// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 6.3 for what a word boundary commits, and PRIVACY.md for the claim
//   that nothing here outlives the word being typed.

import CoreGraphics
import Foundation

/// What the field being typed into says it wants.
///
/// A translation of the `UITextInputTraits` every host's text input already carries, into
/// the terms this routing uses. Translated at the host boundary rather than read here, for
/// two reasons. `Shared/` stays clear of the extension-only half of UIKit, as it does for
/// everything else. And every member of `UITextInputTraits` is an `@optional` protocol
/// requirement, which Swift imports as an optional — `proxy.returnKeyType` has type
/// `UIReturnKeyType?` — so the fallback for "the field did not say" is decided once, in one
/// place, instead of at each use. SPEC.md section 11.
public struct DocumentTraits: Sendable, Equatable {
  /// `UIReturnKeyType`, minus the distinctions stock does not draw: `.google` and
  /// `.yahoo` are search keys from before those were separate products and stock labels
  /// both the same as `.search`.
  public enum ReturnKey: Sendable, Equatable {
    /// The field asked for nothing, so the key is the plain grey one with stock's ↵.
    case newline
    case go
    case search
    case send
    case join
    case next
    case route
    case done
    case emergencyCall
    case `continue`

    /// Stock fills every one of these but `.newline` in blue. Named here rather than in
    /// the view because it is what the case *is*, not how it is drawn.
    public var isAction: Bool { self != .newline }
  }

  /// Which capital the field wants, in `UITextAutocapitalizationType`'s four kinds.
  public enum Autocapitalization: Sendable, Equatable {
    case none
    case words
    case sentences
    case allCharacters
  }

  public var autocapitalization: Autocapitalization

  /// What the field asked its return key to be.
  ///
  /// This used to be the word to draw, a `String?`, on the reasoning that drawing it was
  /// the only thing done with it. That was wrong twice over. **iOS 26 draws glyphs, not
  /// words, for at least two of these** — measured 2026-09-05, a right arrow for `.go` in
  /// Safari's address bar and a magnifier for `.search` in a Contacts search field, both
  /// beside this keyboard on the same simulator. And an action return key is blue where a
  /// plain one is grey, which is a fact about the key rather than about its caption. A
  /// string could carry neither, so the case is carried instead and the drawing is
  /// decided where the drawing happens.
  public var returnKey: ReturnKey

  /// A password field. Nothing is stored either way — PRIVACY.md is unchanged — but the
  /// candidate bar would otherwise print the password in the largest type on screen.
  public var isSecure: Bool

  /// Whether the quote keys may insert curly characters.
  ///
  /// `UITextInputTraits.smartQuotesType` has three values and only one of them is a
  /// refusal: `.no` means the field wants the plain ASCII quote, and `.default` and
  /// `.yes` both leave the keyboard to decide. `SmartPunctuation` explains what is
  /// decided and what was measured; this is only the field's veto.
  public var smartQuotes: Bool

  /// The field asked for its return key to be disabled while there is nothing to submit,
  /// which is `UITextInputTraits.enablesReturnKeyAutomatically`.
  ///
  /// The name is UIKit's and the behaviour drawn from it is stock's, and the two do not
  /// quite agree — see `returnKeyIsDimmed`, which is where the observed rule lives.
  public var enablesReturnKeyAutomatically: Bool

  /// Whether this is a field stock gives a dedicated period key in the bottom row.
  ///
  /// Measured on `UIKeyboardType.webSearch`, which is what Safari's address field asks
  /// for — read off the field itself with a probe build rather than assumed. Whether
  /// stock does the same for `.URL` and `.emailAddress` is untested: no field of either
  /// kind was reached on the device. SPEC.md Appendix A.14.
  public var wantsPeriodKey: Bool

  public init(
    autocapitalization: Autocapitalization = .sentences,
    returnKey: ReturnKey = .newline,
    isSecure: Bool = false,
    smartQuotes: Bool = true,
    enablesReturnKeyAutomatically: Bool = false,
    wantsPeriodKey: Bool = false,
  ) {
    self.autocapitalization = autocapitalization
    self.returnKey = returnKey
    self.isSecure = isSecure
    self.smartQuotes = smartQuotes
    self.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically
    self.wantsPeriodKey = wantsPeriodKey
  }

