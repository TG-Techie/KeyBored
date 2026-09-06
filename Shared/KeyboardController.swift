// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 6.3 for what a word boundary commits, and PRIVACY.md for the claim
//   that nothing here outlives the word being typed.

import CoreGraphics
import Foundation

/// Somewhere text can be inserted and deleted, and read back as far as the cursor.
///
/// The keyboard extension's destination is the host app's text field, reached through
/// `UITextDocumentProxy`. The container app's destination is a text view on screen. This
/// protocol is the whole of what the routing needs from either, which is what lets the
/// same code drive both — and it means the routing can be tested without a keyboard
/// extension, a host app, or a simulator.
///
/// Main-actor isolated because every implementation of it is a piece of UIKit: the host
/// app's text field over `UITextDocumentProxy`, or a text view. Marking it here rather
/// than annotating each conformance is what lets `KeyboardController` hold one without
/// Swift 6 having to assume it might be touched from another thread.
@MainActor
public protocol TextDocument: AnyObject {
  /// What sits before the insertion point, as much of it as the host will give.
  ///
  /// A keyboard has to be able to look at the field it is typing into, not only push
  /// text at it: capitalizing the start of a sentence is a fact about where the cursor
  /// is, and no amount of remembering what this keyboard itself typed can establish it.
  /// `UITextDocumentProxy.documentContextBeforeInput` is exactly this, and is `nil` when
  /// the host declines to say.
  var textBeforeInput: String? { get }

  func insertText(_ text: String)
  func deleteBackward()
}

/// Everything that happens between a finger landing on a key and text appearing.
///
/// This is deliberately not in the extension. Routing is where a keyboard's real
/// behaviour lives — what a space commits, what delete undoes, when a word ends — and
/// putting it behind `UIInputViewController` would make all of it reachable only by
/// installing a keyboard and typing on it by hand.
///
/// Nothing here persists. `word` is reset at every boundary, and there is no history,
/// no buffer of past words and no accumulating state of any kind. See PRIVACY.md.
@MainActor
public final class KeyboardController {
  public private(set) var geometry: KeyboardGeometry
  public private(set) var plane: Plane = .letters
  /// Set from the document rather than remembered: see `updateAutoShift`. The `true`
  /// here is only what holds until the first look, which `init` takes immediately.
  public private(set) var isShifted = true
  public private(set) var bar: CandidateBar = .empty

  private let lexicon: Lexicon
  private var predictor: Predictor
  private var word = WordInProgress()
  /// Held strongly, and that is the whole of the fix for a keyboard that typed nothing.
  ///
  /// This was `weak`. Both hosts construct their adapter inline — the extension passes
  /// `ProxyDocument(proxy: textDocumentProxy)`, the container app passes
  /// `TextViewDocument(textView)` — so nothing else owned it and it was deallocated the
  /// moment `init` returned. Every `document?.insertText(...)` below then did nothing,
  /// silently, on a device. The tests did not see it because a test holds its fake
  /// document in a local for the length of the test, which is an ownership the real
  /// hosts never have. Nothing a document holds points back here, so owning it is not a
  /// cycle: the controller owns the document, the document owns a proxy or a text view,
  /// and `onChange` is captured weakly by both hosts.
  private var document: TextDocument?

  /// Called whenever the bar, the plane or the shift state changed, so a view can
  /// redraw without polling.
  public var onChange: (() -> Void)?

  public init(width: CGFloat, lexicon: Lexicon, document: TextDocument?) {
    self.lexicon = lexicon
    self.document = document
    self.geometry = KeyboardGeometry(width: width, plane: .letters)
    self.predictor = Predictor(
      matcher: ConstellationMatcher(geometry: geometry, lexicon: lexicon))
    updateAutoShift()
  }

  public func attach(_ document: TextDocument) {
    self.document = document
    updateAutoShift()
  }

  /// Rebuilds the geometry for a new width or plane. The lexicon is reused: it does not
  /// depend on either, and rebuilding a 19,000-entry trie on every rotation would be a
  /// visible stall for no reason.
  public func resize(width: CGFloat) {
    guard width > 0, width != geometry.width || plane != geometry.plane else { return }
    geometry = KeyboardGeometry(width: width, plane: plane)
    predictor = Predictor(
      matcher: ConstellationMatcher(geometry: geometry, lexicon: lexicon))
    refresh()
  }

  // MARK: - Input

