import Foundation

enum NotesStore {
    static func list() -> [NoteRecord] {
        let source = """
        tell application "Notes"
            set theOut to ""
            repeat with aNote in notes
                set folderName to ""
                try
                    set folderName to name of container of aNote
                end try
                if folderName is not "Recently Deleted" then
                    set theOut to theOut & (id of aNote) & tab & (name of aNote) & tab & folderName & linefeed
                end if
            end repeat
            return theOut
        end tell
        """
        return NotesList.parse(run(source) ?? "")
    }

    static func open(_ id: String) {
        let escaped = NotesList.escape(id)
        let source = """
        tell application "Notes"
            show (note id "\(escaped)")
            activate
        end tell
        """
        _ = run(source)
    }

    private static func run(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
