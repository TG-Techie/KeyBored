// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import CoreGraphics
import Testing
import UIKit

@testable import KeyBored

/// **The letter's baseline sits where stock's does, in both shift states.**
///
/// Reported by Jonah 2026-09-06 at 14:26 against 0.0.14: "The verticla oddaetnisnstillcalifhtlynoff".
/// Measured against stock in the same Contacts field on a 402pt simulator, ours sat 4px low
/// with a capital and 7px low with a minuscule, on all three letter rows. The cause is that
/// a label centres its line box and a line box is not where the ink is (SPEC.md 8.2), so the
/// placement moved when A.32 gave the two cases their own point sizes.
///
/// **It asserts the ink and not the frame**, and it uses `x` because `x` has no overshoot:
/// a round letter's ink runs a pixel past the baseline at both ends and would put a pixel of
/// slop into a measurement whose whole point is the last pixel. SPEC.md A.33.
@MainActor
@Test func theLetterSitsOnStocksBaselineInBothShiftStates() {
  let width: CGFloat = 402
  let geometry = KeyboardGeometry(width: width, plane: .letters)
  let view = KeyboardView(
    frame: CGRect(x: 0, y: 0, width: width, height: StockMetrics.totalHeight(forWidth: width)))
  view.configure(geometry: geometry, shift: .off, needsNextKeyboard: false)
  let cap = geometry.keys.first { $0.letter == "x" }!.frame

  /// The bottom of the letter's ink inside the cap, in points, or nil if nothing was drawn.
  func inkBottom() -> CGFloat? {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    let scale: CGFloat = 3
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
      view.layer.render(in: UIGraphicsGetCurrentContext()!)
    }
    guard let cg = image.cgImage else { return nil }
    let w = cg.width, h = cg.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(
      data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Inset well inside the corner radius, because the plate shows through the rounded
    // corners and the plate is the one thing on screen that is not the cap or the letter.
    let inset: CGFloat = 6
    let x0 = Int((cap.minX + inset) * scale), x1 = min(Int((cap.maxX - inset) * scale), w - 1)
    let y0 = Int((cap.minY + inset) * scale), y1 = min(Int((cap.maxY - inset) * scale), h - 1)
    func luminance(_ x: Int, _ y: Int) -> Int {
      let i = (y * w + x) * 4
      return (Int(pixels[i]) * 299 + Int(pixels[i + 1]) * 587 + Int(pixels[i + 2]) * 114) / 1000
    }
    // The cap's own colour, sampled just inside its top edge where no letter reaches. The
    // ink is whatever differs from it, which works in either appearance — the letter is
    // near-black on white in light and near-white on grey in dark.
    let capColor = luminance((x0 + x1) / 2, y0)
    var bottom: Int? = nil
    for y in y0...y1 {
      for x in x0...x1 where abs(luminance(x, y) - capColor) > 60 { bottom = y }
    }
    return bottom.map { CGFloat($0 + 1) / scale }
  }

  let target = cap.midY + StockMetrics.capBaselineBelowCenter

  guard let lower = inkBottom() else {
    Issue.record("no ink found on the unshifted cap")
    return
  }
  #expect(abs(lower - target) < 0.5, "the minuscule's baseline is \(lower), stock's is \(target)")

  view.setShift(.oneShot)
  guard let upper = inkBottom() else {
    Issue.record("no ink found on the shifted cap")
    return
  }
  #expect(abs(upper - target) < 0.5, "the capital's baseline is \(upper), stock's is \(target)")

  // And the two share it, which is the property stock has and the reason one constant is
  // enough: a capital and a minuscule on the same row sit on one line.
  #expect(abs(upper - lower) < 0.5, "the two shift states are on different baselines")
}
