// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 6 for the bubble assignment and the commit rule.

import CoreGraphics

/// The three bubbles above the keyboard.
///
/// Left is exactly what was typed, middle is the prediction, right is the runner-up.
/// SPEC.md section 6.1.
///
/// `literal` is always present because it is derivable from the taps alone. The other
/// two are optional, because a short or unusual tap sequence honestly leaves fewer
/// than two words to offer, and an empty slot is better than a filled one that means
/// nothing.
public struct CandidateBar: Sendable, Equatable {
  public let literal: String
  public let primary: String?
  public let secondary: String?

  public static let empty = CandidateBar(literal: "", primary: nil, secondary: nil)

  /// The same three slots with `transform` applied to each. Used to put a word's own
  /// casing on the bar, so that what the bubbles show is what tapping them would type.
  public func map(_ transform: (String) -> String) -> CandidateBar {
    CandidateBar(
      literal: transform(literal),
      primary: primary.map(transform),
      secondary: secondary.map(transform),
    )
  }
}

/// What a word boundary should insert.
public enum Commit: Sendable, Equatable {
  case literal(String)
  case correction(String)

  public var text: String {
    switch self {
    case .literal(let text), .correction(let text): return text
    }
  }
}

/// The taps since the last word boundary, and everything derived from them.
///
/// A value type on purpose: the keyboard holds one, replaces it at each boundary, and
/// there is no long-lived mutable state for a prediction to depend on. That is a large
/// part of what makes "the same taps give the same answer" true by construction rather
/// than by discipline.
public struct WordInProgress: Sendable {
  public private(set) var neighborhoods: [TapNeighborhood] = []

  /// How the shift key was standing for the word's first tap.
  ///
  /// The matcher works in lowercase — "Don't" and "don't" are the same constellation, and
  /// making them different entries would double the lexicon to say nothing. But committing
  /// a correction rewrites what is already in the field, so the casing has to be carried
  /// somewhere or the first word of every sentence quietly loses its capital. Here is that
  /// somewhere: taken from the first tap and applied to whatever is committed.
  public private(set) var casing: WordCasing = .lower

  /// Whether these taps began where a word begins, rather than inside one that was
  /// already in the field.
  ///
  /// Everything this type is for assumes the taps and the word are the same thing: the
  /// bar describes the taps as "what you typed", and a commit rewrites exactly
  /// `tapCount` characters. Put the caret in the middle of an existing word and both
  /// stop being true — the taps are a fragment, and rewriting them replaces text the
  /// user typed with a correction to a word they never wrote.
  ///
  /// Measured on a simulator 2026-09-06: `cat`, space, delete, `hte` left `cathte` in
  /// Safari's address field with the bar reading `"hte" | he | hate`, and the next space
  /// turned the field into `cathe`. SPEC.md Appendix A.16.
  ///
  /// An empty word is anchored, because a word that has not started cannot have started
  /// in the wrong place.
  public private(set) var isAnchored = true

  public init() {}

  public var isEmpty: Bool { neighborhoods.isEmpty }
  public var tapCount: Int { neighborhoods.count }

  public mutating func append(
    _ neighborhood: TapNeighborhood, casing: WordCasing = .lower, anchored: Bool = true,
  ) {
    if neighborhoods.isEmpty {
      self.casing = casing
      isAnchored = anchored
    }
    neighborhoods.append(neighborhood)
  }

  public mutating func removeLast() {
    if !neighborhoods.isEmpty { neighborhoods.removeLast() }
    if neighborhoods.isEmpty { reset() }
  }

  public mutating func reset() {
    neighborhoods.removeAll()
    casing = .lower
    isAnchored = true
  }

  /// Applies the word's own casing to text the matcher produced.
  ///
  /// `.capitalized` touches only the first letter: a correction can be a different length
  /// from the taps that produced it ("dont" is four taps and "don't" is five characters),
  /// so there is no honest per-tap mapping. `.upper` has no such problem — every letter
  /// goes up however many there are.
  public func cased(_ text: String) -> String {
    switch casing {
    case .lower:
      return text
    case .capitalized:
      guard let first = text.first else { return text }
      return String(first).uppercased() + text.dropFirst()
    case .upper:
      return text.uppercased()
    }
  }
}

