// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 8.1 on fixtures that hide the state they were meant to cover.

import CoreGraphics
import UIKit
import Testing

@testable import KeyBored

// MARK: - Ownership

/// Somewhere to observe insertions from without holding the document that made them.
///
/// This is the whole point of the file. Every other test here builds its fake document
/// in a local and keeps it for the length of the test, which is an ownership neither
/// host has: the extension passes `ProxyDocument(proxy:)` and the container app passes
/// `TextViewDocument(_:)`, both constructed inline as arguments. While
/// `KeyboardController` held its document weakly, those were deallocated the instant
/// `init` returned and the keyboard typed nothing at all on a device — with forty tests
/// passing, because all forty accidentally kept the document alive.
@MainActor
private final class Sink {
  var text = ""
}

@MainActor
private final class SinkDocument: TextDocument {
  private let sink: Sink

  init(_ sink: Sink) {
    self.sink = sink
  }

  var textBeforeInput: String? { sink.text }
  var traits: DocumentTraits = .unspecified

  func insertText(_ text: String) { sink.text.append(text) }
  func deleteBackward() { if !sink.text.isEmpty { sink.text.removeLast() } }
}

@MainActor
@Test func theControllerKeepsADocumentNobodyElseOwns() {
  let sink = Sink()
  // Constructed inline and never stored, exactly as both hosts construct theirs.
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: SinkDocument(sink))

  controller.handle(controller.geometry.keys.first { $0.role == .shift }!, at: .zero)
  for character in "hi" {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
  }

  #expect(sink.text == "hi")
}

// MARK: - Legibility

