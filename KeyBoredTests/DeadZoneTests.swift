// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import CoreGraphics
import UIKit
import Testing

@testable import KeyBored

/// **Every point on the keyboard belongs to a key.**
///
/// Reported 2026-09-06: "Has dead zones where tapping doesn't trigger a key which is just
/// incorrect... Every tap should trigger a key press". It is the principle the source book
/// for this project is about — the drawn cap is not the touch target, and stock's caps are
/// drawn inset inside regions that tile the whole surface, so the 18px between two caps
/// and the 33px between two rows belong to somebody.
///
/// This sweeps rather than sampling named points: a test that asserts particular points
/// hit particular keys passes while the gaps between them are dead.
@Test(arguments: [390.0, 402.0, 430.0, 440.0] as [CGFloat])
func everyPointOnTheKeyboardResolvesToAKey(width: CGFloat) {
  for plane in [Plane.letters, .numbers, .symbols] {
    let geometry = KeyboardGeometry(width: width, plane: plane)
    let top = StockMetrics.suggestionBarHeight
    var dead: [CGPoint] = []
    var y = top
    while y <= geometry.height {
      var x: CGFloat = 0
      while x <= width {
        if geometry.hitTest(CGPoint(x: x, y: y)) == nil { dead.append(CGPoint(x: x, y: y)) }
        x += 1
      }
      y += 1
    }
    #expect(
      dead.isEmpty,
      "\(dead.count) dead points at width \(width) on \(plane), first \(dead.first.map(String.init(describing:)) ?? "-")")
  }
}

/// **And every point reaches the view that resolves them.**
///
/// The sweep above tests `KeyboardGeometry`, which was never the defect: it assigned every
/// coordinate to a key while UIKit was deciding, before any of that ran, that a touch
/// landing between two caps belonged to no view at all. So this sweeps the other half —
/// `UIView.hitTest`, the question UIKit actually asks — and asserts the keyboard view
/// claims every point in its own bounds.
///
/// A test of the resolution alone would have passed on 0.0.5, and did.
@MainActor
@Test func everyPointOnTheKeyboardReachesTheKeyboardView() {
  let width: CGFloat = 402
  let controller = KeyboardController(
    width: width, lexicon: EnglishLexicon.make(), document: DeadZoneSink())
  let view = KeyboardView(
    frame: CGRect(x: 0, y: 0, width: width, height: StockMetrics.totalHeight(forWidth: width)))
  view.apply(controller, needsNextKeyboard: false)
  view.layoutIfNeeded()

  // Exclusive at the far edges, because `CGRect.contains` is: a point at exactly maxX or
  // maxY is outside the rectangle and belongs to whatever is next, which is what should
  // happen to a touch on the boundary.
  var unreachable: [CGPoint] = []
  var y: CGFloat = 0
  while y < view.bounds.height {
    var x: CGFloat = 0
    while x < width {
      if view.hitTest(CGPoint(x: x, y: y), with: nil) !== view {
        unreachable.append(CGPoint(x: x, y: y))
      }
      x += 1
    }
    y += 1
  }
  #expect(
    unreachable.isEmpty,
    "\(unreachable.count) points do not reach the keyboard view, first \(unreachable.first.map(String.init(describing:)) ?? "-")")
}

/// The other half of the same defect, and the half no hit test can see.
///
/// A keyboard extension is composited by a process that decides which touches to forward
/// by what was drawn, so a fully transparent region of this view is not reachable by a
/// finger however the view hit-tests. That decision is made outside this process and
/// cannot be exercised from a test, so what is asserted here is the property the fix
/// rests on: the view fills its own bounds with something that is not transparent. If
/// somebody sets this background to `.clear` again for tidiness, the gaps between the
/// caps go dead again and nothing else in the suite notices. See
/// `KeyboardView.touchableFill`.
@MainActor
@Test func theKeyboardFillsItsOwnBoundsSoTheGapsCanBeTouched() {
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: 260))
  guard let fill = view.backgroundColor else {
    Issue.record("the keyboard view has no background colour at all")
    return
  }
  #expect(
    fill.cgColor.alpha > 0,
    "the keyboard view's background is transparent, so its gaps are dead")
}

/// A document that swallows everything, so the view can be built without a host.
private final class DeadZoneSink: TextDocument {
  var text = ""
  var textBeforeInput: String? { text }
  var traits: DocumentTraits = .unspecified
  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}
