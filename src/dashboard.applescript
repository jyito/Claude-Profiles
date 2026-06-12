-- dashboard.applescript — native window host for the Claude Profiles dashboard.
-- Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
-- See LICENSE and NOTICE in the repository root.
--
-- This source is compiled at launch into a stay-open applet by the manager
-- (osacompile -s), because applets run handlers on the MAIN thread — which
-- AppKit and WebKit require for window creation — while plain `osascript`
-- runs scripts on a background thread. The applet's `on idle` loop drives
-- stats refresh and the JS->native bridge (the page sets document.title to
-- "cp:verb[:arg]"; we poll the title, a KVO-readable property — no blocks,
-- no subclasses, no permissions).
--
-- __RESOURCES__ is substituted with the manager's Resources path at compile.
use framework "Foundation"
use framework "AppKit"
use framework "WebKit"
use scripting additions

property theWindow : missing value
property theWebView : missing value
property resourcesDir : "__RESOURCES__"
property enginePath : "__RESOURCES__/engine.sh"
property tickN : 0
property didSetup : false

on run
	try
		my setupWindow()
		set didSetup to true
	on error errMsg number errNum
		display alert "Claude Profiles" message ("The dashboard window failed to open (" & errNum & "): " & errMsg & return & return & "Run the app with --classic for the dialog menu, and please report this.") as critical buttons {"OK"} default button "OK"
		quit
	end try
end run

on setupWindow()
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
	activate
end setupWindow

on idle
	if not didSetup then return 1
	try
		-- quit when the window is closed (but not when minimized)
		if ((theWindow's isVisible()) as boolean) is false and ((theWindow's isMiniaturized()) as boolean) is false then
			quit
			return 1
		end if

		-- poll the JS -> native channel
		set rawTitle to ""
		try
			set rawTitle to (theWebView's title()) as text
		end try
		if rawTitle starts with "cp:" then
			theWebView's evaluateJavaScript:"document.title='Claude Profiles'" completionHandler:(missing value)
			my handleAction(rawTitle)
			set tickN to 0
		end if

		-- push fresh stats every other idle (~2s)
		set tickN to tickN + 1
		if (tickN mod 2) is 1 then
			try
				set statsJSON to do shell script quoted form of enginePath & " stats"
				theWebView's evaluateJavaScript:("updateStats(" & statsJSON & ")") completionHandler:(missing value)
			end try
		end if
	end try
	return 1
end idle

on handleAction(raw)
	set parts to my splitText(raw, ":")
	set verb to item 2 of parts
	set slug to ""
	if (count of parts) > 2 then set slug to item 3 of parts
	try
		if verb is "create" then
			set theName to my joinFrom(parts, 3, ":")
			do shell script quoted form of enginePath & " create " & quoted form of theName & " >/dev/null 2>&1"
		else if verb is "focus" or verb is "focusdefault" then
			my focusInstance(verb, slug)
		else if verb is in {"open", "quit", "force", "clean", "remove", "purge"} then
			do shell script quoted form of enginePath & " " & verb & " " & quoted form of slug & " >/dev/null 2>&1 &"
		end if
	end try
end handleAction

on focusInstance(verb, slug)
	try
		if verb is "focusdefault" then
			set pidText to do shell script quoted form of enginePath & " defaultpid"
		else
			set pidText to do shell script quoted form of enginePath & " mainpid " & quoted form of slug
		end if
		if pidText is "" then return
		set theApp to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:(pidText as integer)
		if theApp is not missing value then
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
