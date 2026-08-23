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

            -- Asking each note for its own id, name and container is three
            -- Apple Events per note, which is minutes of round trips once a
            -- library runs to thousands. Ask each folder for all of its notes
            -- at once instead: a handful of events whatever the note count.
            set theOut to {}
            repeat with aFolder in folders
                if trashIDs does not contain (id of aFolder) then
                    set theIDs to id of notes of aFolder
                    set theNames to name of notes of aFolder
                    set AppleScript's text item delimiters to tab
                    set end of theOut to (name of aFolder) & linefeed & ¬
                        (theIDs as text) & linefeed & (theNames as text)
                    set AppleScript's text item delimiters to ""
                end if
            end repeat
            set AppleScript's text item delimiters to (ASCII character 1)
            set theText to theOut as text
            set AppleScript's text item delimiters to ""
            return theText
        end tell
        """
        return NotesList.parseFolders(run(source) ?? "")
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
