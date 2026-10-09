tell application "Calendar"
	set s to (current date) + 8 * minutes
	tell calendar 1 to make new event with properties {summary:"Design review", start date:s, end date:s + 30 * minutes, location:"https://zoom.us/j/5550123456", url:"https://zoom.us/j/5550123456"}
	set s2 to (current date) + 95 * minutes
	tell calendar 1 to make new event with properties {summary:"1:1 with Sam", start date:s2, end date:s2 + 30 * minutes, url:"https://meet.google.com/abc-defg-hij"}
	return name of calendar 1
end tell
