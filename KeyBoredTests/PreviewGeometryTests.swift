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
      abs(frame.midX - key.frame.midX) < 0.01,
      "the preview over \(key.id) is centred at \(frame.midX) and its cap at \(key.frame.midX)")
    #expect(
      frame.width > key.frame.width,
      "the preview over \(key.id) is no wider than its cap")
  }
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
