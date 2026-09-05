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

  /// Whether shift was down for the word's first tap.
  ///
  /// The matcher works in lowercase — "Don't" and "don't" are the same constellation, and
  /// making them different entries would double the lexicon to say nothing. But committing
  /// a correction rewrites what is already in the field, so the casing has to be carried
  /// somewhere or the first word of every sentence quietly loses its capital. Here is that
  /// somewhere: taken from the first tap and applied to whatever is committed.
  public private(set) var startsCapitalized = false

  public init() {}

  public var isEmpty: Bool { neighborhoods.isEmpty }
  public var tapCount: Int { neighborhoods.count }

  public mutating func append(_ neighborhood: TapNeighborhood, capitalized: Bool = false) {
    if neighborhoods.isEmpty { startsCapitalized = capitalized }
    neighborhoods.append(neighborhood)
  }

  public mutating func removeLast() {
    if !neighborhoods.isEmpty { neighborhoods.removeLast() }
    if neighborhoods.isEmpty { startsCapitalized = false }
  }

  public mutating func reset() {
    neighborhoods.removeAll()
    startsCapitalized = false
  }

  /// Applies the word's own casing to text the matcher produced. Only the first letter:
  /// a correction can be a different length from the taps that produced it ("dont" is
  /// four taps and "don't" is five characters), so there is no honest per-tap mapping.
  public func cased(_ text: String) -> String {
    guard startsCapitalized, let first = text.first else { return text }
    return String(first).uppercased() + text.dropFirst()
  }
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
    let candidates = matcher.candidates(for: word.neighborhoods)

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

    guard let best = matcher.candidates(for: word.neighborhoods, limit: 1).first else {
      return .literal(literal)
    }
    if best.text == literal { return .literal(literal) }

    let slack = matcher.literalCost(for: word.neighborhoods)
      + Tuning.correctionSlackPerTap * Double(word.tapCount)
    return best.cost <= slack ? .correction(best.text) : .literal(literal)
  }
}
