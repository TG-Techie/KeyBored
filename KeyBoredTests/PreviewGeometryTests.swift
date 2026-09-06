// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md Appendix A.19 for where the preview's proportions came from, and for why the
//   top row's preview cannot have the size stock gives it.

import Testing
import UIKit

@testable import KeyBored

/// **A preview belongs to a key, and it ends on that key.**
///
/// This is the invariant 0.0.7 broke. The top row has nowhere near stock's 207px of room
/// above it — a keyboard extension's own surface starts 104px above the first row — and
/// the frame was being pushed down bodily until it fitted, which kept the shape's
/// proportions and moved its foot a third of a cap below the letter it was announcing,
/// into the row beneath. Nothing failed; it just looked wrong, which is the kind of defect
/// a screenshot catches once and a test catches every time.
@MainActor
@Test(arguments: [390.0, 402.0, 430.0, 440.0] as [CGFloat])
func aPreviewEndsOnTheKeyItBelongsTo(width: CGFloat) {
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
  let geometry = KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: true)
  view.configure(geometry: geometry, shift: .off, needsNextKeyboard: true)

  for key in geometry.keys where key.letter != nil {
    let frame = view.previewFrame(above: key)
    #expect(
      abs(frame.maxY - key.frame.maxY) < 0.01,
      "the preview over \(key.id) ends at \(frame.maxY) and its cap ends at \(key.frame.maxY)")
    #expect(
      frame.minY >= 0,
      "the preview over \(key.id) starts at \(frame.minY), above the keyboard's own top edge")
    #expect(
      frame.width > key.frame.width,
      "the preview over \(key.id) is no wider than its cap")

    // **Centred on its key, unless being centred would put it outside the keyboard.**
    // The bulb is two thirds wider than a cap, so over the outermost column a centred one
    // reaches past the keys' own margin and the input view slices it flat — the same
    // defect as the top row's, lying down. Stock leans its bulb inward instead, and so
    // does this: the frame stays inside the margins and the taper, which is drawn to the
    // key rather than to the frame, follows the key. SPEC.md A.23.
    let margin = width * StockMetrics.sideMarginFraction
    #expect(
      frame.minX >= margin - 0.01 && frame.maxX <= width - margin + 0.01,
      "the preview over \(key.id) spans \(frame.minX)...\(frame.maxX), outside the margins \(margin) and \(width - margin)")
    let centred = abs(frame.midX - key.frame.midX) < 0.01
    let onTheLeftMargin = abs(frame.minX - margin) < 0.01
    let onTheRightMargin = abs(frame.maxX - (width - margin)) < 0.01
    #expect(
      centred || onTheLeftMargin || onTheRightMargin,
      "the preview over \(key.id) is neither centred on its cap nor resting on a margin")
  }
}

/// **Exactly two letters lean, and they are `q` and `p`.**
///
/// Asserted separately from the invariant above because "centred, or resting on a margin"
/// is also satisfied by a keyboard that shoved every preview onto a margin, and the whole
/// point of a clamp is that it touches as little as it can. Only the top row reaches the
/// keyboard's own margins: `a` and `z` start half a key and a key and a half in from the
/// edge respectively, so their bulbs fit centred and are left alone.
///
/// Measured on an iPhone 17 Pro simulator at 402pt, 2026-09-06 — the clamp moves `q` and
/// `p` by 11.5px each and nothing else by anything.
@MainActor
@Test(arguments: [390.0, 402.0, 430.0, 440.0] as [CGFloat])
func onlyTheOutermostColumnLeans(width: CGFloat) {
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
  let geometry = KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: true)
  view.configure(geometry: geometry, shift: .off, needsNextKeyboard: true)

  let leaning = geometry.keys
    .filter { $0.letter != nil }
    .filter { abs(view.previewFrame(above: $0).midX - $0.frame.midX) >= 0.01 }
    .sorted { $0.frame.minX < $1.frame.minX }
  #expect(
    leaning.compactMap(\.letter) == ["q", "p"],
    "the previews that lean are \(leaning.compactMap(\.letter)) and should be q and p")
}

/// The top row is the only row that has to give anything up, and it gives up height rather
/// than position. Every other row gets stock's full rise.
@MainActor
@Test func onlyTheTopRowsPreviewIsShortOfStocksRise() {
  let width: CGFloat = 430
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
  let geometry = KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: true)
  view.configure(geometry: geometry, shift: .off, needsNextKeyboard: true)

  for key in geometry.keys where key.letter != nil {
    let frame = view.previewFrame(above: key)
    let wanted = key.frame.height * StockMetrics.previewRiseInCaps
    let got = key.frame.minY - frame.minY
    if key.frame.minY - wanted >= 0 {
      #expect(abs(got - wanted) < 0.01, "\(key.id) had room for the full rise and did not take it")
    } else {
      #expect(frame.minY == 0, "\(key.id) had to be clamped and was not clamped to the top edge")
    }
  }
}
