// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md sections 11.4 and 11.5 for the measurements each number here comes from,
//   taken off a stock keyboard photographed beside this one on 2026-09-05.

import CoreGraphics
import Testing
import UIKit

@testable import KeyBored

/// A stand-in for a field that declares what it wants.
@MainActor
private final class DeclaringDocument: TextDocument {
  var text = ""
  var traits: DocumentTraits

  init(_ traits: DocumentTraits) { self.traits = traits }

  var textBeforeInput: String? { text }
  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

@MainActor
private func typing(_ traits: DocumentTraits) -> (KeyboardController, DeclaringDocument) {
  let document = DeclaringDocument(traits)
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: document)
  return (controller, document)
}

@MainActor
private func type(_ characters: String, on controller: KeyboardController) {
  for character in characters {
    if character == " " {
      controller.handle(controller.geometry.keys.first { $0.role == .space }!, at: .zero)
    } else {
      let key = controller.geometry.key(for: character)!
      controller.handle(key, at: key.center)
    }
  }
}

// MARK: - Height and the bottom row

/// The keyboard stood 40 points taller than stock, all of it empty plate below the last
/// row, because a whole row was reserved for a globe key that belongs in row 3. It then
/// stood 6px per row too short on every phone narrower than 414pt, because the cap height
/// had been measured once on a 430pt phone and written down as if it were universal.
@Test func theKeyboardIsAsTallAsStock() {
  #expect(abs(StockMetrics.bottomPadding - 22.0 / 3) < 0.01)
  #expect(abs(StockMetrics.suggestionBarHeight - 156.0 / 3) < 0.01)

  // Stock on a 402pt phone, measured plate-top to plate-bottom in a 1206×2622 capture
  // of a Contacts search field, 2026-09-05: 1617 to 2410, so 793px.
  //   156 strip + 4×129 caps + 3×33 gaps + 22 padding = 793
  #expect(abs(StockMetrics.totalHeight(forWidth: 402) * 3 - 793) < 1)
  #expect(abs(StockMetrics.rowHeight(forWidth: 402) * 3 - 129) < 0.01)
  #expect(abs(StockMetrics.rowHeight(forWidth: 390) * 3 - 129) < 0.01)

  // And on the two large phones, where the caps are 6px taller:
  //   156 + 4×135 + 3×33 + 22 = 817
  #expect(abs(StockMetrics.rowHeight(forWidth: 430) * 3 - 135) < 0.01)
  #expect(abs(StockMetrics.rowHeight(forWidth: 440) * 3 - 135) < 0.01)
  #expect(abs(StockMetrics.totalHeight(forWidth: 440) * 3 - 817) < 1)

  // The row pitch follows from the two: 162px on a small phone, 168 on a large one, and
  // the gap between rows is the same 33 on both.
  let small = KeyboardGeometry(width: 402)
  let large = KeyboardGeometry(width: 440)
  #expect(abs(small.rowPitch * 3 - 162) < 0.01)
  #expect(abs(large.rowPitch * 3 - 168) < 0.01)
}

@MainActor
@Test func theBottomRowSplitsForTheGlobeExactlyWhereStockPutsItsEmojiKey() {
  let width: CGFloat = 1290 / 3  // so a point is a pixel divided by the reference scale
  let plain = KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: false)
  let withGlobe = KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: true)

  func row3(_ geometry: KeyboardGeometry) -> [Key] {
    geometry.keys.filter { $0.id.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }
  }

  #expect(row3(plain).count == 3)
  #expect(row3(withGlobe).count == 4)

  // 140 + 18 + 141 = 299, which is the undivided key. So the row is the same row.
  let plainPlane = row3(plain)[0]
  let splitPlane = row3(withGlobe)[0]
  let globe = row3(withGlobe)[1]
  #expect(abs(plainPlane.frame.width * 3 - 299) < 1)
  #expect(abs(splitPlane.frame.width * 3 - 140) < 1)
  #expect(abs(globe.frame.width * 3 - 141) < 1)
  #expect(globe.role == .nextKeyboard)

  // And the space bar is unmoved and unchanged, which is what makes it the same row
  // rather than a different one that happens to fit.
  let plainSpace = row3(plain)[1]
  let globeSpace = row3(withGlobe)[2]
  #expect(abs(plainSpace.frame.minX - globeSpace.frame.minX) < 0.5)
  #expect(abs(plainSpace.frame.width - globeSpace.frame.width) < 0.5)
  #expect(abs(plainSpace.frame.width * 3 - 615) < 2)

  // Nothing below row 3 at all. The empty fifth row is the defect this replaces.
  #expect(withGlobe.keys.allSatisfy { $0.id.row <= 3 })
}

