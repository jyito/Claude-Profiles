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
property pollTimer : missing value
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
	-- actions poll at 250ms so clicks feel instant; stats stay on the 2s idle tick
	set pollTimer to current application's NSTimer's scheduledTimerWithTimeInterval:0.25 target:me selector:"checkBridge:" userInfo:(missing value) repeats:true
end setupWindow

on checkBridge:aTimer
	if not didSetup then return
	try
		set rawTitle to ""
		try
			set rawTitle to (theWebView's title()) as text
		end try
		if rawTitle starts with "cp:" then
			theWebView's evaluateJavaScript:"document.title='Claude Profiles'" completionHandler:(missing value)
			my handleAction(rawTitle)
			my pushStats()
		end if
	end try
end checkBridge:

on pushStats()
	try
		set statsJSON to do shell script quoted form of enginePath & " stats"
		theWebView's evaluateJavaScript:("updateStats(" & statsJSON & ")") completionHandler:(missing value)
	end try
end pushStats

on pushTerminals(slug)
	-- slug is sanitized to [a-z0-9] by the engine, so it is safe to inline.
	try
		set tjson to do shell script quoted form of enginePath & " terminals " & quoted form of slug
		theWebView's evaluateJavaScript:("updateTerminals('" & slug & "'," & tjson & ")") completionHandler:(missing value)
	end try
end pushTerminals

on idle
	if not didSetup then return 2
	try
		-- quit when the window is closed (but not when minimized)
		if ((theWindow's isVisible()) as boolean) is false and ((theWindow's isMiniaturized()) as boolean) is false then
			if pollTimer is not missing value then pollTimer's invalidate()
			quit
			return 2
		end if
		my pushStats()
	end try
	return 2
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
		else if verb is "terminals" then
			my pushTerminals(slug)
		else if verb is "closeterm" then
			set tdev to ""
			if (count of parts) > 3 then set tdev to item 4 of parts
			do shell script quoted form of enginePath & " closeterm " & quoted form of slug & " " & quoted form of tdev & " >/dev/null 2>&1 &"
		else if verb is in {"quitall", "cleanall", "killswitch"} then
			do shell script quoted form of enginePath & " " & verb & " >/dev/null 2>&1 &"
		else if verb is in {"opendefault", "quitdefault", "forcedefault"} then
			do shell script quoted form of enginePath & " " & verb & " >/dev/null 2>&1 &"
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
			-- macOS 14+ cooperative activation: yield our active status to the
			-- target first so the polite request below is actually honored.
			-- (Selector is 14+-only; the try keeps older macOS working.)
			try
				(current application's NSApplication's sharedApplication())'s yieldActivationToApplication:theApp
			end try
			theApp's activateWithOptions:3
			delay 0.3
			if not ((theApp's isActive()) as boolean) then
				-- macOS 14+ cooperative activation can ignore the polite request,
				-- especially across Spaces, displays, and fullscreen windows.
				-- System Events' frontmost reliably travels there (asks for
				-- Automation permission once, the first time it's needed).
				try
					tell application "System Events"
						set frontmost of (first application process whose unix id is (pidText as integer)) to true
					end tell
				end try
			end if
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
