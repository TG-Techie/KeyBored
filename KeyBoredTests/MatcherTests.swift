// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 8 names the invariants these tests exist to hold.

import CoreGraphics
import Testing

@testable import KeyBored

/// The iPhone 15 Pro Max width the reference screenshot was taken at, so that the
/// geometry assertions can be checked against Appendix A's measured pixels directly.
private let referenceWidth: CGFloat = 430

private func makeMatcher() -> ConstellationMatcher {
  ConstellationMatcher(
    geometry: KeyboardGeometry(width: referenceWidth),
    lexicon: EnglishLexicon.make(),
  )
}

/// Taps placed exactly on the key centres: the "perfect constellation" of a word.
private func perfectTaps(_ word: String, _ geometry: KeyboardGeometry) -> [CGPoint] {
  word.map { geometry.key(for: $0)!.center }
}

private func neighborhoods(_ points: [CGPoint], _ matcher: ConstellationMatcher)
  -> [TapNeighborhood]
{
  points.map { matcher.neighborhood(for: $0)! }
}

// MARK: - Geometry

@Test func geometryMatchesTheMeasuredStockProportions() {
  let geometry = KeyboardGeometry(width: referenceWidth)
  let q = geometry.key(for: "q")!
  let w = geometry.key(for: "w")!

  // Appendix A, in pixels at 3x: key width 108, column pitch 126, left margin 20.
  #expect(abs(q.frame.width * 3 - 108) < 1.5)
  #expect(abs((w.frame.minX - q.frame.minX) * 3 - 126) < 1.5)
  #expect(abs(q.frame.minX * 3 - 20) < 1.5)
  #expect(abs(q.frame.height * 3 - 135) < 0.5)

  // Row 1 sits half a column pitch in from row 0: 84px against 20px, and half of the
  // 126px pitch is 63.
  let a = geometry.key(for: "a")!
  #expect(abs((a.frame.minX - q.frame.minX) * 3 - 64) < 2)

  // Row 2's letters keep the same pitch as the rows above rather than packing against
  // shift: measured first-letter left edge 210px.
  let z = geometry.key(for: "z")!
  #expect(abs(z.frame.minX * 3 - 210) < 3)
}

@Test func rowsAreOnTheMeasuredPitch() {
  let geometry = KeyboardGeometry(width: referenceWidth)
  let q = geometry.key(for: "q")!
  let a = geometry.key(for: "a")!
  // Row pitch 168px on a 430pt phone. The top row starts 156px below the top of the
  // *plate* — 1617 to 1773 measured on a simulator, 1807 to 1963 on the 430pt reference —
  // but a key's frame is in the keyboard's own view, which begins 52px below the plate
  // top, so row 0 sits at 104 there. Asserting 156 against a frame is what 0.0.5 shipped.
  #expect(abs((a.frame.minY - q.frame.minY) * 3 - 168) < 0.5)
  #expect(abs(q.frame.minY * 3 - 104) < 0.5)
  #expect(abs((q.frame.minY + StockMetrics.systemBandAboveInputView) * 3 - 156) < 0.5)
}

// MARK: - Neighbourhoods

@Test func theNeighborhoodIsTheThreeByThreeBlockClampedToKeysThatExist() {
  let matcher = makeMatcher()
  let geometry = matcher.geometry

  // An interior key has the full nine.
  let g = matcher.neighborhood(for: geometry.key(for: "g")!.center)!
  #expect(g.candidates.count == 9)
  #expect(g.literal == "g")

  // The block is clamped, not padded: q is a corner, so its block runs off the top and
  // off the left and it legitimately has fewer than nine. SPEC.md invariant I3.
  let q = matcher.neighborhood(for: geometry.key(for: "q")!.center)!
  #expect(q.candidates.count < 9)
  #expect(q.literal == "q")
  #expect(q.letters.contains("w"))
  #expect(q.letters.contains("a"))
}

@Test func aNeighborhoodIsNeverEmptyAndIsSortedByCost() {
  let matcher = makeMatcher()
  for key in matcher.geometry.letterKeys {
    let neighborhood = matcher.neighborhood(for: key.center)!
    #expect(!neighborhood.candidates.isEmpty)
    #expect(neighborhood.candidates.count <= 9)
    let costs = neighborhood.candidates.map(\.cost)
    #expect(costs == costs.sorted())
    #expect(neighborhood.literal == key.letter)
  }
}

// MARK: - The algorithm's defining property

@Test func aPerfectConstellationRanksItsOwnWordFirstAtZeroCost() {
  let matcher = makeMatcher()
  for word in ["hello", "keyboard", "the", "predictable", "swift", "constellation"] {
    #expect(!matcher.lexicon.entries(forTapForm: word).isEmpty, "\(word) is not in the lexicon")
    let taps = neighborhoods(perfectTaps(word, matcher.geometry), matcher)
    let candidates = matcher.candidates(for: taps)
    #expect(candidates.first?.entry.tapForm == word)
    #expect(abs(candidates.first!.cost) < 1e-9)
  }
}

