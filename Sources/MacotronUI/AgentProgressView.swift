// AgentProgressView.swift — SwiftUI view for the agent progress panel
import SwiftUI

/// Observable state for the agent progress display
@MainActor
public final class AgentProgressState: ObservableObject {
    @Published public var topic: String = ""
    @Published public var statusText: String = "Planning..."
    @Published public var isComplete: Bool = false
    @Published public var success: Bool = true

    public init() {}

    public func reset(topic: String) {
        self.topic = topic
        self.statusText = "Planning..."
        self.isComplete = false
        self.success = true
    }
}

/// Compact progress view: topic line + animated status text with checkmark/x
public struct AgentProgressView: View {
    @ObservedObject var state: AgentProgressState

    public init(state: AgentProgressState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Topic line
            Text(state.topic)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Status line
            HStack(spacing: 6) {
                if state.isComplete {
                    Image(systemName: state.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(state.success ? .green : .red)
                        .font(.system(size: 14))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                if state.isComplete {
                    Text(state.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    ShinyText(text: state.statusText)
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

/// Gradient shimmer animation on text — gives an AI/processing feel
struct ShinyText: View {
    let text: String
    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: phase)
                .mask(
                    Text(text)
                        .font(.system(size: 12))
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 250
                }
            }
    }
}
