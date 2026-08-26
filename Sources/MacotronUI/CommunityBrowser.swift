// CommunityBrowser.swift — The Community tab of the plugin catalog sheet.
import AppKit
import MacotronEngine
import SwiftUI

struct CommunityBrowser: View {
    @ObservedObject var state: SettingsState
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PluginSearchField(text: $query)
                Button {
                    state.loadCommunity(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(state.communityLoading)
                .help("Search GitHub again")
            }

            content
        }
        .task { state.loadCommunity() }
    }

    @ViewBuilder
    private var content: some View {
        if state.communityLoading, state.communityEntries.isEmpty {
            centered {
                ProgressView()
                    .controlSize(.small)
                Text("Searching GitHub…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = state.communityError, state.communityEntries.isEmpty {
            centered {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again") { state.loadCommunity(force: true) }
                    .controlSize(.small)
            }
        } else if filtered.isEmpty {
            centered {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(state.communityEntries.isEmpty
                     ? "No repositories carry the macotron-plugin topic yet."
                     : "Nothing matches “\(query)”.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtered) { entry in
                        CommunityRow(
                            entry: entry,
                            status: state.communityStatus(entry),
                            busy: state.installingRepo == entry.repo,
                            onAdd: { state.beginCommunityInstall(entry) }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
            .overlay(alignment: .top) {
                if let error = state.communityError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ body: () -> Content) -> some View {
        VStack(spacing: 10) { body() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    /// Fuzzy over the title, the repository, and the description. GitHub already
    /// sorted by stars, so an empty query keeps that order.
    private var filtered: [CommunityEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return state.communityEntries }
        return state.communityEntries
            .compactMap { entry -> (CommunityEntry, Int)? in
                guard let score = FuzzyMatch.best(
                    query: q,
                    targets: [entry.title, entry.repo, entry.summary]
                ) else { return nil }
                return (entry, score)
            }
            .sorted { $0.1 == $1.1 ? $0.0.stars > $1.0.stars : $0.1 > $1.1 }
            .map(\.0)
    }
}

public enum CommunityStatus: Equatable {
    case available
    case installed
    case updatable
}

private struct CommunityRow: View {
    let entry: CommunityEntry
    let status: CommunityStatus
    let busy: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Label(entry.owner, systemImage: "person.crop.circle")
                    Label("\(entry.stars)", systemImage: "star")
                    if let pushed = entry.pushedAt {
                        Label(Self.relative.localizedString(for: pushed, relativeTo: .now),
                              systemImage: "clock")
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(label, action: onAdd)
                        .controlSize(.small)
                        .disabled(status == .installed)
                }
                Button {
                    NSWorkspace.shared.open(entry.homepage)
                } label: {
                    Text("GitHub")
                        .font(.system(size: 10))
                }
                .buttonStyle(.link)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private var label: String {
        switch status {
        case .available: return "Add"
        case .installed: return "Added"
        case .updatable: return "Update"
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

/// Says plainly where the bytes came from. Community plugins run with the same
/// access as Macotron itself, and the app cannot restrict them.
struct CommunityProvenance: View {
    let origin: CommunityOrigin

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloaded from \(origin.repo)")
                    .font(.callout.weight(.medium))
                Text("Written by \(origin.owner), not by Macotron. It runs with the same access this app has.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
    }
}

enum CatalogSection: Int, CaseIterable, Identifiable {
    case builtIn
    case community

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .builtIn: return "Built-In"
        case .community: return "Community"
        }
    }
}
