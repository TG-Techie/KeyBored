// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 6.3 for the commit rule these exercise end to end.

import CoreGraphics
import Testing

@testable import KeyBored

/// Collects what the keyboard would have typed.
///
/// The point of `TextDocument` being a two-method protocol is that this is the whole of
/// what a test needs to stand in for a host app. Everything below therefore tests the
/// real routing — the same `KeyboardController` the extension runs — without a keyboard
/// extension, a host app or a simulator.
@MainActor
private final class FakeDocument: TextDocument {
  var text = ""

  func insertText(_ text: String) { self.text.append(text) }
  func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

@MainActor
private func typing() -> (KeyboardController, FakeDocument) {
  let document = FakeDocument()
  let controller = KeyboardController(
    width: 430, lexicon: EnglishLexicon.make(), document: document)
  return (controller, document)
}

/// Strikes each letter dead centre on its key, then whatever command keys are named.
@MainActor
private func type(_ word: String, into controller: KeyboardController) {
  for character in word {
    let key = controller.geometry.key(for: character)!
    controller.handle(key, at: key.center)
  }
}

@MainActor
private func press(_ role: KeyRole, _ controller: KeyboardController) {
  let key = controller.geometry.keys.first { $0.role == role }!
  controller.handle(key, at: key.center)
}

// MARK: - Ordinary typing

@MainActor
@Test func typingAWordAndASpaceLeavesTheWord() {
  let (controller, document) = typing()
  press(.shift, controller)  // clear the initial auto-shift
  type("hello", into: controller)
  press(.space, controller)
  #expect(document.text == "hello ")
}

@MainActor
@Test func theKeyboardStartsShiftedAndShiftIsOneShot() {
  let (controller, document) = typing()
  // A fresh keyboard is shifted, like stock, and it releases after one letter.
  #expect(controller.isShifted)
  type("hello", into: controller)
  #expect(document.text == "Hello")
  #expect(!controller.isShifted)
}

@MainActor
@Test func deleteWalksTheWordBack() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("hello", into: controller)
  press(.delete, controller)
  press(.delete, controller)
  #expect(document.text == "hel")
  // The bar keeps describing what is actually in the field rather than what was typed.
  #expect(controller.bar.literal == "hel")
}

// MARK: - The commit policy, end to end

@MainActor
@Test func aSloppyWordIsCorrectedOnSpace() {
  let (controller, document) = typing()
  press(.shift, controller)
  // "hello" with every tap a third of a key right and a quarter low.
  for character in "hello" {
    let key = controller.geometry.key(for: character)!
    controller.handle(
      key,
      at: CGPoint(
        x: key.center.x + key.frame.width * 0.3,
        y: key.center.y + key.frame.height * 0.25))
  }
  press(.space, controller)
  #expect(document.text == "hello ")
}

@MainActor
@Test func aContractionIsCompletedOnSpace() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("dont", into: controller)
  press(.space, controller)
  #expect(document.text == "don't ")
}

@MainActor
@Test func aDeliberateNonWordSurvivesSpace() {
  // The failure a daily driver cannot have: a name, an abbreviation or a password
  // silently replaced by whatever the dictionary liked best.
  let (controller, document) = typing()
  press(.shift, controller)
  type("xkqjv", into: controller)
  press(.space, controller)
  #expect(document.text == "xkqjv ")
}

@MainActor
@Test func aWordThatIsAlreadyAWordSurvivesSpace() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("well", into: controller)
  press(.space, controller)
  #expect(document.text == "well ")
}

// MARK: - The bar

@MainActor
@Test func tappingABubbleReplacesTheWord() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("dont", into: controller)
  #expect(controller.bar.literal == "dont")
  #expect(controller.bar.primary == "don't")
  controller.commitBubble(controller.bar.primary!)
  #expect(document.text == "don't")
}

@MainActor
@Test func tappingTheLiteralBubbleKeepsWhatWasTyped() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("dont", into: controller)
  controller.commitBubble(controller.bar.literal)
  #expect(document.text == "dont")
}

@MainActor
@Test func theBarEmptiesAtAWordBoundary() {
  let (controller, _) = typing()
  press(.shift, controller)
  type("hello", into: controller)
  #expect(!controller.bar.literal.isEmpty)
  press(.space, controller)
  #expect(controller.bar.literal.isEmpty)
}

// MARK: - Planes

@MainActor
@Test func switchingToDigitsEndsTheWordAndTypesLiterally() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("hello", into: controller)
  press(.plane(.numbers), controller)
  #expect(controller.plane == .numbers)
  #expect(controller.bar.literal.isEmpty)

  let two = controller.geometry.key(for: "2")!
  controller.handle(two, at: two.center)
  // A digit is inserted as struck: the constellation is defined over letters, so a tap
  // on another plane is not one the matcher can score, and it must not be corrected.
  #expect(document.text == "hello2")
}

// MARK: - Casing across a commit

@MainActor
@Test func aCorrectionKeepsTheSentenceCapital() {
  // A fresh keyboard is shifted, so this is the first word of a sentence. Correcting it
  // rewrites what is already in the field, and the capital has to survive that rewrite.
  let (controller, document) = typing()
  type("dont", into: controller)
  press(.space, controller)
  #expect(document.text == "Don't ")
}

@MainActor
@Test func anUnshiftedWordIsNotCapitalizedByACorrection() {
  let (controller, document) = typing()
  press(.shift, controller)
  type("dont", into: controller)
  press(.space, controller)
  #expect(document.text == "don't ")
}

@MainActor
@Test func deletingBackToNothingClearsTheWordsCapital() {
  // Walking a word back to empty must forget its casing too, or the next word inherits
  // a capital nobody typed.
  let (controller, document) = typing()
  type("dont", into: controller)
  for _ in 0..<4 { press(.delete, controller) }
  #expect(document.text.isEmpty)
  type("dont", into: controller)
  press(.space, controller)
  #expect(document.text == "don't ")
}

@MainActor
@Test func theBarIsCasedTheWayACommitWouldBe() {
  // Each bubble shows the text tapping it inserts. On a fresh, shifted keyboard that
  // means the capital appears in the bar too, not only in the field.
  let (controller, document) = typing()
  type("dont", into: controller)
  #expect(controller.bar.literal == "Dont")
  #expect(controller.bar.primary == "Don't")
  controller.commitBubble(controller.bar.primary!)
  #expect(document.text == "Don't")
}

@MainActor
@Test func anUncorrectedWordKeepsItsCapitalToo() {
  // The other branch of the commit policy, on a fresh keyboard. A non-word is left alone,
  // so nothing is re-inserted and the capital survives by doing nothing — but the two
  // branches have to agree, or the capital would depend on whether a correction fired.
  let (controller, document) = typing()
  type("xkqjv", into: controller)
  press(.space, controller)
  #expect(document.text == "Xkqjv ")
}

@MainActor
@Test func deleteThenRetypeRestoresTheCapital() {
  // Walking back into a word must not lose its casing: the first tap is still the first
  // tap, and the word is still the start of a sentence.
  let (controller, document) = typing()
  type("dont", into: controller)
  press(.delete, controller)
  let t = controller.geometry.key(for: "t")!
  controller.handle(t, at: t.center)
  press(.space, controller)
  #expect(document.text == "Don't ")
}
