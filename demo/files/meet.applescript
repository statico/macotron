tell application "Calendar"
	tell calendar 1 to delete (every event whose summary is "Design review")
	set s to (current date) + 50
	tell calendar 1 to make new event with properties {summary:"Design review", start date:s, end date:s + 30 * minutes, location:"https://zoom.us/j/5550123456", url:"https://zoom.us/j/5550123456"}
	return s as string
end tell
