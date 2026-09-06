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
    #expect(candidates.first?.reading.singleWord?.tapForm == word)
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

/// **An exact tie keeps what the user typed.**
///
/// The commit rule compares the best candidate's cost against a slack, and the two sides of
/// that comparison are not symmetric in what they cost to undo: a wrong autocorrection has
/// to be noticed, selected and retyped, while a missed one costs a backspace. So the
/// comparison is strict, and a tie falls to the literal.
///
/// These are the cases that made it strict, measured on 2026-09-06 with taps placed exactly
/// on the key centres. At dead centre `literalCost` is zero, so the slack is
/// `0.5 * tapCount` and nothing else — and one edit costs 1.5, which lands on an exact
/// multiple of the slack for words of three, four, five and eight taps alike. Six of the
/// eleven unwanted rewrites in that probe were exact ties, including the user's own name.
///
/// `np` → `no` and `pw` → `ow` are deliberately not here. They are ties by arithmetic and
/// three parts in 10^16 below the boundary in IEEE, so they still correct; the comment on
/// the comparison in `Predictor.commit(for:)` says why no tolerance is applied.
/// SPEC.md Appendix A.22.
/// `isnthere` was in this list and is not any more. It is not a tie that stopped standing:
/// splits gave the taps a reading that was never available before — `is there`, every tap
/// but one read as the letter it landed on and the `n` read as the space bar above which it
/// sits — at 1.2 against a slack of 4.0. That is the correction item 3 was asked for, and
/// `theTapsCanSayTwoWords` is where it is asserted. SPEC.md A.34.
@Test(arguments: ["jonah", "qwer", "ios", "hte", "teh"])
func anExactTieKeepsWhatWasTyped(typed: String) {
  let matcher = makeMatcher()
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps(typed, matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  // The premise: these are ties rather than comfortable wins, so the test would pass
  // vacuously if the costs ever moved. Assert the premise, not just the outcome.
  let slack = matcher.literalCost(for: word.neighborhoods)
    + Tuning.correctionSlackPerTap * Double(word.tapCount)
  let best = matcher.candidates(for: word.neighborhoods, limit: 1).first
  #expect(best != nil)
  #expect(
    abs((best?.cost ?? .nan) - slack) < 1e-9,
    "\(typed) is no longer an exact tie: best \(best?.cost ?? .nan) against slack \(slack)")
  #expect(Predictor(matcher: matcher).commit(for: word) == .literal(typed))
}

/// The other side of the same rule: standing ties down must not stand real corrections down.
///
/// Every one of these is a one-key slip on a word somebody meant, and every one of them wins
/// strictly rather than on a tie — typically at a cost near 1.0 against a slack of 2.5 or
/// more. That gap is why the tie change is safe: a wanted correction is not close to the
/// boundary, and a rewrite that arrives exactly on it is the matcher reaching.
@Test(
  arguments: [
    ("hrllo", "hello"), ("helli", "hello"), ("thr", "the"), ("thrre", "there"),
    ("keyboatd", "keyboard"), ("mornibg", "morning"), ("abiut", "about"),
    ("peopke", "people"), ("becahse", "because"), ("woukd", "would"),
    ("thsnks", "thanks"), ("reslly", "really"), ("somethibg", "something"),
    ("olease", "please"), ("tomorrpw", "tomorrow"), ("frienf", "friend"),
  ])
func aOneKeySlipStillCorrectsAndNotOnATie(typed: String, intended: String) {
  let matcher = makeMatcher()
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps(typed, matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  let slack = matcher.literalCost(for: word.neighborhoods)
    + Tuning.correctionSlackPerTap * Double(word.tapCount)
  let best = matcher.candidates(for: word.neighborhoods, limit: 1).first
  #expect(
    (best?.cost ?? .infinity) < slack - 0.25,
    "\(typed) now wins by less than a quarter unit and is near the tie boundary")
  #expect(Predictor(matcher: matcher).commit(for: word) == .correction(intended))
}