@Test func theLiteralIsAlwaysThePerTapNearestLetter() {
  let matcher = makeMatcher()
  // Points scattered deterministically across the letter rows, so this is a property
  // check without a random seed to make it irreproducible.
  for key in matcher.geometry.letterKeys {
    for dx in [-0.3, 0.0, 0.3] {
      let point = CGPoint(
        x: key.center.x + key.frame.width * CGFloat(dx), y: key.center.y)
      guard let neighborhood = matcher.neighborhood(for: point) else { continue }
      let nearest = matcher.geometry.letterKeys.min {
        matcher.geometry.normalizedManhattan(from: point, to: $0)
          < matcher.geometry.normalizedManhattan(from: point, to: $1)
      }!
      #expect(neighborhood.literal == nearest.letter)
    }
  }
}

// MARK: - Determinism, which is the whole point

@Test func theSameTapsGiveTheSameAnswerEveryTime() {
  let matcher = makeMatcher()
  let taps = neighborhoods(perfectTaps("hello", matcher.geometry), matcher)
  let first = matcher.candidates(for: taps).map(\.text)
  for _ in 0..<8 {
    #expect(makeMatcher().candidates(for: taps).map(\.text) == first)
  }
}

// MARK: - Sloppy typing

@Test func aSloppyTapSequenceStillFindsTheWord() {
  let matcher = makeMatcher()
  let geometry = matcher.geometry
  // "hello" typed with every tap a third of a key off to the right and low.
  let points = "hello".map { character -> CGPoint in
    let key = geometry.key(for: character)!
    return CGPoint(
      x: key.center.x + key.frame.width * 0.3, y: key.center.y + key.frame.height * 0.25)
  }
  let taps = neighborhoods(points, matcher)
  #expect(matcher.candidates(for: taps).first?.text == "hello")
}

@Test func aDroppedTapIsForgiven() {
  // One edit is forgiven per word; SPEC.md section 5.3.
  let matcher = makeMatcher()
  let taps = neighborhoods(perfectTaps("helo", matcher.geometry), matcher)
  #expect(matcher.candidates(for: taps).map(\.text).contains("hello"))
}

@Test func aDoubledTapIsForgiven() {
  let matcher = makeMatcher()
  let taps = neighborhoods(perfectTaps("helllo", matcher.geometry), matcher)
  #expect(matcher.candidates(for: taps).map(\.text).contains("hello"))
}

// MARK: - The bar and the commit policy

