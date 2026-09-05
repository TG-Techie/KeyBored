// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import CoreGraphics
import Testing
import UIKit

@testable import KeyBored

@MainActor
private final class Sink: TextDocument {
  var text = ""
  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

/// The bar is the only surface where a prediction is visible, so "the controller computed
/// the right three strings" is not the same claim as "the keyboard showed them". These
/// test the second one.
@MainActor
@Test func theViewDrawsTheThreeBubbles() {
  let controller = KeyboardController(
    width: 402, lexicon: EnglishLexicon.make(), document: Sink())
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: StockMetrics.totalHeight))
  view.apply(controller, needsNextKeyboard: false)

  // Clear the initial auto-shift: these are about how the bar is quoted, not how it is
  // cased. Casing across a commit has its own tests in KeyboardControllerTests.
  let shift = controller.geometry.keys.first { $0.role == .shift }!
  controller.handle(shift, at: shift.center)
  for character in "dont" {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
  }
  view.apply(controller, needsNextKeyboard: false)

  let titles = view.bubbleTitlesForTesting
  #expect(titles.count == 3)
  // The literal is quoted and the predictions are not: the quotes are how the strip
  // distinguishes "what you typed" from "a word I know". See SPEC.md section 6.1.
  #expect(titles[0] == "\u{201C}dont\u{201D}")
  #expect(titles[1] == "don't")
  #expect(!titles[2].isEmpty)
}

/// Before the first tap all three slots are empty, deliberately. See SPEC.md section 6.1:
/// every slot is a function of the taps, and under a flat prior there is no likelier word
/// to offer, so a pre-filled bar would be an arbitrary three dressed as a prediction.
@MainActor
@Test func theBarIsEmptyBeforeTheFirstTap() {
  let controller = KeyboardController(
    width: 402, lexicon: EnglishLexicon.make(), document: Sink())
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: StockMetrics.totalHeight))
  view.apply(controller, needsNextKeyboard: false)
  #expect(view.bubbleTitlesForTesting == ["", "", ""])
}

/// The strip above the keys is reserved whether or not there is anything in it, so the
/// rows never shift under the user's fingers when a prediction appears or goes away.
@MainActor
@Test func theStripIsReservedEvenWhenTheBarIsEmpty() {
  let geometry = KeyboardGeometry(width: 402)
  let topRow = geometry.key(for: "q")!
  #expect(topRow.frame.minY == StockMetrics.suggestionBarHeight)
  #expect(StockMetrics.suggestionBarHeight > 30)
}

/// Renders the keyboard with the bar populated and writes it out, so that "the bubbles
/// are visible" can be checked by looking rather than by reading this file. The image
/// lands in the test host's Documents directory; `xcrun simctl get_app_container` finds it.
@MainActor
@Test func renderThePopulatedKeyboard() throws {
  let width: CGFloat = 402
  let controller = KeyboardController(
    width: width, lexicon: EnglishLexicon.make(), document: Sink())
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: width, height: StockMetrics.totalHeight))
  view.backgroundColor = KeyboardView.plateColor
  view.apply(controller, needsNextKeyboard: true)
  for character in "dont" {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
  }
  view.apply(controller, needsNextKeyboard: true)
  view.layoutIfNeeded()

  let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
    view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
  }
  let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  try image.pngData()!.write(to: directory.appendingPathComponent("keyboard-populated.png"))
}

/// The quotes around the left bubble are presentation and must never reach the text
/// field. Drawn quoted, committed bare — a decoration that could be typed would be a
/// defect rather than a style.
@MainActor
@Test func theLiteralIsDrawnQuotedAndCommittedBare() {
  let document = Sink()
  let controller = KeyboardController(
    width: 402, lexicon: EnglishLexicon.make(), document: document)
  let view = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: StockMetrics.totalHeight))
  view.apply(controller, needsNextKeyboard: false)
  let shift = controller.geometry.keys.first { $0.role == .shift }!
  controller.handle(shift, at: shift.center)
  for character in "dont" {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
  }
  view.apply(controller, needsNextKeyboard: false)

  #expect(view.bubbleTitlesForTesting[0] == "\u{201C}dont\u{201D}")
  controller.commitBubble(controller.bar.literal)
  #expect(document.text == "dont")
}
