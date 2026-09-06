// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   RELEASING.md, "Before any of it: type with it" — the step this exists to make possible.
//   SPEC.md A.9 for what it was worth and what it cost to find.

// Posts a real mouse click at a point on the Mac's screen, so that a script can press a
// key on a simulator's keyboard.
//
// The obvious way — AppleScript's `tell application "System Events" to click at {x, y}` —
// does not do this. That click is delivered through the accessibility layer: it lands only
// on elements the app under the cursor exposes, and it lands at their centre rather than
// where it was aimed. A keyboard's letter caps carry labels and answer it; shift, delete,
// space and the globe drew images and swallowed every click, which reads exactly like a
// keyboard whose bottom rows are dead. A `CGEvent` posted to the HID event tap has no such
// filter: the Simulator receives it as a mouse event and turns it into a touch wherever it
// is aimed.
//
//     swiftc -O -o tap tools/tap.swift
//     ./tap 698 986        # a tap
//     ./tap 698 986 1100   # a long press, in milliseconds
//
// Coordinates are the Mac's global screen points. `tools/keys.sh` converts from the device
// points that screenshots are measured in, which is usually what you want.

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
  FileHandle.standardError.write(Data("usage: tap <x> <y> [holdMilliseconds]\n".utf8))
  exit(2)
}

// Long enough to register as a press, short enough not to be a long press. iOS starts the
// keyboard list at about half a second, so the default sits well under that.
let hold = arguments.count > 3 ? (Double(arguments[3]) ?? 60) : 60
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType) {
  CGEvent(
    mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left,
  )?.post(tap: .cghidEventTap)
}

// The move comes first and separately: a down event at a point the cursor has not reached
// is delivered, but the Simulator's own hit-testing reads the cursor position, so the two
// have to happen in that order with a moment between them.
post(.mouseMoved)
usleep(30_000)
post(.leftMouseDown)
usleep(UInt32(hold * 1000))
post(.leftMouseUp)
