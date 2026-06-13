-- badge-icon.applescript — composite a small colored badge (a profile's initial
-- on a colored disc) onto a base app icon, so multi-account wrappers are
-- distinguishable in the Dock/Spotlight while still reading as Claude.
--
-- Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
-- See LICENSE and NOTICE in the repository root.
--
-- Zero-dependency: AppleScriptObjC draws into a headless NSBitmapImageRep
-- context (no window, no main thread needed — runs fine under plain osascript),
-- exactly like the rest of this project. Run:
--
--   osascript badge-icon.applescript <basePNG> <outPNG> <LETTER> <r> <g> <b>
--
-- where r/g/b are 0–255. The base should be a square PNG (1024×1024 ideal); the
-- badge geometry is expressed in 1024-px units and scales with the base.
--
-- Reserved-word traps escaped with pipes: `|set|` (NSColor set) and
-- `|properties|` (representationUsingType:properties:). `by` is also reserved,
-- so the badge's y-origin is `py`.
use framework "Foundation"
use framework "AppKit"
use scripting additions

on run argv
	set basePath to item 1 of argv
	set outPath to item 2 of argv
	set letter to item 3 of argv
	set rr to (item 4 of argv as number) / 255
	set gg to (item 5 of argv as number) / 255
	set bb to (item 6 of argv as number) / 255

	set S to 1024
	set baseImg to current application's NSImage's alloc()'s initWithContentsOfFile:basePath
	if baseImg is missing value then error "cannot read base image: " & basePath

	set bmp to current application's NSBitmapImageRep's alloc()'s initWithBitmapDataPlanes:(missing value) pixelsWide:S pixelsHigh:S bitsPerSample:8 samplesPerPixel:4 hasAlpha:true isPlanar:false colorSpaceName:(current application's NSCalibratedRGBColorSpace) bytesPerRow:0 bitsPerPixel:0
	set ctx to current application's NSGraphicsContext's graphicsContextWithBitmapImageRep:bmp
	current application's NSGraphicsContext's saveGraphicsState()
	current application's NSGraphicsContext's setCurrentContext:ctx

	-- base icon, full canvas
	baseImg's drawInRect:(current application's NSMakeRect(0, 0, S, S)) fromRect:(current application's NSZeroRect) operation:2 fraction:1.0

	-- badge in the bottom-right corner (AppKit origin is bottom-left)
	set d to 380
	set m to 44
	set px to S - d - m
	set py to m

	-- dark separator ring so the disc reads against any icon colour
	set ringInset to 16
	(current application's NSColor's colorWithCalibratedRed:0.102 green:0.098 blue:0.082 alpha:1.0)'s |set|()
	(current application's NSBezierPath's bezierPathWithOvalInRect:(current application's NSMakeRect(px - ringInset, py - ringInset, d + ringInset * 2, d + ringInset * 2)))'s fill()

	-- coloured disc
	(current application's NSColor's colorWithCalibratedRed:rr green:gg blue:bb alpha:1.0)'s |set|()
	(current application's NSBezierPath's bezierPathWithOvalInRect:(current application's NSMakeRect(px, py, d, d)))'s fill()

	-- the profile's initial, white, roughly centred in the disc
	set theFont to current application's NSFont's boldSystemFontOfSize:228
	set wht to current application's NSColor's whiteColor()
	set attrs to current application's NSDictionary's dictionaryWithObjects:{theFont, wht} forKeys:{current application's NSFontAttributeName, current application's NSForegroundColorAttributeName}
	set txt to current application's NSString's stringWithString:letter
	txt's drawAtPoint:(current application's NSMakePoint(px + 122, py + 78)) withAttributes:attrs

	(current application's NSGraphicsContext's currentContext())'s flushGraphics()
	current application's NSGraphicsContext's restoreGraphicsState()

	set png to bmp's representationUsingType:4 |properties|:(current application's NSDictionary's dictionary())
	(png's writeToFile:outPath atomically:true)
	return "ok"
end run