/// How a word is cased when it is committed.
///
/// Three cases rather than a `Bool`, because caps lock is a third thing and a boolean
/// could not say it: with `startsCapitalized` a word typed under caps lock went into the
/// field as `DEF` and into the bar as `Def`, so tapping the bar's own literal replaced
/// what had been typed with something else. Measured on a simulator, 2026-09-06.
public enum WordCasing: Sendable, Equatable {
  /// Shift was off: the word is committed exactly as the matcher produced it.
  case lower
  /// Shift was armed for one tap, or auto-capitalization was: the first letter goes up.
  case capitalized
  /// Caps lock was on: every letter goes up.
  case upper
}

/// Turns the word in progress into the bar, and decides what a space commits.
public struct Predictor: Sendable {
  public let matcher: ConstellationMatcher

  public init(matcher: ConstellationMatcher) {
    self.matcher = matcher
  }

  public func literal(for word: WordInProgress) -> String {
    matcher.literal(for: word.neighborhoods)
  }

  public func bar(for word: WordInProgress) -> CandidateBar {
    guard !word.isEmpty else { return .empty }
    let literal = matcher.literal(for: word.neighborhoods)
    let candidates = matcher.readings(for: word.neighborhoods)

    // A prediction identical to the literal is not shown twice. The literal slides
    // into the middle, where the eye is already looking, and the runner-up takes the
    // right-hand slot.
    let distinct = candidates.map(\.text).filter { $0 != literal }
    if candidates.first?.text == literal {
      return CandidateBar(literal: literal, primary: literal, secondary: distinct.first)
    }
    return CandidateBar(
      literal: literal,
      primary: distinct.first,
      secondary: distinct.dropFirst().first,
    )
  }