  /// What holds when the field says nothing. `.sentences` is UIKit's own documented
  /// default for `autocapitalizationType`, not a preference of this project's.
  public static let unspecified = DocumentTraits()
}

/// Somewhere text can be inserted and deleted, and read back as far as the cursor.
///
/// The keyboard extension's destination is the host app's text field, reached through
/// `UITextDocumentProxy`. The container app's destination is a text view on screen. This
/// What the shift key is doing, which is three things and not two.
///
/// This was a `Bool` until 2026-09-05, and the missing state was caps lock: a double tap
/// did what a single tap does, so the only way to type two capitals in a row was to hold
/// the field in `.allCharacters`. Off and one-shot both read as "not locked" and one-shot
/// and locked both read as "shifted", so neither pair collapses into a flag without losing
/// the other distinction. Stock draws the difference too — a latched shift is a barred
/// arrow, not a filled one.
public enum ShiftState: Sendable, Equatable {
  /// The next letter comes out as it is drawn on the key.
  case off
  /// The next letter is capitalized, and then the shift releases itself.
  case oneShot
  /// Every letter is capitalized until the shift key is struck again. Auto-shift does
  /// not clear this; only a strike does.
  case locked

  /// How a word begun while the shift stands here is committed.
  ///
  /// The bar's left slot shows the text a tap on it would insert, so this mapping is what
  /// keeps that promise true under caps lock: `DEF` in the field has to be `DEF` in the
  /// bar, not `Def`. See `WordCasing`.
  var wordCasing: WordCasing {
    switch self {
    case .off: return .lower
    case .oneShot: return .capitalized
    case .locked: return .upper
    }
  }
}

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

  /// What the field wants of the keyboard. A host that cannot say returns
  /// `.unspecified`; the container app's try-it surface does exactly that.
  var traits: DocumentTraits { get }

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
  /// Set from the document rather than remembered: see `updateAutoShift`. The `oneShot`
  /// here is only what holds until the first look, which `init` takes immediately.
  public private(set) var shift: ShiftState = .oneShot

  /// Whether the next letter comes out capitalized. Both shifted states say yes; what
  /// separates them is what happens to the state afterwards.
  public var isShifted: Bool { shift != .off }

  /// How long after a shift strike a second one still latches. Stock's window is around
  /// a third of a second; this was not measured off a stock keyboard, it is the standard
  /// double-tap interval and it feels right. Section 10 has it as a tunable.
  static let capsLockWindow: TimeInterval = 0.3

  /// When the shift key was last struck, on the clock the caller passes to `handle`.
  /// Only a strike moves it, so auto-shift arming the key cannot look like a first tap.
  private var lastShiftTap: TimeInterval = -.greatestFiniteMagnitude
  public private(set) var bar: CandidateBar = .empty

  /// What the field asked for, re-read whenever the document changes. See
  /// `DocumentTraits`; `.unspecified` until a document has been looked at.
  public private(set) var traits: DocumentTraits = .unspecified

  /// Whether anything has been typed since the keyboard came up. Drives
  /// `returnKeyIsDimmed`, and nothing else.
  public private(set) var hasTypedSincePresentation = false

  /// Whether the action return key is drawn greyed out.
  ///
  /// Stock does this and the rule is not the one the trait's name suggests. Measured
  /// 2026-09-06 in a Contacts search field (SPEC.md Appendix A.13): a freshly presented
  /// keyboard on an empty field draws the search key grey; the first keystroke turns it
  /// blue; **deleting back to an empty field leaves it blue**, for the rest of that
  /// presentation; and dismissing and re-presenting greys it again. So it is not "there
  /// is nothing to submit", which would go back to grey — it is "nothing has been typed
  /// yet", which latches.
  ///
  /// Gated on the field's own trait rather than applied everywhere, because Safari's
  /// address bar is empty on a fresh presentation and stock draws its arrow blue there.
  /// Only the action return keys dim; whether stock also dims a plain `↵` in a field that
  /// sets the trait was not tested, and no field that does both was found.
  public var returnKeyIsDimmed: Bool {
    traits.returnKey.isAction && traits.enablesReturnKeyAutomatically
      && !hasTypedSincePresentation
  }

  /// The keyboard has just been put on screen. Re-arms the dimmed return key.
  public func didPresent() {
    hasTypedSincePresentation = false
    refresh()
  }

  /// Whether the layout carries the globe key, from the host's
  /// `needsInputModeSwitchKey`. It changes the geometry rather than only the drawing,
  /// because the globe takes stock's emoji slot and the space bar starts after it.
  public var hasGlobeKey: Bool = false {
    didSet {
      guard hasGlobeKey != oldValue else { return }
      rebuildGeometry()
      refresh()
    }
  }

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
    readTraits()
    updateAutoShift()
  }

  public func attach(_ document: TextDocument) {
    self.document = document
    readTraits()
    updateAutoShift()
  }

  /// Rebuilds the geometry for a new width or plane. The lexicon is reused: it does not
  /// depend on either, and rebuilding a 19,000-entry trie on every rotation would be a
  /// visible stall for no reason.
  public func resize(width: CGFloat) {
    guard width > 0, width != geometry.width || plane != geometry.plane else { return }
    rebuildGeometry(width: width)
    refresh()
  }

  /// The one place a geometry is built after `init`, so a new width, a new plane and the
  /// globe appearing cannot each grow their own copy of these three lines.
  private func rebuildGeometry(width: CGFloat? = nil) {
    geometry = KeyboardGeometry(
      width: width ?? geometry.width, plane: plane, hasGlobeKey: hasGlobeKey,
      hasPeriodKey: traits.wantsPeriodKey)
    predictor = Predictor(
      matcher: ConstellationMatcher(geometry: geometry, lexicon: lexicon))
  }

  // MARK: - Input

  /// What a strike on `key` at `point` does.
  ///
  /// **On the letters plane the point decides and the cap does not.** Every key the
  /// matcher scores — the letters and the space bar — goes through one neighbourhood, and
  /// what the tap *means* is the nearest scored character to where the finger landed, not
  /// the cap it landed on. So a tap on the space bar that is nearer a letter types the
  /// letter, and a tap low on a letter that is nearer the space bar ends the word. That
  /// is Jonah's rule of 2026-09-06 10:35 and it is the constellation method applied to
  /// the key it had been leaving out. SPEC.md A.20.
  ///
  /// The cap is still consulted, for two things it is the authority on: whether this is a
  /// key the matcher scores at all, and what a command key does. Rounding the point to
  /// its key would discard the only signal the matcher runs on.
  public func handle(
    _ key: Key, at point: CGPoint,
    at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
  ) {
    if plane == .letters, key.scoredCharacter != nil {
      guard let neighborhood = predictor.matcher.neighborhood(for: point) else { return }
      strike(neighborhood)
      return
    }

    switch key.role {
    case .letter(let letter):
      // Only reached off the letters plane, because the letters plane is resolved above.
      // Digits and symbols end the word: the constellation is defined over the letters
      // and the space bar, so a tap on another plane is not a tap the matcher can score,
      // and nothing here is ever corrected. What goes in is the character as struck,
      // except for the two quote keys, which stock resolves against the character in
      // front of the cursor — see `SmartPunctuation`.
      //
      // The apostrophe is the exception, and `continuesAWord` is where that is already
      // said: it sits *inside* `don't`, so the word is not over and committing would try
      // to correct `don`. The record is abandoned instead, and the tap after it starts an
      // unanchored word that nothing will rewrite.
      if Self.continuesAWord(letter) { discardWord() } else { commitWord() }
      // Read after the commit, not before: a correction can change the character the
      // quote is resolving against.
      let previous = document?.textBeforeInput?.last
      insert(
        traits.smartQuotes
          ? SmartPunctuation.text(for: letter, after: previous)
          : SmartPunctuation.plain(for: letter))
      // And the apostrophe, alone among them, hands the keyboard back to the letters
      // plane, because the tap after an apostrophe is nearly always a letter.
      if SmartPunctuation.returnsToLetters(after: letter) {
        plane = .letters
        rebuildGeometry()
      }
      refresh()

    case .punctuation(let character):
      // A punctuation cap on the letters plane ends the word the same way a tap on
      // another plane does — the punctuation itself goes in as struck and is never
      // corrected — and then the field's capitalization rule gets its say, because a
      // period is one of the things `.sentences` capitalizes after.
      commitWord()
      insert(String(character))
      updateAutoShift()
      refresh()

    case .space:
      // Only reached off the letters plane, where the space bar is a cap like any other
      // and there is no constellation for it to be a point in. On the letters plane a
      // space is what a tap *resolved to*, and `strike(_:)` is where that happens.
      commitWordWithSpace()

    case .newline:
      commitWord()
      insert("\n")
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
      // Two strikes inside the window latch; anything else toggles. It is the interval
      // alone and not the state it found, because on a keyboard that auto-shift has
      // already armed the first of the two taps turns shift *off* — and stock latches on
      // that pair all the same, which a rule that wanted to find shift on would miss.
      //
      // The edge that leaves: unlatch, then strike again within the window, and it
      // latches instead of arming a one-shot. Stock's behaviour there has not been
      // checked, and it is not a pair of taps anyone makes on purpose.
      let isDoubleTap = time - lastShiftTap < Self.capsLockWindow
      lastShiftTap = time
      shift = isDoubleTap ? .locked : (shift == .off ? .oneShot : .off)
      refresh()

    case .plane(let next):
      // Leaving the letters plane ends the word, and ending a word commits it. The plane
      // key inserts nothing, so this is the one boundary with no character behind it —
      // but the next tap cannot be part of this word either way, and a word that ends is
      // a word that gets its correction.
      commitWord()
      plane = next
      rebuildGeometry()
      refresh()

    case .nextKeyboard:
      break  // The host decides what switching keyboards means; see the view controller.
    }
  }

  /// Replaces the word in progress with the text of a bubble the user tapped. Deleting
  /// exactly `tapCount` characters is safe because every letter-plane tap inserted
  /// exactly one.
  public func commitBubble(_ text: String) {
    guard !word.isEmpty, word.isAnchored else { return }
    let text = word.cased(text)
    for _ in 0..<word.tapCount { document?.deleteBackward() }
    insert(text)
    discardWord()
    updateAutoShift()
    refresh()
  }

  /// What a tap on the letters plane means, once the matcher has said which character it
  /// was nearest.
  ///
  /// The space is not a special case here so much as the case that ends the word: it is
  /// the one scored character that is not part of any word, so resolving to it is what
  /// says the word before it is finished and may be corrected.
  private func strike(_ neighborhood: TapNeighborhood) {
    guard neighborhood.literal != " " else {
      commitWordWithSpace()
      return
    }
    // Whether this tap starts a word, or continues one that was already in the field, is
    // decided once — here, before the character goes in, while the character in front of
    // the cursor is still the one that was there.
    let anchored = word.isEmpty ? !Self.continuesAWord(document?.textBeforeInput?.last) : true
    word.append(neighborhood, casing: shift.wordCasing, anchored: anchored)
    insert(String(cased(neighborhood.literal)))
    // Shift is a one-shot: it applies to the letter that follows it and then releases,
    // which is what the stock keyboard does — except in a field that asked for
    // `.allCharacters`, where releasing it would fight the field on every key.
    if shift == .oneShot, traits.autocapitalization != .allCharacters { shift = .off }
    refresh()
  }

  /// A space: the word in front of it is committed, corrected if the matcher has a better
  /// reading of it, and then the space goes in. Stock accepts its top suggestion on the
  /// space bar in the same way.
  private func commitWordWithSpace() {
    commitWord()
    insert(" ")
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
    readTraits()
    let before = document?.textBeforeInput ?? ""
    if !word.isEmpty, !before.hasSuffix(word.cased(predictor.literal(for: word))) {
      discardWord()
    }
    if word.isEmpty { updateAutoShift() }
    refresh()
  }

  /// Whether a character in front of the cursor means the next tap lands inside a word.
  ///
  /// The apostrophe is in here because the lexicon has words with one in the middle, so
  /// `don'` followed by `t` is a continuation and not a new word.
  private static func continuesAWord(_ character: Character?) -> Bool {
    guard let character else { return false }
    return character.isLetter || character == "'" || character == SmartPunctuation.apostrophe
  }

  /// Applies the correction, if the commit policy says there is one.
  private func commitWord() {
    guard !word.isEmpty else { return }
    // A word this keyboard did not compose the start of is not one it may rewrite: the
    // taps are a fragment of it, and `tapCount` characters back from the cursor is not
    // where that word begins. SPEC.md Appendix A.16.
    guard word.isAnchored else {
      discardWord()
      return
    }
    if case .correction(let text) = predictor.commit(for: word) {
      for _ in 0..<word.tapCount { document?.deleteBackward() }
      document?.insertText(word.cased(text))
    }
    discardWord()
  }

  /// Every insertion the user asked for, in one place, so that "has anything been typed"
  /// has somewhere to be recorded. `commitWord`'s own rewrite deliberately does not go
  /// through here: it is this keyboard correcting what the user already typed, and the tap
  /// that triggered it came through one of these.
  private func insert(_ text: String) {
    hasTypedSincePresentation = true
    document?.insertText(text)
  }

  /// Throws the word in progress away **without** committing it.
  ///
  /// **This is not the verb a word boundary wants, and it used to be spelled so that it
  /// looked like one.** It was `endWord()`, and it sat at every boundary in `handle` — so
  /// a comma, a digit or the plane key silently deleted the pending correction, and the
  /// space that followed had nothing left to correct. Reported by Jonah 2026-09-06 12:59:
  /// "if i put a comma on th nd ofna word then type space  an easy clrrection, is often
  /// missed". Reproduced in two taps: `hrllo` then space gives `hello`, `hrllo` then a
  /// comma then space gives `hrllo,`. SPEC.md Appendix A.27.
  ///
  /// So the two verbs are named apart. A boundary calls `commitWord()`. This one means
  /// something narrower and rarer: *the record is no longer valid*, because the document
  /// moved underneath it or because the text it describes is already gone. There are
  /// three such places and no more — the host reporting a change this keyboard did not
  /// make, a bubble whose text has already been inserted, and the apostrophe, which is a
  /// character inside a word rather than a boundary between two.
  private func discardWord() {
    word.reset()
  }

  private func refresh() {
    // The bar is cased the way a commit would case it, so that each bubble shows exactly
    // the text tapping it inserts. Showing "dont" over a field already holding "Dont"
    // would make the left bubble — whose whole job is "this is what you typed" — wrong
    // about the one thing it claims.
    // A password field gets no bar. Nothing is stored either way, and PRIVACY.md is
    // unchanged by this — but the bar is the largest type on the keyboard, and printing
    // what someone is typing into a password field there is the one place this keyboard
    // would be worse than the stock one to be seen using. SPEC.md section 11.2.
    // An unanchored word gets no bar at all. The left bubble's job is to say "this is
    // what you typed", and for a fragment of a word already in the field it would be
    // saying it about three letters in the middle of one. Nothing honest fits there.
    bar =
      traits.isSecure || !word.isAnchored
      ? .empty : predictor.bar(for: word).map(word.cased)
    onChange?()
  }

  private func cased(_ character: Character) -> Character {
    isShifted ? Character(String(character).uppercased()) : character
  }

  /// Re-reads the field's traits, and rebuilds the layout if one of them is a layout.
  ///
  /// Most traits only change how a key is drawn or what it inserts. `wantsPeriodKey` moves
  /// the space bar and the return key, so it has to reach the geometry, and the host can
  /// change fields under a keyboard that is already on screen.
  private func readTraits() {
    let previous = traits
    traits = document?.traits ?? .unspecified
    if traits.wantsPeriodKey != previous.wantsPeriodKey { rebuildGeometry() }
  }

  /// Re-arms the one-shot shift from where the insertion point actually is.
  ///
  /// Called only where the shift state is the keyboard's to decide — a word boundary, a
  /// delete back to nothing, a change the host made. A tap on the shift key is the
  /// user's, and nothing here overrides it.
  private func updateAutoShift() {
    // Caps lock is the user's, and it survives every boundary until they strike shift
    // again. Auto-shift arms a one-shot; it does not get to cancel a latch.
    guard shift != .locked else { return }
    let before = document?.textBeforeInput
    switch traits.autocapitalization {
    case .none:
      shift = .off
    case .allCharacters:
      // A field that wants every character capitalized wants exactly what caps lock is,
      // which is also why the letter path above does not release the shift in one.
      shift = .locked
    case .words:
      shift = Self.beginsAWord(before) ? .oneShot : .off
    case .sentences:
      shift = Self.beginsASentence(before) ? .oneShot : .off
    }
  }

  /// Whether text arriving here would begin a word: nothing before it, or whitespace.
  static func beginsAWord(_ before: String?) -> Bool {
    guard let last = before?.last else { return true }
    return last.isWhitespace
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
