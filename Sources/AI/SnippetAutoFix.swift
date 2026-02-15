// SnippetAutoFix.swift — AI-powered automatic repair for broken snippets
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.autofix")

/// Attempts to automatically fix broken snippets by sending the error and source code
/// to Claude and verifying the result doesn't introduce dangerous APIs.
///
/// Safety constraints:
/// - Skips snippets that use dangerous APIs or opt out with `// macotron:no-autofix`
/// - Rate-limited to 3 attempts per 10-minute sliding window
/// - Fixed code is verified via `CapabilityReview` to ensure no capability escalation
@MainActor
public final class SnippetAutoFix {
    private let provider: ClaudeProvider

    /// Timestamps of recent auto-fix attempts for rate limiting.
    /// Protected by MainActor isolation.
    private var attemptTimestamps: [Date] = []

    /// Maximum auto-fix API calls within the rate limit window.
    private let maxAttempts = 3

    /// Duration of the sliding rate-limit window.
    private let windowDuration: TimeInterval = 600 // 10 minutes

    public init(provider: ClaudeProvider) {
        self.provider = provider
    }

    /// Attempt to fix a broken snippet.
    ///
    /// - Parameters:
    ///   - filename: The snippet filename (e.g. "003-tiling.js")
    ///   - source: The current (broken) source code
    ///   - error: The error message produced when the snippet was evaluated
    /// - Returns: The fixed source code, or `nil` if the fix was skipped or failed.
    public func attemptFix(
        filename: String,
        source: String,
        error: String
    ) async -> String? {
        // 1. Capability gate — refuse to auto-fix dangerous or opted-out snippets
        guard CapabilityReview.canAutoFix(source: source) else {
            logger.info("Skipping auto-fix for \(filename): dangerous APIs or no-autofix pragma")
            return nil
        }

        // 2. Rate limit — max 3 attempts per 10-minute window
        pruneExpiredTimestamps()
        guard attemptTimestamps.count < maxAttempts else {
            logger.warning("Auto-fix rate limit reached (\(self.maxAttempts) in \(Int(self.windowDuration))s)")
            return nil
        }
        attemptTimestamps.append(Date())

        // 3. Record which APIs the original snippet uses so we can verify the fix
        let originalManifest = CapabilityReview.review(source)

        // 4. Build the prompt
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(filename: filename, source: source, error: error)

        let options = AIRequestOptions(
            maxTokens: 4096,
            temperature: 0.2,
            systemPrompt: systemPrompt
        )

        // 5. Call Claude (simple text completion, no tools)
        let fixedCode: String
        do {
            let response = try await provider.chat(prompt: userPrompt, options: options)
            guard let extracted = extractCodeBlock(from: response) else {
                logger.warning("Auto-fix response for \(filename) did not contain a code block")
                return nil
            }
            fixedCode = extracted
        } catch {
            logger.error("Auto-fix API call failed for \(filename): \(error)")
            return nil
        }

        // 6. Verify the fix doesn't escalate capabilities
        let fixedManifest = CapabilityReview.review(fixedCode)

        let newDangerousAPIs = fixedManifest.apisUsed.subtracting(originalManifest.apisUsed)
            .filter { api in CapabilityReview.dangerousPatterns.contains(where: { api.contains($0) }) }

        if !newDangerousAPIs.isEmpty {
            logger.warning(
                "Auto-fix for \(filename) rejected: introduced dangerous APIs: \(newDangerousAPIs)"
            )
            return nil
        }

        // Also reject if the fix escalates the overall tier beyond the original
        if fixedManifest.tier > originalManifest.tier {
            logger.warning(
                "Auto-fix for \(filename) rejected: escalated tier from \(String(describing: originalManifest.tier)) to \(String(describing: fixedManifest.tier))"
            )
            return nil
        }

        logger.info("Auto-fix for \(filename) succeeded")
        return fixedCode
    }

    // MARK: - Private

    /// Remove timestamps older than the rate-limit window.
    private func pruneExpiredTimestamps() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        attemptTimestamps.removeAll { $0 < cutoff }
    }

    /// Build the system prompt that instructs Claude how to fix snippets.
    private func buildSystemPrompt() -> String {
        """
        You are Macotron's snippet auto-repair system. Your sole task is to fix JavaScript \
        snippets that failed to load due to syntax or runtime errors.

        RULES:
        - Return ONLY the fixed JavaScript code inside a single ```javascript code block.
        - Do NOT add any explanation, commentary, or markdown outside the code block.
        - Do NOT add any API calls that were not in the original code.
        - Do NOT add any of these dangerous APIs under any circumstances: \
        shell.run, fs.write, fs.delete, fs.remove, http.post, http.put, http.delete, \
        keychain.set, keychain.delete, url.registerHandler.
        - Preserve the original intent and behavior of the snippet.
        - Preserve the original first-line comment describing the snippet.
        - Fix only what is broken. Make the minimal change necessary.
        - If you cannot determine how to fix the error, return the original code unchanged \
        inside the code block.
        """
    }

    /// Build the user-facing prompt with the error and source.
    private func buildUserPrompt(filename: String, source: String, error: String) -> String {
        """
        The following Macotron snippet failed to load. Please fix it.

        **Filename:** \(filename)

        **Error:**
        ```
        \(error)
        ```

        **Source code:**
        ```javascript
        \(source)
        ```
        """
    }

    /// Extract the contents of the first ```javascript ... ``` code block from the response.
    /// Falls back to extracting any ``` ... ``` block if no javascript-tagged block is found.
    private func extractCodeBlock(from response: String) -> String? {
        // Try ```javascript first
        if let range = extractFencedBlock(from: response, language: "javascript") {
            return String(response[range])
        }
        // Fallback: any fenced block
        if let range = extractFencedBlock(from: response, language: nil) {
            return String(response[range])
        }
        // Last resort: if the entire response looks like JS (no markdown), return it trimmed
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("*") {
            return trimmed
        }
        return nil
    }

    /// Extract the content range of a fenced code block.
    private func extractFencedBlock(from text: String, language: String?) -> Range<String.Index>? {
        let opener: String
        if let lang = language {
            opener = "```\(lang)"
        } else {
            opener = "```"
        }
        let closer = "```"

        guard let openRange = text.range(of: opener) else { return nil }

        // Start of content is the line after the opener
        let afterOpener = openRange.upperBound
        guard let newlineAfterOpener = text[afterOpener...].firstIndex(of: "\n") else { return nil }
        let contentStart = text.index(after: newlineAfterOpener)

        // Find the closing ``` after the content start
        guard let closeRange = text[contentStart...].range(of: closer) else { return nil }
        let contentEnd = closeRange.lowerBound

        guard contentStart < contentEnd else { return nil }

        // The content is everything between the opening fence line and the closing fence.
        // Trim a single trailing newline if present (the one right before ```).
        var end = contentEnd
        if end > contentStart {
            let prev = text.index(before: end)
            if text[prev] == "\n" {
                end = prev
                // Also trim \r in \r\n
                if end > contentStart {
                    let prev2 = text.index(before: end)
                    if text[prev2] == "\r" {
                        end = prev2
                    }
                }
            }
        }

        guard contentStart <= end else { return nil }
        return contentStart..<end
    }
}
