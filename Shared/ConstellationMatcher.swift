// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   Ken Kocienda, Creative Selection — the origin of the constellation method.
//   SPEC.md sections 5.5 and 6.3 for the derivation of every constant in Tuning.

import CoreGraphics

/// One tap, recorded as where it landed rather than as what it hit. The position is
/// the signal the whole algorithm runs on; resolving it to a letter at record time
/// would throw that signal away before anything could use it.
public struct Tap: Sendable, Equatable {
  public let point: CGPoint
  public let sequence: Int

  public init(point: CGPoint, sequence: Int) {
    self.point = point
    self.sequence = sequence
  }
}

/// The letters one tap could plausibly have meant, with what each would have cost.
///
/// Never empty: a tap inside the keyboard always has a nearest key, so no caller has
/// to handle the empty case. Always sorted by cost, so `first` is the literal.
public struct TapNeighborhood: Sendable {
  public let candidates: [(letter: Character, cost: Double)]

  public var literal: Character { candidates[0].letter }

  public func cost(of letter: Character) -> Double? {
    candidates.first { $0.letter == letter }?.cost
  }

  public var letters: Set<Character> { Set(candidates.map(\.letter)) }
}

/// What the matcher read a run of taps as: one word, or two words with a space between
/// them.
///
/// **Two is the ceiling, and it is the same judgement that forgives one dropped letter.**
/// A split supposes the user meant a space and did not leave one, which is one supposition
/// about what happened; a reading with two of them supposes twice. Three words are not
/// expressible here rather than being ruled out somewhere downstream.
public enum Reading: Sendable, Equatable {
  case word(LexiconEntry)
  case split(LexiconEntry, LexiconEntry)

  /// What goes into the document.
  public var text: String {
    switch self {
    case .word(let entry): return entry.insertion
    case .split(let first, let second): return "\(first.insertion) \(second.insertion)"
    }
  }

  /// The single entry this reading is, or nothing when it is a split. A split's halves
  /// are each a single word, and this is how the search takes them apart to build one.
  public var singleWord: LexiconEntry? {
    if case .word(let entry) = self { return entry }
    return nil
  }

  /// Whether every word here inserts exactly what was tapped. Only used to break ties
  /// towards the reading that changes nothing.
  var isPlain: Bool {
    switch self {
    case .word(let entry): return entry.insertion == entry.tapForm
    case .split(let first, let second):
      return first.insertion == first.tapForm && second.insertion == second.tapForm
    }
  }
}

/// A reading the matcher is proposing, and what it cost to propose it.
public struct Candidate: Sendable, Equatable {
  public let reading: Reading
  public let cost: Double
  public let edits: Int

  public init(reading: Reading, cost: Double, edits: Int) {
    self.reading = reading
    self.cost = cost
    self.edits = edits
  }

  public var text: String { reading.text }
}

/// Every number the matcher's behaviour depends on, named and in one place.
///
/// They are constants rather than literals scattered through the search because each
/// one is a claim about how people type, and a claim you cannot find is a claim you
/// cannot revise when real typing disagrees with it.
public enum Tuning {
  /// The 3x3 block of keys around the one that was struck, clamped to the keys that
  /// exist rather than padded. At the corners of the keyboard a neighbourhood is
  /// legitimately smaller than nine; see SPEC.md section 5.2.
  public static let neighborhoodRows = 1
  public static let neighborhoodColumns = 1

  /// What it costs to suppose the user missed a key out, or hit one twice. In
  /// normalized key units, so it is commensurate with the distance costs it competes
  /// against: 1.5 means "a dropped tap is worth about a key and a half of sloppiness".
  public static let omissionPenalty: Double = 1.5
  public static let insertionPenalty: Double = 1.5

  /// Dropped and doubled taps are what fast thumbs on glass produce, so one is
  /// forgiven. One edit covers the overwhelming majority of real slips; allowing two
  /// multiplies the search for words nobody meant.
  public static let maxEdits = 1


  /// How many partial matches stay alive. Bounded so that typing time never depends on
  /// how many words happen to look like what is being typed.
  public static let beamWidth = 256

  /// How far past the literal's own sloppiness a correction may sit and still be
  /// applied on space, per tap.
  ///
  /// This is the threshold in the commit rule, SPEC.md section 6.3: a boundary chooses
  /// between the literal and the best candidate on how far the typing sits from the
  /// word. The literal's cost is the intrinsic sloppiness of the
  /// typing — how far the fingers landed from the keys they hit. A correction that
  /// costs barely more than that is a word the user was plainly aiming at; one that
  /// costs much more is the matcher reaching. 0.5 normalized units per tap is half a
  /// key of extra reach per letter, and it is a starting value rather than a measured
  /// one.
  public static let correctionSlackPerTap: Double = 0.5
}