@Test func theBarNeverShowsThePredictionTwice() {
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("the", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  let bar = predictor.bar(for: word)
  #expect(bar.literal == "the")
  #expect(bar.primary == "the")
  #expect(bar.secondary != "the")
}

@Test func aContractionIsPredictedFromItsApostropheFreeTapForm() {
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("dont", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  #expect(predictor.bar(for: word).primary == "don't")
  #expect(predictor.commit(for: word) == .correction("don't"))
}

@Test func aWordThatIsAlreadyItselfIsNotCorrected() {
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("well", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  // "well" and "we'll" share a tap form; the plain word wins the tie, so nothing is
  // changed under the user.
  #expect(predictor.commit(for: word) == .literal("well"))
}

@Test func aDeliberateNonWordIsLeftAlone() {
  // The commit policy's whole job: a name or an abbreviation whose best match sits far
  // from what was typed must stand rather than being corrected into something else.
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("xkqjv", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  #expect(predictor.commit(for: word) == .literal("xkqjv"))
}

/// A word the user actually typed is never replaced, however close a candidate sits.
///
/// Reported 2026-09-06: `editing` going in as `doting`, and a trailing `s` dropped to leave
/// another word entirely. The commit rule asked only whether a candidate was within the
/// slack, and a candidate that close can be a different real word — nothing in the cost
/// separates a typo from a correctly typed word, because accurate fingers put both in the
/// same place.
///
/// The rule tests the insertion and not the tap form, and these two cases are why: an entry
/// that exists to rewrite a word into a different string still fires, and one that inserts
/// the typed string as itself stands the correction down. SPEC.md Appendix A.16.
@Test func aLiteralThatIsAlreadyAWordIsNeverReplaced() {
  let geometry = KeyboardGeometry(width: referenceWidth)

  func commit(_ typed: String, against entries: [LexiconEntry]) -> Commit {
    let matcher = ConstellationMatcher(geometry: geometry, lexicon: Lexicon(entries: entries))
    var word = WordInProgress()
    for neighborhood in neighborhoods(perfectTaps(typed, geometry), matcher) {
      word.append(neighborhood)
    }
    return Predictor(matcher: matcher).commit(for: word)
  }

  let rewrite = LexiconEntry(tapForm: "dont", insertion: "don't")
  #expect(commit("dont", against: [rewrite]) == .correction("don't"))
  #expect(commit("dont", against: [rewrite, LexiconEntry(tapForm: "dont")]) == .literal("dont"))
}

// MARK: - The lexicon

@Test func twoEntriesCanShareOneTapForm() {
  let lexicon = EnglishLexicon.make()
  let its = lexicon.entries(forTapForm: "its").map(\.insertion).sorted()
  #expect(its == ["it's", "its"])
}

// MARK: - Cost

@Test func theBundledListIsTheOneTheSpecSays() {
  // If this number moves, Shared/Resources/README.md is describing a different file.
  #expect(EnglishLexicon.words().count == 75_646)

  // The words that were missing from the list this replaced, and the reason it was
  // replaced: he typed them and the keyboard corrected them into other words.
  for word in ["editing", "edited", "edits", "cats", "walked", "running"] {
    #expect(EnglishLexicon.words().contains(word), "\(word) is missing from the list")
  }
  let lexicon = EnglishLexicon.make()
  #expect(lexicon.entries(forTapForm: "lol").first?.source == .idiom)
  #expect(lexicon.entries(forTapForm: "omw").isEmpty)
}

/// The lexicon is built once, when the keyboard extension is loaded, and until it is
/// built the keyboard cannot draw a bar. So its construction is on the path a person
/// watches, which the match latency below is not.
///
/// Worth a measurement because the list grew fourfold on 2026-09-06, from 19,217 words to
/// 75,646. Same loose bound and same reasoning as the test below: an order of magnitude,
/// not a few milliseconds.
///
/// **The bound is in seconds because this runs unoptimised.** The number that matters was
/// measured on the shipping configuration instead, with a probe build of the extension
/// reading its own clock: **34 ms in a release build**, against 2 to 5 seconds for the same
/// work in a debug simulator build on a loaded machine. So this test guards the order of
/// magnitude of the debug number and says nothing about the release one. SPEC.md A.16.
@Test func buildingTheLexiconStaysQuickEnoughToDoAtLaunch() {
  let start = ContinuousClock.now
  let lexicon = EnglishLexicon.make()
  let elapsed = ContinuousClock.now - start
  #expect(lexicon.count > 75_000)
  #expect(elapsed < .seconds(8), "building the lexicon took \(elapsed)")
}

/// How big the trie is, in the one unit a test in this suite can honestly measure.
///
/// The question worth asking is what the trie costs in memory, because that is the budget
/// a keyboard extension is killed for exceeding rather than warned about. This test does
/// not ask it, and the previous version of it — which read the process footprint either
/// side of building the lexicon and asserted the difference was under 40 MB — could not
/// either. swift-testing runs the whole suite in one process in randomized order, so the
/// difference measures whatever else has run: it reported -80.7 MB on one run and
/// +145.7 MB on the next, with the process baseline moving from 101 MB to 243 MB. An
/// assertion of `cost < 40` passes on a negative cost, so it was green having measured
/// nothing at all.
///
/// The node count is deterministic, has no such dependence, and moves for exactly the
/// reason the footprint would: the trie's cost is roughly 161 bytes a node, so this bound
/// catches the list growing by an order of magnitude. The megabytes are measured by
/// `tools/footprint.swift`, in a process that does nothing else, and what is left on a
/// real device is reported by `MemoryBudget`.
@Test func theTrieStaysTheSizeItsWordListImplies() {
  let lexicon = EnglishLexicon.make()
  #expect(lexicon.count > 75_000)
  #expect(lexicon.nodes.count < 250_000, "the trie has \(lexicon.nodes.count) nodes")
}

@Test func matchingAWordStaysFastOnTheRealLexicon() {
  // SPEC.md invariant I11: one match against the full lexicon stays well inside a
  // keystroke interval. The lexicon
  // grew 24x when the real word list replaced the starter one, so that claim is worth
  // a measurement rather than a re-reading.
  //
  // The bound is deliberately loose — this runs on a simulator on a shared machine, and
  // a flaky timing test that gets deleted guards nothing. It is here to catch an order
  // of magnitude, not a regression of a few microseconds.
  let matcher = makeMatcher()
  let taps = neighborhoods(perfectTaps("constellation", matcher.geometry), matcher)

  let start = ContinuousClock.now
  for _ in 0..<50 { _ = matcher.candidates(for: taps) }
  let perMatch = (ContinuousClock.now - start) / 50

  #expect(perMatch < .milliseconds(20), "one match took \(perMatch)")
}
