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

    for background in [KeyboardView.letterKeyColor, KeyboardView.commandKeyColor,
                       KeyboardView.pressedKeyColor] {
      let cap = background.resolvedColor(with: traits)
      #expect(contrast(text, cap) >= 4.5)
    }

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
    #expect(contrast(plate, KeyboardView.letterKeyColor.resolvedColor(with: traits)) >= 1.2)
    #expect(contrast(plate, KeyboardView.commandKeyColor.resolvedColor(with: traits)) >= 1.2)
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
  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
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
