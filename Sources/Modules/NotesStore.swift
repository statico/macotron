import Foundation

enum NotesStore {
    static func list() -> [NoteRecord] {
        let source = """
        tell application "Notes"
            if (count of notes) is 0 then return ""
            set theIds to id of notes
            set theNames to name of notes
            set theOut to ""
            repeat with i from 1 to (count of theIds)
                set theOut to theOut & (item i of theIds) & tab & (item i of theNames) & linefeed
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
