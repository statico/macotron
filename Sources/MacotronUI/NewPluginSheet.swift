import MacotronEngine
import SwiftUI

struct NewPluginSheet: View {
    let existing: Set<String>
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""

    private var filename: String? { PluginDraft.filename(for: title) }
    private var duplicate: Bool { filename.map(existing.contains) ?? false }
    private var canCreate: Bool { filename != nil && !duplicate }

    private var hint: String {
        guard let filename else { return "Macotron writes a .js file in the plugins folder." }
        if duplicate { return "\(filename) already exists." }
        return "Creates \(filename) and opens it."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Plugin")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(duplicate ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let filename, canCreate else { return }
                    onCreate(filename, PluginDraft.source(title: title))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