/// Turns a sequence of taps into ranked words, mechanistically.
///
/// The search is a beam over states of `(trie node, taps consumed, edits used)`. A
/// match consumes a tap and follows an edge; an omission follows an edge without
/// consuming a tap; an insertion consumes a tap without following an edge. Because
/// every transition advances the node depth or the tap index, the state space is a
/// DAG and can be walked layer by layer with no cycle check and no backtracking.
///
/// Nothing here reads a clock, a random number, or any state that survives the call.
/// The same taps and the same lexicon give the same answer, always — which is the
/// point of the whole project.
public struct ConstellationMatcher: Sendable {
  public let geometry: KeyboardGeometry
  public let lexicon: Lexicon

  public init(geometry: KeyboardGeometry, lexicon: Lexicon) {
    self.geometry = geometry
    self.lexicon = lexicon
  }

  // MARK: - Neighbourhoods

  /// The 3x3 block of scored keys around the tap, clamped to the keys that exist.
  ///
  /// There is no row above `q` and no column left of `a`. The block is defined over
  /// the grid and then intersected with the keyboard, so an edge tap simply has fewer
  /// neighbours rather than a special case.
  ///
  /// **The space bar is in the block and used not to be.** The pool was `letterKeys`, so
  /// a tap on a letter could never be scored as a space and a tap on the space bar was
  /// not scored at all — this returned `nil` for it. Widening the pool to `scoredKeys` is
  /// the whole change: the row walk already picks up the bottom row for a tap in row 2
  /// and row 2 for a tap on the space bar, because it finds the block by position rather
  /// than by arithmetic on indices. SPEC.md A.20.
  public func neighborhood(for point: CGPoint) -> TapNeighborhood? {
    guard let hit = geometry.hitTest(point), hit.scoredCharacter != nil else { return nil }

    var found: [(Character, Double)] = []
    for rowOffset in -Tuning.neighborhoodRows...Tuning.neighborhoodRows {
      let row = hit.id.row + rowOffset
      let rowKeys = geometry.scoredKeys.filter { $0.id.row == row }.sorted {
        $0.frame.minX < $1.frame.minX
      }
      guard !rowKeys.isEmpty else { continue }

      // Within the row, the column of the block is the key nearest the tap in x. On
      // the offset rows that is not the same index as the struck key, which is exactly
      // why the block is found by position rather than by arithmetic on indices.
      var nearest = 0
      for (i, key) in rowKeys.enumerated()
      where abs(key.center.x - point.x) < abs(rowKeys[nearest].center.x - point.x) {
        nearest = i
      }

      for columnOffset in -Tuning.neighborhoodColumns...Tuning.neighborhoodColumns {
        let index = nearest + columnOffset
        guard index >= 0, index < rowKeys.count else { continue }
        let key = rowKeys[index]
        found.append((key.scoredCharacter!, geometry.normalizedManhattan(from: point, to: key)))
      }
    }

    guard !found.isEmpty else { return nil }
    // Sorted by cost, then by letter, so the ordering is total and reproducible rather
    // than dependent on the order the rows happened to be walked.
    found.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
    return TapNeighborhood(candidates: found.map { (letter: $0.0, cost: $0.1) })
  }

  /// What the taps literally say: the nearest letter to each, in order. Always
  /// available, never involves the lexicon, and is the ground truth the other two
  /// bubbles are a proposal against.
  public func literal(for neighborhoods: [TapNeighborhood]) -> String {
    String(neighborhoods.map(\.literal))
  }

  /// The intrinsic sloppiness of the typing: how far the fingers landed from the keys
  /// they actually struck. The commit policy compares a correction against this rather
  /// than against zero, because a user typing carelessly should not thereby lose their
  /// corrections, and a user typing precisely should not have them forced on.
  public func literalCost(for neighborhoods: [TapNeighborhood]) -> Double {
    neighborhoods.reduce(0) { $0 + $1.candidates[0].cost }
  }

  // MARK: - The search

