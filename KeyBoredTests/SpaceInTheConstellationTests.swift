// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md Appendix A.20 — why the space bar is a point in the constellation, and why
//   adding it needed the cost function changed first.

import Testing
import UIKit

@testable import KeyBored

private let widths: [CGFloat] = [390, 402, 430, 440]

private func lettersGeometry(_ width: CGFloat) -> KeyboardGeometry {
  KeyboardGeometry(width: width, plane: .letters, hasGlobeKey: true)
}

/// **The change to the cost function does not move a single letter-to-letter score.**
///
/// This is the property the whole of stage one rests on. `normalizedManhattan` used to
/// divide every horizontal distance by one `columnPitch` and now divides by the key's own
/// width plus the gap. For a key of the standard letter width those are the same number,
/// so every constant in SPEC section 5 keeps the meaning it was fitted with and nothing
/// has to be re-tuned.
///
/// It is asserted rather than argued because the argument is only as good as the claim
/// that every letter key is the standard width, and that is a fact about the geometry that
/// a future change could quietly break. If this test ever fails by more than the tolerance
/// below, the tuning has moved and the correction quality Jonah reported at 02:31 on
/// 2026-09-06 is downstream of it.
///
/// **The tolerance is one ULP and it is not slack, it is a finding.** The bottom letter
/// row's keys are not built from `keyWidth`; they are built from
/// `(7 * keyWidth + 6 * gap - 6 * gap) / 7`, which is the same number by algebra and one
/// unit in the last place away from it in binary. So `z` through `m` move by about 4
/// parts in 10^16 and the other nineteen letters do not move at all. Nothing can be
/// ranked differently by that, but it is the difference between "identical" and
/// "identical to within a rounding of the last bit", and the second one is true.
@Test(arguments: widths)
func thePerKeyNormalizerIsIdentityForLetters(width: CGFloat) {
  let geometry = lettersGeometry(width)
  // The old `columnPitch`, reconstructed: one letter's width plus one gap.
  let pitch = geometry.letterKeys[0].frame.width + geometry.columnGap

  for key in geometry.letterKeys {
    for dx in stride(from: -60.0, through: 60.0, by: 7.5) {
      for dy in stride(from: -60.0, through: 60.0, by: 7.5) {
        let point = CGPoint(x: key.center.x + dx, y: key.center.y + dy)
        let before = Double(
          abs(point.x - key.center.x) / pitch
            + abs(point.y - key.center.y) / geometry.rowPitch)
        let after = geometry.normalizedManhattan(from: point, to: key)
        #expect(
          abs(after - before) <= 4 * .ulpOfOne * max(1, abs(before)),
          "\(key.letter!) at \(point) scores \(after) and used to score \(before)")
      }
    }
  }
}

/// The one ULP above has a cause and this is it, stated as a fact about the geometry so
/// that the tolerance in the test beside it is not mistaken for a fudge.
@Test(arguments: widths)
func everyLetterKeyIsTheSameWidthToWithinARoundingOfTheLastBit(width: CGFloat) {
  let geometry = lettersGeometry(width)
  let standard = geometry.letterKeys[0].frame.width
  for key in geometry.letterKeys {
    #expect(
      abs(key.frame.width - standard) <= 4 * .ulpOfOne * standard,
      "\(key.letter!) is \(key.frame.width) wide against the top row's \(standard)")
  }
}

/// The defect that made the space bar look as though it were not there.
///
/// At 430pt the space bar is 615px wide against a letter's 109, so its centre is a long
/// way from a tap near either end of it. Under the old normalizer a tap 13px inside the
/// space bar's own left edge scored 2.32 to space and 1.32 to `x` one row up: **space lost
/// inside itself**, and adding it to the candidate set without fixing that would have
/// changed nothing anybody could see.
@Test(arguments: widths)
func spaceWinsInsideItsOwnCap(width: CGFloat) {
  let geometry = lettersGeometry(width)
  let matcher = ConstellationMatcher(geometry: geometry, lexicon: Lexicon(entries: []))
  let space = geometry.keys.first { $0.role == .space }!

  for fraction in [0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98] {
    let point = CGPoint(
      x: space.frame.minX + space.frame.width * fraction, y: space.frame.midY)
    let neighborhood = matcher.neighborhood(for: point)
    let read = neighborhood.map { String($0.literal) } ?? "nothing"
    #expect(
      neighborhood?.literal == " ",
      "a tap \(Int(fraction * 100))% along the space bar reads as \(read)")
  }
}

/// A tap on the space bar is scored, and it is scored against the row above it.
///
/// It used to return nothing at all: `neighborhood(for:)` opened by requiring a letter, so
/// a finger that landed on the space bar had no constellation and the word was committed
/// on the strength of which cap was struck.
@Test func aTapOnTheSpaceBarIsScoredAgainstTheRowAboveIt() {
  let geometry = lettersGeometry(430)
  let matcher = ConstellationMatcher(geometry: geometry, lexicon: Lexicon(entries: []))
  let space = geometry.keys.first { $0.role == .space }!
  let point = CGPoint(x: space.frame.midX, y: space.frame.midY)

  let neighborhood = matcher.neighborhood(for: point)
  #expect(neighborhood != nil)
  #expect(neighborhood?.literal == " ")
  #expect(
    neighborhood?.letters.contains(where: { $0.isLetter }) == true,
    "the space bar's neighbourhood has no letters in it, so nothing can be recovered")
}

/// The two halves of Jonah's rule, as behaviour rather than as scores.
///
/// A finger that lands on the space bar but nearer a letter types the letter, and a finger
/// that lands low on a letter but nearer the space bar ends the word. Before this, the cap
/// decided both and a `b` struck slightly low committed the word unrecoverably.
@MainActor
@Test func theNearestScoredCharacterDecidesAndNotTheCapStruck() {
  let geometry = lettersGeometry(430)

  let space = geometry.keys.first { $0.role == .space }!
  let b = geometry.key(for: "b")!

  // A hair inside the space bar's top edge, directly under `b`: still a space.
  let justInsideSpace = CGPoint(x: b.center.x, y: space.frame.minY + 1)
  // A hair inside `b`'s bottom edge: still a `b`.
  let justInsideB = CGPoint(x: b.center.x, y: b.frame.maxY - 1)

  let matcher = ConstellationMatcher(geometry: geometry, lexicon: Lexicon(entries: []))
  #expect(matcher.neighborhood(for: justInsideSpace)?.literal == " ")
  #expect(matcher.neighborhood(for: justInsideB)?.literal == "b")
}

/// Non-character keys are out of the constellation and stay on the canvas.
///
/// Excluding shift, delete, the plane key and the globe from *matching* must never turn
/// into excluding them from the touch layer, which is how the dead zones in those columns
/// would come back. They are two different questions about the same key.
@Test func onlyKeysThatEnterACharacterAreScored() {
  let geometry = lettersGeometry(430)
  let scored = Set(geometry.scoredKeys.map(\.id))

  for key in geometry.keys {
    switch key.role {
    case .letter, .space:
      #expect(scored.contains(key.id), "\(key.role) should be a point in the constellation")
    case .shift, .delete, .plane, .nextKeyboard, .newline, .punctuation:
      #expect(!scored.contains(key.id), "\(key.role) enters no character and must not be scored")
    }
    // Every key, scored or not, is still a key the keyboard can be struck on.
    #expect(geometry.hitTest(key.center)?.id == key.id)
  }
}