/// **A correction may re-read a tap; it may not invent one or throw one away.**
///
/// The whole measured set in one assertion, because the deliverable is the rule and not
/// the five words Jonah named. At dead-centre taps every one of the sixteen one-key-slip
/// fixtures reaches its word with zero edits, and every edit-carrying candidate in the
/// non-word set is junk — so the edit count separates the two exactly, and the boundary
/// stops buying edits at any word length. SPEC.md Appendix A.29.
///
/// The four exceptions are named rather than omitted. `np` → `no`, `pw` → `ow`,
/// `sry` → `dry` and `keybored` → `keynoted` are edit-free substitutions costing the same
/// as a genuine slip at the same length, so nothing in this scorer can tell them from the
/// corrections above that must keep firing. They are a limit of the rule and are listed
/// here so the next reader does not mistake them for something this test missed.
@Test func theBoundaryNeverBuysAnEdit() {
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)

  func commit(_ typed: String) -> Commit {
    var word = WordInProgress()
    for neighborhood in neighborhoods(perfectTaps(typed, matcher.geometry), matcher) {
      word.append(neighborhood)
    }
    return predictor.commit(for: word)
  }

  // Deliberate non-words. Every one of these must go in as typed.
  // `isnthere` is deliberately absent: it is a run of two words with the space struck as
  // an `n`, and since splits exist it commits as `is there`. SPEC.md A.34.
  let mustStand = [
    "jonah", "qwer", "ios", "hte", "teh", "iphone", "borekey", "xkqjv",
    "kocienda", "asdf", "zxcv", "hjkl", "xyz", "aapl", "wifi", "tg", "hj", "gm", "vx",
    "qk", "zj", "mn", "ok", "brb", "idk", "tbh",
  ]
  for typed in mustStand {
    #expect(commit(typed) == .literal(typed), "\(typed) was rewritten")
  }

  // The four this rule does not reach, asserted as they actually behave so that the day
  // one of them changes is a day this test fails and someone reads why.
  #expect(commit("np") == .correction("no"))
  #expect(commit("pw") == .correction("ow"))
  #expect(commit("sry") == .correction("dry"))
  #expect(commit("keybored") == .correction("keynoted"))

  // And the corrections that must keep firing.
  let mustCorrect = [
    ("hrllo", "hello"), ("helli", "hello"), ("thr", "the"), ("thrre", "there"),
    ("keyboatd", "keyboard"), ("mornibg", "morning"), ("abiut", "about"),
    ("peopke", "people"), ("becahse", "because"), ("woukd", "would"),
    ("thsnks", "thanks"), ("reslly", "really"), ("somethibg", "something"),
    ("olease", "please"), ("tomorrpw", "tomorrow"), ("frienf", "friend"),
  ]
  for (typed, intended) in mustCorrect {
    #expect(commit(typed) == .correction(intended), "\(typed) no longer corrects")
  }

  // The premise the rule rests on, asserted rather than assumed: none of the sixteen needs
  // an edit, and the rule would be silently vacuous if that ever stopped being true.
  for (typed, _) in mustCorrect {
    var word = WordInProgress()
    for neighborhood in neighborhoods(perfectTaps(typed, matcher.geometry), matcher) {
      word.append(neighborhood)
    }
    let best = matcher.candidates(for: word.neighborhoods, limit: 1).first
    #expect(best?.edits == 0, "\(typed) now reaches its word through an edit")
  }
}

/// **The same corrections, with each tap off centre by a different amount.**
///
/// Every other fixture in this file lands each tap on its key's exact centre, and that
/// shared convenience is a shared blind spot — `SPEC.md` section 8.1 has the last one. It
/// hid a real defect for the length of one install: the boundary rule was first written to
/// refuse the whole word when the *single best* candidate carried an edit. Every test here
/// passed, because at dead centre the best candidate is edit-free for all sixteen fixtures.
/// Then `hrllo` stopped correcting in the hand at 402pt, and typing it again after the fix
/// corrected it — the same word, the same field, before and after.
///
/// **A uniform offset does not reproduce it and a varying one does.** Nudging every tap by
/// the same fraction leaves `hello` at the head of the list at every offset that was tried;
/// real fingers miss each key differently, and it takes that to let an edit-carrying
/// candidate overtake. So the offsets here are per-tap, derived from the tap's index so
/// that a failure names the same word every time.
@Test func aCorrectionSurvivesTapsThatMissEachKeyDifferently() {
  let matcher = makeMatcher()
  let predictor = Predictor(matcher: matcher)
  // `thrre` is deliberately not here. Off centre it commits `three` rather than `there`,
  // and both are edit-free readings of the same five taps at almost the same cost — an
  // ambiguity in the lexicon rather than anything this test is about.
  let cases = [
    ("hrllo", "hello"), ("helli", "hello"), ("thr", "the"), ("keyboatd", "keyboard"),
    ("mornibg", "morning"), ("abiut", "about"), ("peopke", "people"),
    ("becahse", "because"), ("woukd", "would"), ("thsnks", "thanks"),
    ("reslly", "really"), ("somethibg", "something"), ("olease", "please"),
    ("tomorrpw", "tomorrow"), ("frienf", "friend"),
  ]
  // Five offsets cycled by tap index, all well inside a cap so the literal cannot move.
  let offsets: [(CGFloat, CGFloat)] = [
    (0.30, 0.18), (-0.28, -0.20), (0.12, -0.30), (-0.32, 0.22), (0.22, 0.30),
  ]

  for (typed, intended) in cases {
    var word = WordInProgress()
    for (index, character) in typed.enumerated() {
      let key = matcher.geometry.key(for: character)!
      let (fx, fy) = offsets[index % offsets.count]
      word.append(
        matcher.neighborhood(
          for: CGPoint(
            x: key.center.x + key.frame.width * fx,
            y: key.center.y + key.frame.height * fy))!)
    }
    #expect(
      matcher.literal(for: word.neighborhoods) == typed,
      "the offsets moved \(typed) onto different keys")
    #expect(predictor.commit(for: word) == .correction(intended), "\(typed) off centre")
  }
}