  public func candidates(for neighborhoods: [TapNeighborhood], limit: Int = 8) -> [Candidate] {
    guard !neighborhoods.isEmpty else { return [] }
    let tapCount = neighborhoods.count

    // Layer = node depth + taps consumed. Every transition increases it by one, so
    // walking layers in order visits each state after everything that can reach it.
    var layers: [[StateKey: Double]] = Array(
      repeating: [:], count: maxDepth(tapCount) + tapCount + 1)
    layers[0][StateKey(node: 0, taps: 0, edits: 0)] = 0

    var results: [Candidate] = []

    for layer in 0..<layers.count {
      var states = Array(layers[layer])
      guard !states.isEmpty else { continue }

      // Prune to the beam. Sorted by cost, then by the state itself, so that which
      // states survive a tie never depends on dictionary ordering.
      if states.count > Tuning.beamWidth {
        states.sort {
          $0.value == $1.value
            ? ($0.key.node, $0.key.taps, $0.key.edits) < ($1.key.node, $1.key.taps, $1.key.edits)
            : $0.value < $1.value
        }
        states.removeSubrange(Tuning.beamWidth...)
      }

      for (state, cost) in states {
        // A complete word: the trie node is terminal and every tap has been consumed.
        if state.taps == tapCount {
          for index in lexicon.entryIndices(at: state.node) {
            results.append(
              Candidate(
                reading: .word(lexicon.entries[index]), cost: cost, edits: state.edits))
          }
        }

        let children = lexicon.children(of: state.node)
        guard !children.isEmpty || state.taps < tapCount else { continue }

        if state.taps < tapCount {
          let neighborhood = neighborhoods[state.taps]

          // Match: this tap meant this letter.
          for (letter, stepCost) in neighborhood.candidates {
            guard let next = children[letter] else { continue }
            relax(
              &layers, layer + 1,
              StateKey(node: next, taps: state.taps + 1, edits: state.edits),
              cost + stepCost)
          }

          // Insertion: this tap was a stray, and the word does not account for it.
          if state.edits < Tuning.maxEdits {
            relax(
              &layers, layer + 1,
              StateKey(node: state.node, taps: state.taps + 1, edits: state.edits + 1),
              cost + Tuning.insertionPenalty)
          }
        }

        // Omission: the word has a letter here that never got tapped.
        if state.edits < Tuning.maxEdits {
          for (_, next) in children {
            relax(
              &layers, layer + 1,
              StateKey(node: next, taps: state.taps, edits: state.edits + 1),
              cost + Tuning.omissionPenalty)
          }
        }
      }
    }

    // Ties break first towards the entry that changes nothing — where "well" and
    // "we'll" match a tap sequence equally well, the plain word wins, because a
    // keyboard whose virtue is predictability should not reach for the apostrophe on a
    // coin toss. Beyond that they break on the inserted text, never on discovery order:
    // a ranking that depends on how a dictionary happened to enumerate is not
    // mechanistically predictable, however deterministic its scores are.
    return Self.ranked(results, limit: limit)
  }

  /// Sorts readings and keeps the cheapest of each distinct text.
  ///
  /// Ties break first towards the reading that changes nothing — where `well` and `we'll`
  /// match a tap sequence equally well, the plain word wins, because a keyboard whose
  /// virtue is predictability should not reach for the apostrophe on a coin toss. Beyond
  /// that they break on the inserted text, never on discovery order: a ranking that
  /// depends on how a dictionary happened to enumerate is not mechanistically predictable,
  /// however deterministic its scores are.
  static func ranked(_ readings: [Candidate], limit: Int) -> [Candidate] {
    var sorted = readings
    sorted.sort { a, b in
      if a.cost != b.cost { return a.cost < b.cost }
      let aPlain = a.reading.isPlain
      let bPlain = b.reading.isPlain
      if aPlain != bPlain { return aPlain }
      return a.text < b.text
    }
    var seen = Set<String>()
    var unique: [Candidate] = []
    for candidate in sorted where seen.insert(candidate.text).inserted {
      unique.append(candidate)
      if unique.count == limit { break }
    }
    return unique
  }

  // MARK: - Splits

