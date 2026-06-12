-- dashboard.applescript — native window host for the Claude Profiles dashboard.
-- Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
-- See LICENSE and NOTICE in the repository root.
-- Pure macOS built-ins: run by /usr/bin/osascript, no compilation, no dependencies.
-- JS -> native bridge: the page sets document.title to "cp:action:slug";
-- a 0.5s NSTimer polls the title (KVO property, no blocks needed) and acts.
-- Native -> JS: evaluateJavaScript with a missing-value completion handler.
use framework "Foundation"
use framework "AppKit"
use framework "WebKit"
use scripting additions

property theWindow : missing value
property theWebView : missing value
property resourcesDir : missing value
property enginePath : missing value
property launcherPath : missing value
property tickN : 0

on run
	set scriptPath to POSIX path of (path to me)
	set resourcesDir to do shell script "dirname " & quoted form of scriptPath
	set enginePath to resourcesDir & "/engine.sh"
	set launcherPath to resourcesDir & "/../MacOS/launcher"

	current application's NSApplication's sharedApplication()
	current application's NSApp's setActivationPolicy:0

	set frameRect to current application's NSMakeRect(0, 0, 880, 620)
	set theWindow to current application's NSWindow's alloc()'s initWithContentRect:frameRect styleMask:15 backing:2 defer:false
	theWindow's setTitle:"Claude Profiles"
	theWindow's setReleasedWhenClosed:false
	theWindow's setMinSize:(current application's NSMakeSize(620, 420))

	set conf to current application's WKWebViewConfiguration's alloc()'s init()
	set theWebView to current application's WKWebView's alloc()'s initWithFrame:frameRect configuration:conf
	theWebView's setAutoresizingMask:18

	(theWindow's contentView())'s addSubview:theWebView
	set htmlURL to current application's |NSURL|'s fileURLWithPath:(resourcesDir & "/dashboard.html")
	set dirURL to current application's |NSURL|'s fileURLWithPath:resourcesDir
	theWebView's loadFileURL:htmlURL allowingReadAccessToURL:dirURL

	theWindow's |center|()
	theWindow's makeKeyAndOrderFront:(missing value)
	current application's NSApp's activateIgnoringOtherApps:true

	current application's NSTimer's scheduledTimerWithTimeInterval:0.5 target:me selector:"tick:" userInfo:(missing value) repeats:true
	current application's NSApp's run()
end run

on tick:aTimer
	-- quit the host when the window is closed (but not when minimized)
	if ((theWindow's isVisible()) as boolean) is false and ((theWindow's isMiniaturized()) as boolean) is false then
		current application's NSApp's terminate:me
		return
	end if

	-- poll the JS->native channel
	try
		set rawTitle to (theWebView's title()) as text
	on error
		set rawTitle to ""
	end try
	if rawTitle starts with "cp:" then
		theWebView's evaluateJavaScript:"document.title='Claude Profiles'" completionHandler:(missing value)
		my handleAction(rawTitle)
	end if

	-- push fresh stats every 4th tick (every 2s)
	set tickN to tickN + 1
	if (tickN mod 4) is 1 then
		try
			set statsJSON to do shell script quoted form of enginePath & " stats"
			theWebView's evaluateJavaScript:("updateStats(" & statsJSON & ")") completionHandler:(missing value)
		end try
	end if
end tick:

on handleAction(raw)
	set parts to my splitText(raw, ":")
	set verb to item 2 of parts
	set slug to ""
	if (count of parts) > 2 then set slug to item 3 of parts
	try
		if verb is "add" then
			-- reuse the dialog-based creator from the main launcher, async so the window stays live
			do shell script quoted form of launcherPath & " --action add >/dev/null 2>&1 &"
		else if verb is "focus" or verb is "focusdefault" then
			my focusInstance(verb, slug)
		else if verb is "create" then
			-- the name is everything after the second colon (it may itself contain text)
			set theName to my joinFrom(parts, 3, ":")
			do shell script quoted form of enginePath & " create " & quoted form of theName & " >/dev/null 2>&1"
		else if verb is in {"open", "quit", "force", "clean", "remove", "purge"} then
			do shell script quoted form of enginePath & " " & verb & " " & quoted form of slug & " >/dev/null 2>&1 &"
		end if
	end try
	-- nudge a quick stats refresh on the next tick
	set tickN to 0
end handleAction

on focusInstance(verb, slug)
	-- Bring every window of one specific instance to the front. Targets the
	-- process by PID via NSRunningApplication, so it works even though all
	-- instances share Claude's bundle identifier. No permissions required.
	try
		if verb is "focusdefault" then
			set pidText to do shell script quoted form of enginePath & " defaultpid"
		else
			set pidText to do shell script quoted form of enginePath & " mainpid " & quoted form of slug
		end if
		if pidText is "" then return
		set theApp to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:(pidText as integer)
		if theApp is not missing value then
			-- 3 = NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps
			theApp's activateWithOptions:3
		end if
	end try
end focusInstance

on joinFrom(theItems, startIndex, theDelim)
	set acc to ""
	repeat with i from startIndex to (count of theItems)
		if acc is not "" then set acc to acc & theDelim
		set acc to acc & (item i of theItems)
	end repeat
	return acc
end joinFrom

on splitText(theText, theDelim)
	set savedDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelim
	set theItems to text items of theText
	set AppleScript's text item delimiters to savedDelims
	return theItems
end splitText
