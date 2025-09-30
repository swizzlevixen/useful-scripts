(* 
Based on:
AppleScript Mail Rule Template Copyright ( C ) 2011 Apple Inc. All Rights Reserved.

Mail includes the ability to execute an AppleScript script as the action for a Mail rule.  To use, replace the example code with your processing routines, and save as a compiled script. Then create a Mail rule, and assign the script to be the action for the Mail rule.
*)

(*
MONTHLY EMAILS FILTER
This AppleScript is attached to a Mail rule that targets certain "From" email addresses. Every month it starts a log file in ~/Library/Application Support/monthly_emails_filter.txt. If the from email is not already in the log, it leaves the email alone, and adds the email address to the log file. When another email comes from the same email address, matching one already in the log file, the email is automatically deleted.
This is mainly an attempt to keep seeing the occasional promotional email from companies that I do want to keep up with once a month, but otherwise send WAY TOO MANY emails.
*)

using terms from application "Mail"
	on perform mail action with messages these_messages for rule this_rule
		-- Everything has to be inside this "on perform" block
		
		-- Create empty array for email addresses
		set senders to {}
		
		-- check if log file exists
		set logFileName to "monthly_emails_filter.txt"
		set ASpath to (path to application support from user domain)
		set fileTarget to (ASpath as rich text) & logFileName
		
		try
			-- Check if the log file exists
			set fileAlias to fileTarget as alias
			--display dialog (fileAlias as string) & " exists"
			-- Check if it is a new month
			-- If so, we delete the log file and start from scratch
			tell application "Finder"
				set theFileDate to (creation date of fileAlias)
			end tell
			set currentMonth to (month of (current date))
			set fileMonth to (month of theFileDate)
			if currentMonth is not equal to fileMonth then
				-- delete the file
				--display dialog "It's a new month, so deleting the file"
				tell application "Finder" to delete fileTarget
				-- starting over clean for the month, so do not load any data
			else
				-- Load the log file email addresses into the array
				set senders to read file fileTarget using delimiter {","}
				--display dialog "Loaded from file:" & list2string(senders, ",")
			end if
		on error
			display dialog "Error loading, or " & (fileTarget as string) & " does not exist" giving up after 5
		end try
		
		-- Start of the Mail loop
		tell application "Mail"
			set the message_count to the count of these_messages
			repeat with i from 1 to the message_count
				set this_message to item i of these_messages
				
				-- GET THE SENDER email OF THIS MESSAGE
				set this_sender to extract address from sender of this_message
				--display dialog this_sender
				-- check to see if from address is already in the array
				if senders contains this_sender then
					-- if so, delete the email
					--display dialog "sender matched: " & this_sender
					delete this_message
				else
					-- if not, add the email to the array
					-- and leave the email alone. This is the monthly free pass email for this sender
					set end of senders to this_sender
				end if
				
			end repeat
		end tell
		-- end of the Mail loop
		-- save current array of sender emails, as a comma delimited list, overwriting the log file
		try
			--convert the list into a string to be written to file
			set senders_string to list2string(senders, ",")
			--display dialog "Writing this to disk:" & senders_string
			set theOpenedFile to open for access file fileTarget with write permission
			set eof of theOpenedFile to 0
			write senders_string to theOpenedFile starting at eof
			close access theOpenedFile
		on error
			try
				close access file fileTarget
			end try
		end try
		--end of "on perform" block
	end perform mail action with messages
end using terms from

(*
Handler for lists->string with delimiter
*)
on list2string(theList, theDelimiter)
	
	-- First, we store in a variable the current delimiter to restore it later
	set theBackup to AppleScript's text item delimiters
	
	-- Set the new delimiter
	set AppleScript's text item delimiters to theDelimiter
	
	-- Perform the conversion
	set theString to theList as string
	
	-- Restore the original delimiter
	set AppleScript's text item delimiters to theBackup
	
	return theString
	
end list2string