  /// Readings of these taps as two words, where one tap was the space between them.
  ///
  /// **A split is not a transition in the search, and that is the whole design.** The beam
  /// already has a transition shaped exactly like a free edit inserted anywhere at a fixed
  /// price — `omissionPenalty` follows a trie edge without consuming a tap and without ever
  /// reading a neighbourhood. Letting a space through that door would make `together` into
  /// `to get her` for the cost of one omission, at any position, with nothing about the
  /// typing to justify it.
  ///
  /// So a split is built here instead, out of the two things that do look at what happened:
  ///
  /// **The tap that becomes the space has to have the space bar in its own neighbourhood**,
  /// and it is charged the same distance any other letter would be. The space bar is row 3
  /// and `neighborhood(for:)` reads the 3x3 block around the key that was struck, so only
  /// rows 2 and 3 carry a space candidate at all. `isnthere` splits at its `n`, which is
  /// row 2 and sits directly above the space bar. `together` would have to split at `g` or
  /// `h`, which are row 1 and carry no space at any price, and it would need two of them
  /// besides.
  ///
  /// **And every other tap keeps the letter it landed on.** Each half has to be a word whose
  /// tap form is exactly what those taps literally say. A split is already one supposition
  /// about the typing — that a tap meant a space — and a reading that also re-letters its
  /// way to two words is supposing twice. That is the same judgement A.29 makes about
  /// edits, and it is not free: `jonah` at dead centre reaches `ho ah` by moving one tap
  /// from `j` to `h`, which is a real cost of 1.0 and still lands inside a five-tap word's
  /// slack of 2.5. Requiring the halves to be literal is what stops it, and it stops the
  /// whole class rather than that word.
  ///
  /// **Both of those are choices this keyboard is making, not laws of the algorithm.** They
  /// hold only while splits are built this way, and two tests hold them:
  /// `aTapAwayFromTheSpaceBarCannotSplit` and `aSplitReadsEveryOtherTapLiterally`. The
  /// moment a split can be reached through the omission transition the first guarantee is
  /// gone and nothing else in the code would notice. SPEC.md A.34.
  ///
  /// **Known limit:** a one-letter half is where the remaining false splits are — `into`
  /// reads as `i to` and `about` as `a out`, both edit-free and both cheap. Neither can be
  /// committed, because the commit rule never replaces a word the user actually typed, and
  /// both are real words. They can still reach the bar's right-hand slot. No minimum half
  /// length is imposed, because `a` and `I` are words people start sentences with and there
  /// is nothing measured to set the threshold from.
  public func splits(for neighborhoods: [TapNeighborhood], limit: Int = 8) -> [Candidate] {
    // Both halves have to be a word, so the shortest run that can split is three taps.
    guard neighborhoods.count >= 3 else { return [] }

    var found: [Candidate] = []
    for index in 1..<(neighborhoods.count - 1) {
      guard let spaceCost = neighborhoods[index].cost(of: " ") else { continue }
      let left = Array(neighborhoods[..<index])
      let right = Array(neighborhoods[(index + 1)...])
      let leftWords = lexicon.entries(forTapForm: literal(for: left))
      guard !leftWords.isEmpty else { continue }
      let rightWords = lexicon.entries(forTapForm: literal(for: right))
      guard !rightWords.isEmpty else { continue }

      // The space is charged like any other tap — the distance from where the finger
      // landed to the key it is being read as — and the letters are charged what they
      // literally cost. Nothing here is a flat penalty, which is what keeps a split
      // commensurate with the single words it competes against.
      let cost = literalCost(for: left) + spaceCost + literalCost(for: right)
      for first in leftWords {
        for second in rightWords {
          found.append(Candidate(reading: .split(first, second), cost: cost, edits: 0))
        }
      }
    }
    return Self.ranked(found, limit: limit)
  }

  /// Every reading of these taps, single words and splits together, best first.
  ///
  /// This is what the bar and the commit rule ask for. `candidates(for:)` stays the
  /// single-word search underneath it, because a split is built out of two of those.
  public func readings(for neighborhoods: [TapNeighborhood], limit: Int = 8) -> [Candidate] {
    Self.ranked(
      candidates(for: neighborhoods, limit: limit) + splits(for: neighborhoods, limit: limit),
      limit: limit)
  }

  private func relax(
    _ layers: inout [[StateKey: Double]], _ layer: Int, _ key: StateKey, _ cost: Double
  ) {
    guard layer < layers.count else { return }
    if let existing = layers[layer][key], existing <= cost { return }
    layers[layer][key] = cost
  }

  /// How deep the search may go: the tap count plus the edits it is allowed to spend
  /// inventing letters nobody typed.
  private func maxDepth(_ tapCount: Int) -> Int { tapCount + Tuning.maxEdits }
}

/// One position in the search: how far into a word, how far into the taps, and how
/// many slips have been forgiven to get here. Hoisted to file scope so the relaxation
/// helper can name it.
private struct StateKey: Hashable {
  let node: Int
  let taps: Int
  let edits: Int
}