/// WCAG relative luminance, which is the standard definition of "how light is this".
private func luminance(_ color: UIColor) -> CGFloat {
  var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
  color.getRed(&r, green: &g, blue: &b, alpha: &a)
  func channel(_ value: CGFloat) -> CGFloat {
    value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
}

private func contrast(_ one: UIColor, _ other: UIColor) -> CGFloat {
  let a = luminance(one), b = luminance(other)
  return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// Asserts you can read the keys, in both appearances.
///
/// A unit test that checks a label's `text` says nothing about whether anyone can see
/// it. On a phone in dark mode every letter was white on a white cap and the keyboard
/// looked blank; the assertion that catches that is about colour, not about strings.
/// 4.5:1 is WCAG AA for body text, which is a stricter bar than a keycap needs and is
/// therefore a safe floor.
@MainActor
@Test func everyCapIsLegibleInBothAppearances() {
  for style in [UIUserInterfaceStyle.light, .dark] {
    let traits = UITraitCollection(userInterfaceStyle: style)
    let text = KeyboardView.keyTextColor.resolvedColor(with: traits)

    #expect(contrast(text, KeyboardView.capColor.resolvedColor(with: traits)) >= 4.5)

    // The pressed cap is held to 3:1, not 4.5, and the reason is that 4.5 is a bar stock
    // itself does not clear. Measured 2026-09-06 (SPEC.md A.12), stock's dark pressed cap
    // is `#7D7D7D`, which is 4.17:1 against the white glyph on it. This keyboard used to
    // pass 4.5 here by drawing a pressed cap 18 units darker than stock's, which is not a
    // legibility win worth a visible divergence: the state lasts as long as a finger is
    // down, and the finger is on the glyph. The floor stays, at the level stock reaches.
    #expect(contrast(text, KeyboardView.pressedKeyColor.resolvedColor(with: traits)) >= 3.0)

    // The action return key carries its own foreground because it carries its own fill,
    // and it is the same blue in both appearances, so it has to be legible in both.
    #expect(contrast(.white, KeyboardView.actionKeyColor) >= 3.0)

    // The dimmed action return key is exempt, and deliberately so: stock draws its glyph
    // about 1.1:1 against its own cap, which is what a disabled control looks like. The
    // assertion that is worth making is that it is *not* legible in the way an enabled key
    // is, so that a future change cannot quietly make the two states look alike.
    let dimmed = KeyboardView.dimmedActionKeyColor.resolvedColor(with: traits)
    let dimmedGlyph = KeyboardView.dimmedActionKeyTextColor.resolvedColor(with: traits)
    #expect(contrast(dimmedGlyph, dimmed) < 1.5)
    // And it has to be a different key from the enabled one. Stated as inequality rather
    // than as a contrast ratio, which is the wrong instrument: grey against `#007AFF` is
    // 1.16:1 in dark because the two happen to sit at the same luminance, and they are
    // still nothing alike to look at.
    #expect(dimmed != KeyboardView.actionKeyColor)

    let bar = KeyboardView.barTextColor.resolvedColor(with: traits)
    let plate = KeyboardView.plateColor.resolvedColor(with: traits)
    #expect(contrast(bar, plate) >= 4.5)
  }
}

/// The plate has to be distinguishable from the caps sitting on it, or the keyboard
/// reads as one undifferentiated slab. This is deliberately a much weaker bar than the
/// text contrast above: it is a shape check, not a legibility one.
@MainActor
@Test func thePlateIsDistinctFromTheCapsOnIt() {
  for style in [UIUserInterfaceStyle.light, .dark] {
    let traits = UITraitCollection(userInterfaceStyle: style)
    let plate = KeyboardView.plateColor.resolvedColor(with: traits)
    #expect(contrast(plate, KeyboardView.capColor.resolvedColor(with: traits)) >= 1.2)
  }
}

/// A mutable stand-in for a field the host also writes to.
///
/// The other fakes in this suite only ever receive text from the keyboard, which is
/// exactly the situation in which the auto-shift bug is invisible: it only appears when
/// something other than the keyboard changes the field.
@MainActor
private final class HostEditableDocument: TextDocument {
  var text = ""

  var textBeforeInput: String? { text }
  var traits: DocumentTraits = .unspecified
  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

@MainActor
private func type(_ characters: String, on controller: KeyboardController) {
  for character in characters {
    if character == " " {
      // At the space bar's own centre, not at the origin. The point used to be ignored
      // for a space and is now what decides the tap means one, so a helper that struck it
      // at (0, 0) would be asserting the behaviour of a tap in the top-left corner.
      let space = controller.geometry.keys.first { $0.role == .space }!
      controller.handle(space, at: space.center)
    } else {
      let key = controller.geometry.key(for: character)!
      controller.handle(key, at: key.center)
    }
  }
}

/// The bug Jonah found by typing into Safari: clear the field with the host's own clear
/// button, type again, and the keyboard stayed lowercase where the stock one capitalizes.
@MainActor
@Test func clearingTheFieldFromTheHostReArmsTheCapital() {
  let document = HostEditableDocument()
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: document)

  type("hi there", on: controller)
  #expect(document.text == "Hi there")

  // Safari's clear button, or anything else the app does to its own field.
  document.text = ""
  controller.documentDidChange()

  type("hi there", on: controller)
  #expect(document.text == "Hi there")
}

/// Capitalization follows the sentence, not the launch of the keyboard.
@MainActor
@Test func aFullStopAndASpaceStartANewSentence() {
  let document = HostEditableDocument()
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: document)

  type("hi ", on: controller)
  #expect(controller.isShifted == false)

  document.text = "Hi. "
  controller.documentDidChange()
  #expect(controller.isShifted == true)

  document.text = "Hi. there"
  controller.documentDidChange()
  #expect(controller.isShifted == false)

  document.text = "Dr."
  controller.documentDidChange()
  #expect(controller.isShifted == false)

  document.text = "Hi\n"
  controller.documentDidChange()
  #expect(controller.isShifted == true)
}

/// The system reports the keyboard's own insertions through the same callback the host's
/// edits arrive on. If those were treated as external the word in progress would be
/// thrown away after every letter and the bar would never fill.
@MainActor
@Test func theKeyboardsOwnInsertionsDoNotClearTheWord() {
  let document = HostEditableDocument()
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: document)

  for character in "hell" {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
    controller.documentDidChange()
  }

  #expect(document.text == "Hell")
  #expect(controller.bar.literal == "Hell")
}