  /// What a space, a return or a punctuation mark should actually insert.
  ///
  /// Neither "always correct" nor "only on tap": a boundary chooses, comparing how far
  /// the taps sat from the keys they struck against how much further the best word sits
  /// from them. SPEC.md section 6.3.
  ///
  /// A word typed sloppily but unambiguously has a best match barely worse than its
  /// own literal, and corrects. A deliberate non-word — a name, an abbreviation, a
  /// password — has a best match far worse than its literal, and stands.
  public func commit(for word: WordInProgress) -> Commit {
    let literal = matcher.literal(for: word.neighborhoods)
    guard !word.isEmpty else { return .literal(literal) }

    // **A correction may re-read a tap. It may not invent one or throw one away.**
    //
    // The search reaches a word three ways: matching a tap to a letter at the distance
    // between them, supposing a letter was never tapped (`omissionPenalty`), or supposing a
    // tap was a stray (`insertionPenalty`). The first is the constellation method working —
    // the user aimed at `hello` and one finger landed on `r`. The other two are the matcher
    // supposing the taps are not what happened, and `Candidate.edits` counts how often it
    // had to. A boundary only ever commits a reading that accounts for every tap, so the
    // candidate considered here is the cheapest one with no edits in it.
    //
    // **This is a filter and not a veto, and the difference cost a real correction.** The
    // rule first written here refused to commit when the single best candidate carried an
    // edit. Every test passed — at dead-centre taps on a 430pt keyboard the best candidate
    // for all sixteen fixtures happens to be edit-free — and then `hrllo` stopped
    // correcting in the hand at 402pt, because off-centre taps had let an edit-carrying
    // candidate overtake `hello` at the top of the list. Taking the best edit-free
    // candidate rather than giving up on the whole word is the same rule stated correctly.
    // SPEC.md Appendix A.29.
    // `readings` and not `candidates`: a run of taps can be two words with a space missing
    // between them, and a split is a reading of the taps like any other. It is charged the
    // distance from the tap to the space bar and carries no edit of its own, so it competes
    // on the same terms and passes through every rule below unchanged. SPEC.md A.34.
    let ranked = matcher.readings(for: word.neighborhoods)
    guard let best = ranked.first(where: { $0.edits == 0 }) else { return .literal(literal) }
    if best.text == literal { return .literal(literal) }

    // **A word the user actually typed is never replaced.** The rule below asks only
    // whether a candidate sits close enough to the taps, and a close-enough candidate can
    // be a different real word: reported 2026-09-06, `editing` going in as `doting`, and
    // a trailing `s` dropped to leave another word entirely. Nothing in the cost tells
    // those apart from a genuine typo, because a typo and a correctly typed word land in
    // the same place when the fingers are accurate.
    //
    // The test is the insertion and not the tap form, so the corrections that exist to
    // rewrite a word into a different string still fire: `dont` is in the lexicon with
    // `don't` as its insertion, so it is not "already a word" by this rule, while
    // `editing` inserts itself and is. SPEC.md Appendix A.16.
    //
    // What to suggest and when to overwrite are two decisions. This changes only the
    // second: the candidate is still offered in the bar, and a tap on it still applies.
    if matcher.lexicon.entries(forTapForm: literal).contains(where: { $0.insertion == literal }) {
      return .literal(literal)
    }

    // **Why the candidate above is the best edit-free one rather than the best one.**
    //
    // **Measured over the whole probe set at dead-centre taps, the edit count separates the
    // wanted corrections from the unwanted ones exactly.** All sixteen one-key-slip
    // fixtures reach their word with zero edits, at a cost of 1.0 — `becahse` → `because`
    // is the one at 1.5, and it is still zero edits, because `h` to `c` is simply two keys
    // of distance. Every edit-carrying candidate in the set is junk: `iphone` → `phone`,
    // `jonah` → `josh`, `hte` → `hate`, `teh` → `eh`, `ios` → `bios`, `borekey` → `horsey`,
    // `tg` → `g`, `gm` → `g`, `vx` → `v`, `qk` → `k`, `zj` → `j`, `mn` → `m`, `asdf` →
    // `add`, `aapl` → `asp`, `wifi` → `wig`, `xyz` → `ditz`, `kocienda` → `kickers`.
    //
    // **This is also where the slack formula was breaking.** An edit costs a flat 1.5
    // while the slack is `0.5 * tapCount`, so from three taps up an edit is always
    // affordable and gets *more* affordable the longer the word — `iphone` → `phone` paid
    // 1.5 against a slack of 3.0 and `borekey` → `horsey` survived by half a unit out of
    // 4.0. The defect is dividing a per-event penalty by the word's length. Rather than
    // retune the divisor, the two kinds of cost are separated: distance is per-tap and
    // still measured per-tap below, and an edit is a single event that a boundary does not
    // buy at any length. SPEC.md Appendix A.29.
    //
    // What to suggest and when to overwrite stay two decisions. An edit-carrying candidate
    // is still ranked, still shown in the bar, and a tap on it still applies it.

    // **A tie keeps the literal.** The comparison is strict, and that is not a rounding
    // preference — it is the only side of an exact tie the asymmetry permits. A tie means
    // the evidence is exactly balanced between what the user typed and something else,
    // while the two outcomes cost very different amounts to undo: a wrong autocorrection
    // has to be noticed, selected and retyped, a missed one costs a backspace. So where
    // the arithmetic cannot separate them, the typing wins.
    //
    // Measured at dead-centre taps, where `literalCost` is exactly zero and the slack is
    // therefore `0.5 * tapCount` and nothing else, six of eleven unwanted rewrites were
    // exact ties and stood on this rule: `jonah` → `josh`, `isnthere` → `anthers`,
    // `qwer` → `weer`, `ios` → `bios`, `hte` → `hate`, `teh` → `eh`. SPEC.md A.22.
    //
    // Five of those six carry an edit and so never reach this comparison any more — the
    // rule above stops them one line earlier and for a different reason. `qwer` → `weer`
    // is the one still standing here, and it is why this stays a rule rather than becoming
    // a historical note: an exact tie between two edit-free readings is a real state.
    //
    // **Two more are ties in arithmetic and not in IEEE, and still correct.** `np` → `no`
    // and `pw` → `ow` accumulate a cost of 0.9999999999999997 against a slack of 1.0 —
    // three parts in 10^16 below the boundary, from summing distances that are each 1.0 by
    // construction. No tolerance is applied here, because a tolerance on this comparison
    // would be a tuning constant with nothing measured behind it, and because the same
    // one-ULP arithmetic is already recorded in A.20 as a property of the geometry rather
    // than something to paper over. It is a known limit of the rule, not a defect in it.
    let slack = matcher.literalCost(for: word.neighborhoods)
      + Tuning.correctionSlackPerTap * Double(word.tapCount)
    return best.cost < slack ? .correction(best.text) : .literal(literal)
  }
}