  /// What a strike on `key` at `point` does.
  ///
  /// The point matters and the key does not, for letters: the key is only consulted to
  /// tell a letter from a command. Rounding the point to its key here would discard the
  /// only signal the matcher runs on.
  public func handle(_ key: Key, at point: CGPoint) {
    switch key.role {
    case .letter(let letter):
      if plane == .letters {
        guard let neighborhood = predictor.matcher.neighborhood(for: point) else { return }
        word.append(neighborhood, capitalized: isShifted)
        document?.insertText(String(cased(neighborhood.literal)))
        // Shift is a one-shot: it applies to the letter that follows it and then
        // releases, which is what the stock keyboard does.
        if isShifted { isShifted = false }
      } else {
        // Digits and symbols are inserted as struck and end the word. The constellation
        // is defined over letters, so a tap on another plane is not a tap the matcher
        // can score.
        endWord()
        document?.insertText(String(letter))
      }
      refresh()

    case .space:
      commitWord()
      document?.insertText(" ")
      updateAutoShift()
      refresh()

    case .newline:
      commitWord()
      document?.insertText("\n")
      updateAutoShift()
      refresh()

    case .delete:
      // Delete walks the word back one tap at a time so the bar keeps describing what
      // is actually in the field. Once the word is empty it deletes through whatever
      // came before, which the matcher knows nothing about — so that is also the point
      // at which where the cursor now sits has to be asked about again.
      word.removeLast()
      document?.deleteBackward()
      if word.isEmpty { updateAutoShift() }
      refresh()

    case .shift:
      isShifted.toggle()
      refresh()

    case .plane(let next):
      endWord()
      plane = next
      geometry = KeyboardGeometry(width: geometry.width, plane: next)
      predictor = Predictor(
        matcher: ConstellationMatcher(geometry: geometry, lexicon: lexicon))
      refresh()

    case .nextKeyboard:
      break  // The host decides what switching keyboards means; see the view controller.
    }
  }

  /// Replaces the word in progress with the text of a bubble the user tapped. Deleting
  /// exactly `tapCount` characters is safe because every letter-plane tap inserted
  /// exactly one.
  public func commitBubble(_ text: String) {
    guard !word.isEmpty else { return }
    let text = word.cased(text)
    for _ in 0..<word.tapCount { document?.deleteBackward() }
    document?.insertText(text)
    endWord()
    updateAutoShift()
    refresh()
  }

  /// The host reporting that the document changed under the keyboard.
  ///
  /// Something other than a key can move the cursor or empty the field — Safari's clear
  /// button, a tap into a different field, the app setting text of its own. The stock
  /// keyboard follows all of it; this one could not, because `isShifted` was set to
  /// `true` once at construction and thereafter only ever toggled by the shift key. The
  /// visible symptom, in the simulator on 2026-09-05: clearing Safari's find field and
  /// typing gave `hi there` where the stock keyboard gives `Hi there`.
  ///
  /// The system reports the keyboard's own insertions through the same callback, and
  /// those must not disturb the word in progress. The two are told apart by looking: if
  /// what precedes the cursor still ends with the letters this keyboard believes it put
  /// there, the change was its own.
  public func documentDidChange() {
    let before = document?.textBeforeInput ?? ""
    if !word.isEmpty, !before.hasSuffix(word.cased(predictor.literal(for: word))) {
      endWord()
    }
    if word.isEmpty { updateAutoShift() }
    refresh()
  }

  /// Applies the correction, if the commit policy says there is one.
  private func commitWord() {
    guard !word.isEmpty else { return }
    if case .correction(let text) = predictor.commit(for: word) {
      for _ in 0..<word.tapCount { document?.deleteBackward() }
      document?.insertText(word.cased(text))
    }
    endWord()
  }

  private func endWord() {
    word.reset()
  }

  private func refresh() {
    // The bar is cased the way a commit would case it, so that each bubble shows exactly
    // the text tapping it inserts. Showing "dont" over a field already holding "Dont"
    // would make the left bubble — whose whole job is "this is what you typed" — wrong
    // about the one thing it claims.
    bar = predictor.bar(for: word).map(word.cased)
    onChange?()
  }

  private func cased(_ character: Character) -> Character {
    isShifted ? Character(String(character).uppercased()) : character
  }

  /// Re-arms the one-shot shift from where the insertion point actually is.
  ///
  /// Called only where the shift state is the keyboard's to decide — a word boundary, a
  /// delete back to nothing, a change the host made. A tap on the shift key is the
  /// user's, and nothing here overrides it.
  private func updateAutoShift() {
    isShifted = Self.beginsASentence(document?.textBeforeInput)
  }

  /// Whether text arriving here would begin a sentence.
  ///
  /// Nothing before the cursor counts, which covers both an empty field and a host that
  /// declines to say: capitalizing at the very start is what the stock keyboard does, so
  /// it is also the honest guess when there is nothing to go on. A terminator has to be
  /// followed by a space — `Dr.` mid-sentence is not a new sentence, and neither is a
  /// cursor sitting directly after the dot.
  static func beginsASentence(_ before: String?) -> Bool {
    guard let before else { return true }
    var sawSpace = false
    for character in before.reversed() {
      if character.isNewline { return true }
      if character == " " {
        sawSpace = true
        continue
      }
      return sawSpace && ".!?".contains(character)
    }
    // Spaces all the way back to the start of what the host gave us.
    return true
  }
}