// MARK: - What the field asked for

@MainActor
@Test func aFieldThatWantsNoCapitalsGetsNone() {
  let (controller, document) = typing(DocumentTraits(autocapitalization: .none))
  #expect(controller.isShifted == false)
  type("hi", on: controller)
  #expect(document.text == "hi")
}

@MainActor
@Test func aFieldThatWantsEveryWordCapitalizedGetsThemAll() {
  let (controller, document) = typing(DocumentTraits(autocapitalization: .words))
  type("hi there", on: controller)
  #expect(document.text == "Hi There")
}

@MainActor
@Test func aFieldThatWantsEveryCharacterCapitalizedKeepsShiftDown() {
  let (controller, document) = typing(DocumentTraits(autocapitalization: .allCharacters))
  // The one-shot release would give "Hi"; a field asking for all characters wants "HI".
  type("hi there", on: controller)
  #expect(document.text == "HI THERE")
}

@MainActor
@Test func aSecureFieldGetsNoCandidateBar() {
  let (controller, document) = typing(DocumentTraits(isSecure: true))
  type("dont", on: controller)
  // The keystrokes still land; it is only the display that is suppressed.
  #expect(document.text == "Dont")
  #expect(controller.bar == .empty)

  // And the same taps in an ordinary field do fill the bar, so the assertion above is
  // about the trait rather than about the word.
  let (ordinary, _) = typing(.unspecified)
  type("dont", on: ordinary)
  #expect(ordinary.bar.literal == "Dont")
}

@MainActor
@Test func theReturnKeyIsWhatTheFieldAskedForAndIsBlueWhenItIsAnAction() {
  func view(_ traits: DocumentTraits) -> KeyboardView {
    let (controller, _) = typing(traits)
    let view = KeyboardView(
      frame: CGRect(x: 0, y: 0, width: 430, height: StockMetrics.totalHeight(forWidth: 430)))
    view.apply(controller, needsNextKeyboard: false)
    return view
  }

  // A field asking for Search gets stock's magnifier, not the word — iOS 26 draws glyphs
  // for the two action keys that have been measured. Blue, as stock draws them.
  let search = view(DocumentTraits(returnKey: .search))
  #expect(search.returnKeyTitleForTesting == "")
  #expect(search.returnKeyHasGlyphForTesting)
  #expect(search.returnKeyColorForTesting == KeyboardView.actionKeyColor)

  // A case with no measured glyph draws its word, still on the blue cap.
  let send = view(DocumentTraits(returnKey: .send))
  #expect(send.returnKeyTitleForTesting == "Send")
  #expect(send.returnKeyColorForTesting == KeyboardView.actionKeyColor)

  // Unasked, it draws stock's ↵ on an ordinary cap.
  let plain = view(.unspecified)
  #expect(plain.returnKeyTitleForTesting == "")
  #expect(plain.returnKeyHasGlyphForTesting)
  #expect(plain.returnKeyColorForTesting == KeyboardView.capColor)
}

@MainActor
@Test func theSpaceBarIsBlankTheWayStocksIs() {
  let (controller, _) = typing(.unspecified)
  let view = KeyboardView(
    frame: CGRect(x: 0, y: 0, width: 430, height: StockMetrics.totalHeight(forWidth: 430)))
  view.apply(controller, needsNextKeyboard: false)
  #expect(view.spaceBarTitleForTesting == "")
}

// MARK: - The other two planes

