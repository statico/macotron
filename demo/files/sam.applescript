tell application "Calendar"
	tell calendar 1 to delete (every event whose summary is "1:1 with Sam")
	set s to (current date) + 180 * minutes
	tell calendar 1 to make new event with properties {summary:"1:1 with Sam", start date:s, end date:s + 30 * minutes, url:"https://meet.google.com/abc-defg-hij"}
	quit
end tell
