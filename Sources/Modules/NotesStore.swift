import Foundation

enum NotesStore {
    static func list() -> [NoteRecord] {
        // A note only reports its immediate folder, and a deleted folder keeps
        // its own name, so collect the trashed folders first and match on those.
        let source = """
        tell application "Notes"
            set trashIDs to {}
            repeat with aFolder in folders
                set aContainer to aFolder
                repeat 8 times
                    if name of aContainer is "Recently Deleted" then
                        set end of trashIDs to id of aFolder
                        exit repeat
                    end if
                    try
                        set aContainer to container of aContainer
                    on error
                        exit repeat
                    end try
                end repeat
            end repeat

            set theOut to ""
            repeat with aNote in notes
                set folderName to ""
                set folderID to ""
                try
                    set aContainer to container of aNote
                    set folderName to name of aContainer
                    set folderID to id of aContainer
                end try
                if trashIDs does not contain folderID then
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