/// Stock's number and symbol planes, measured on a 1206px simulator capture 2026-09-05.
///
/// Both were wrong in the shipped 0.0.3, and wrong in the same two ways: the second row
/// carried nine glyphs where stock carries ten, so it sat half a column pitch in like the
/// letters plane's `asdf` row; and the third row's punctuation was drawn at letter width
/// on the letter grid, where stock draws five caps half again as wide.
///
/// The captures are `stk-numbers.png` and `stk-symbols.png`. Rows, in pixels:
///
///     row 0   10 caps  x 20-119 … 1086-1186        (identical to the letters plane)
///     row 1   10 caps  x 20-119 … 1086-1186        (identical to row 0)
///     row 2    7 caps  136, five of 148, 137
///                      the five run x 197-1008, exactly where the letters plane's
///                      `z`…`m` run in the same capture
///     row 3    3 caps  278 / 574 / 279
@MainActor
@Test func theNumberAndSymbolPlanesAreLaidOutTheWayStockLaysThemOut() {
  // 402 points is the 1206px capture at the reference scale, so a point here is a third
  // of a measured pixel and the numbers below can be compared with the capture directly.
  let width: CGFloat = 402
  let letters = KeyboardGeometry(width: width, plane: .letters)

  func glyphs(_ geometry: KeyboardGeometry, row: Int) -> [Key] {
    geometry.keys
      .filter { $0.id.row == row && $0.letter != nil }
      .sorted { $0.frame.minX < $1.frame.minX }
  }

  let lettersRow2 = glyphs(letters, row: 2)
  #expect(lettersRow2.count == 7)

  for plane in [Plane.numbers, Plane.symbols] {
    let geometry = KeyboardGeometry(width: width, plane: plane)

    // Rows 0 and 1 are ten keys on the same grid as the letters plane's top row: the
    // whole width, both margins, no half-pitch inset. The tenth key of row 1 is the one
    // that was missing — `"` on the numbers plane, `•` on the symbols plane.
    for row in 0..<2 {
      let keys = glyphs(geometry, row: row)
      #expect(keys.count == 10, "plane \(plane) row \(row)")
      #expect(abs(keys[0].frame.minX - glyphs(letters, row: 0)[0].frame.minX) < 0.01)
      #expect(abs(keys[9].frame.maxX - glyphs(letters, row: 0)[9].frame.maxX) < 0.01)
      #expect(abs(keys[0].frame.width * 3 - 101.7) < 0.5)
    }
    #expect(String(glyphs(geometry, row: 1).compactMap(\.letter)).count == 10)

    // Row 2's five punctuation caps occupy the letters plane's `z`…`m` span exactly, and
    // divide it five ways rather than seven.
    let row2 = glyphs(geometry, row: 2)
    #expect(row2.count == 5)
    #expect(abs(row2[0].frame.minX - lettersRow2[0].frame.minX) < 0.01)
    #expect(abs(row2[4].frame.maxX - lettersRow2[6].frame.maxX) < 0.01)
    #expect(abs(row2[0].frame.width * 3 - 149.1) < 0.5)

    // Centred, which is what the equal margins either side of it come from.
    let groupMid = (row2[0].frame.minX + row2[4].frame.maxX) / 2
    #expect(abs(groupMid - width / 2) < 0.01)
  }
}

/// Every command key answers to a touch inside its own cap.
///
/// Written after an afternoon spent believing the shift key was dead, because clicks
/// driven at it through the simulator kept doing nothing. They were being dropped by the
/// automation, not by the keyboard — but nothing in the suite said so, because every other
/// test reaches a key through `geometry.keys.first { $0.role == ... }` and then hands
/// `hitTest` that key's own centre. This one hands it points a finger would produce.
@MainActor
@Test func aTouchAnywhereOnACommandCapHitsThatKey() {
  let geometry = KeyboardGeometry(width: 402, plane: .letters, hasGlobeKey: true)
  for role in [KeyRole.shift, .delete, .space, .newline, .nextKeyboard] {
    let key = geometry.keys.first { $0.role == role }!
    let frame = key.frame
    let corners = [
      CGPoint(x: frame.minX + 1, y: frame.minY + 1),
      CGPoint(x: frame.maxX - 1, y: frame.minY + 1),
      CGPoint(x: frame.minX + 1, y: frame.maxY - 1),
      CGPoint(x: frame.maxX - 1, y: frame.maxY - 1),
      CGPoint(x: frame.midX, y: frame.midY),
    ]
    for point in corners {
      #expect(geometry.hitTest(point)?.role == role, "\(point) in \(frame) missed \(role)")
    }
  }
}
