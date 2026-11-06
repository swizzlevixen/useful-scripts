-- Crop and print 4x6" shipping labels from PDF attachments of Mail messages
-- Created by Mark Boszko on 2025-07-20
-- Copyright (c) 2025-2026 Mark Boszko. All rights reserved.
--
-- This one script works two ways:
--
--   1. From the Script Menu in Mail (install in ~/Library/Scripts/Applications/Mail/):
--      processes the selected messages and reports with dialogs.
--
--   2. As a Mail rule action (install in ~/Library/Application Scripts/com.apple.mail/):
--      Mail calls the "perform mail action" handler with the matching messages;
--      results are reported with notifications, since a rule can't block Mail with a dialog.
--
-- Each PDF attachment is saved to the temporary folder and handed to the shell script,
-- which finds the 4x6" label on the page, crops to it, and prints it. If no label is
-- found, the shell script opens its best-effort crop in Preview for manual handling.

-- Where the shell script lives. Mail rule scripts see the real home folder, so ~ is fine.
property shellScript : "~/Applications/crop_pdf_and_print_label.sh"

-- Script Menu entry point
on run
	try
		tell application "Mail" to set theMessages to the selection
		if (count of theMessages) < 1 then error "One or more messages must be selected."
		set theReport to my processMessages(theMessages)
		my showReport(theReport, true)
	on error errMsg number errNum
		if errNum is not -128 then -- -128 is User Canceled
			tell application "Mail" to activate
			display alert "Error " & (errNum as string) message errMsg as warning
		end if
	end try
end run

-- Mail rule entry point
using terms from application "Mail"
	on perform mail action with messages theMessages for rule theRule
		try
			set theReport to my processMessages(theMessages)
			my showReport(theReport, false)
		on error errMsg number errNum
			display notification errMsg with title "Crop and Print 4x6 Label" subtitle "Error " & (errNum as string)
		end try
	end perform mail action with messages
end using terms from

-- Save each PDF attachment and run the shell script on it.
-- Returns {pdfs:n, printed:{names}, notFound:{names}, failed:{names & reasons}}
on processMessages(theMessages)
	set printedList to {}
	set notFoundList to {}
	set failedList to {}
	set pdfCount to 0
	-- Save attachments under ~/Library/Application Support/Mail/, not Mail's sandbox temp
	-- folder: when a rule runs, the shell script and Ghostscript are children of the
	-- script runner and get "Operation not permitted" reading inside Mail's container.
	-- Mail's sandbox is allowed to write here, and everything else can read it.
	set theFolder to (POSIX path of (path to application support from user domain)) & "Mail/Crop and Print 4x6 Label/"
	do shell script "mkdir -p " & quoted form of theFolder
	tell application "Mail"
		repeat with theMessage in theMessages
			repeat with theAttachment in mail attachments of theMessage
				set attName to name of theAttachment
				set isPDF to false
				try
					if (MIME type of theAttachment is "application/pdf") or (attName ends with ".pdf") then set isPDF to true
				on error
					if attName ends with ".pdf" then set isPDF to true
				end try
				if isPDF then
					set pdfCount to pdfCount + 1
					set theFile to theFolder & attName
					try
						if not (downloaded of theAttachment) then error "Attachment has not been downloaded yet."
						save theAttachment in theFile
						my waitForFile(theFile)
						-- Exit 0: label found and printed. Exit 3: no 4x6" label; opened in Preview.
						do shell script shellScript & " " & quoted form of theFile
						set end of printedList to attName
					on error errMsg number errNum
						if errNum is 3 then
							set end of notFoundList to attName
						else
							set end of failedList to attName & ": " & errMsg
						end if
					end try
				end if
			end repeat
		end repeat
	end tell
	return {pdfs:pdfCount, printed:printedList, notFound:notFoundList, failed:failedList}
end processMessages

-- Mail may still be writing a saved attachment when "save" returns. Wait until the
-- file exists and its size has stopped changing (up to about 10 seconds).
on waitForFile(thePath)
	set lastSize to -1
	repeat 20 times
		try
			set thisSize to (do shell script "stat -f %z " & quoted form of thePath) as integer
		on error
			set thisSize to -1
		end try
		if thisSize > 0 and thisSize is lastSize then return
		set lastSize to thisSize
		delay 0.5
	end repeat
end waitForFile

-- Tell the user what happened: dialogs when run by hand, notifications from a rule.
on showReport(theReport, interactive)
	set theTitle to "Crop and Print 4x6 Label"
	if interactive then
		if pdfs of theReport is 0 then
			set theText to "No PDF attachments found."
		else
			set theText to ((count of printed of theReport) as string) & " of " & ((pdfs of theReport) as string) & " PDF(s) printed."
		end if
		if (count of notFound of theReport) > 0 then
			set theText to theText & return & return & "No 4×6\" label found (opened in Preview):" & return & my joinList(notFound of theReport, return)
		end if
		if (count of failed of theReport) > 0 then
			set theText to theText & return & return & "Failed:" & return & my joinList(failed of theReport, return)
		end if
		tell application "Mail" to activate
		if (count of failed of theReport) > 0 then
			display alert theTitle message theText as warning
		else
			display dialog theText with title theTitle buttons {"OK"} default button 1 giving up after 10
		end if
	else
		-- Rule mode: stay quiet unless a PDF was actually handled.
		repeat with n in printed of theReport
			display notification "Printed " & n with title theTitle
			my logLine("Printed " & n)
		end repeat
		repeat with n in notFound of theReport
			display notification "No 4×6\" label found in " & n & "; opened in Preview." with title theTitle subtitle "Check and print manually"
			my logLine("No label found: " & n)
		end repeat
		repeat with f in failed of theReport
			display notification (f as string) with title theTitle subtitle "Failed"
			my logLine("FAILED " & (f as string))
		end repeat
		if (pdfs of theReport) is 0 then my logLine("Rule fired; no PDF attachments.")
	end if
end showReport

-- Rule mode can only show a one-line notification, so keep a log of what happened:
-- ~/Library/Logs/Crop and Print 4x6 Label.log (falls back to the temporary items folder)
on logLine(theText)
	set entry to ((current date) as string) & linefeed & theText & linefeed & linefeed
	set logName to "Crop and Print 4x6 Label.log"
	try
		do shell script "printf '%s' " & quoted form of entry & " >> ~/Library/Logs/" & quoted form of logName
	on error
		try
			tell application "Mail" to set tmpFolder to POSIX path of (path to temporary items)
			do shell script "printf '%s' " & quoted form of entry & " >> " & quoted form of (tmpFolder & logName)
		end try
	end try
end logLine

on joinList(theList, theDelimiter)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theString to theList as string
	set AppleScript's text item delimiters to oldDelimiters
	return theString
end joinList