/// **The taps can say two words.** `isnthere` is `is there` with the space struck as an
/// `n`, and reading it that way is what item 3 asked for. SPEC.md A.34.
@Test func theTapsCanSayTwoWords() {
  let matcher = makeMatcher()
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("isnthere", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  #expect(Predictor(matcher: matcher).commit(for: word) == .correction("is there"))

  // And it is a reading of the taps rather than an edit bolted onto one: every tap is
  // accounted for, none is invented, and the boundary rule that refuses to buy an edit
  // therefore lets it through untouched.
  let best = matcher.readings(for: word.neighborhoods).first
  #expect(best?.text == "is there")
  #expect(best?.edits == 0)
}

/// **A tap that is not next to the space bar cannot become one**, which is the property
/// that makes `together` → `to get her` impossible rather than merely unlikely.
///
/// The search has a transition shaped exactly like a free space inserted anywhere — an
/// omission follows a trie edge without consuming a tap and without ever reading a
/// neighbourhood — so this is a design choice held in place by a test rather than a
/// consequence of the algorithm. If someone builds the split on that transition instead,
/// this is what fails. SPEC.md A.34.
@Test func aTapAwayFromTheSpaceBarCannotSplit() {
  let matcher = makeMatcher()

  // Row 1 is `asdfghjkl`, two rows above the space bar, so its 3x3 block cannot reach it.
  for letter in "asdfghjkl" {
    let key = matcher.geometry.key(for: letter)!
    let neighborhood = matcher.neighborhood(for: key.center)!
    #expect(neighborhood.cost(of: " ") == nil, "\(letter) can be read as a space")
  }
  // Row 2 is `zxcvbnm`, directly above it, and every one of them can be.
  for letter in "zxcvbnm" {
    let key = matcher.geometry.key(for: letter)!
    let neighborhood = matcher.neighborhood(for: key.center)!
    #expect(neighborhood.cost(of: " ") != nil, "\(letter) cannot be read as a space")
  }

  // So the word that would have to split at a row-1 tap does not split at all, however
  // cheap the two halves are on their own.
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("together", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  #expect(matcher.splits(for: word.neighborhoods).isEmpty)
  #expect(!matcher.readings(for: word.neighborhoods).contains { $0.text.contains(" ") })
}

/// **A split re-reads exactly one tap: the one that becomes the space.** Every other tap
/// keeps the letter it landed on.
///
/// A split is already one supposition about the typing. A reading that also letters its way
/// to two words is supposing twice, and it is not a hypothetical: `jonah` at dead centre
/// reaches `ho ah` by moving one tap from `j` to `h`, a real cost of 1.0 that still lands
/// inside a five-tap slack of 2.5. It was committing before the halves had to be literal.
/// SPEC.md A.34.
@Test func aSplitReadsEveryOtherTapLiterally() {
  let matcher = makeMatcher()
  var word = WordInProgress()
  for neighborhood in neighborhoods(perfectTaps("jonah", matcher.geometry), matcher) {
    word.append(neighborhood)
  }
  // The premise: `n` is row 2, so this word does have a tap that could carry a space, and
  // the test would pass vacuously if it did not.
  #expect(word.neighborhoods[2].cost(of: " ") != nil)
  #expect(!matcher.readings(for: word.neighborhoods).contains { $0.text.contains(" ") })
  #expect(Predictor(matcher: matcher).commit(for: word) == .literal("jonah"))
}

/// Splits are computed on every keystroke, so they are inside invariant I11 with everything
/// else. A split point costs two lexicon lookups rather than two searches, which is why this
/// stays in the same range as `matchingAWordStaysFastOnTheRealLexicon` even though a long
/// word offers several of them.
@Test func readingAWordWithItsSplitsStaysFast() {
  let matcher = makeMatcher()
  let taps = neighborhoods(perfectTaps("constellation", matcher.geometry), matcher)

  let start = ContinuousClock.now
  for _ in 0..<50 { _ = matcher.readings(for: taps) }
  let perMatch = (ContinuousClock.now - start) / 50
  #expect(perMatch < .milliseconds(50), "a reading took \(perMatch)")
}
