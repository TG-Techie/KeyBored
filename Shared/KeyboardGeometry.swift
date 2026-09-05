// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md, Appendix A — the measured stock proportions every number here comes from,
//   and the tests in KeyBoredTests that check this file against them.

import CoreGraphics

/// Which set of characters the keys are currently producing. Shift is deliberately
/// *not* a plane: shifted and unshifted letters occupy identical geometry and must
/// share their constellations, so shift is a modifier and the plane is unchanged.
public enum Plane: Sendable, Equatable {
  case letters
  case numbers
  case symbols
}

/// A key's identity, independent of what it currently produces. Row 0 is the top
/// letter row; `index` counts from the left within that row.
public struct KeyID: Hashable, Sendable {
  public let row: Int
  public let index: Int

  public init(row: Int, index: Int) {
    self.row = row
    self.index = index
  }
}

/// What a key does when it is struck. Only `.letter` keys take part in matching;
/// everything else is a command, resolved before the matcher is ever consulted.
public enum KeyRole: Equatable, Sendable {
  case letter(Character)
  case shift
  case delete
  case space
  case newline
  case plane(Plane)
  case nextKeyboard
}

/// One key, with the role it plays and the frame it occupies in keyboard coordinates.
public struct Key: Sendable {
  public let id: KeyID
  public let role: KeyRole
  public let frame: CGRect

  public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

  /// The character this key produces, or `nil` for command keys. Reads better at
  /// call sites than unwrapping `role` every time.
  public var letter: Character? {
    if case .letter(let c) = role { return c }
    return nil
  }
}

/// The measured stock proportions, kept in one place and named, so that the numbers
/// in SPEC.md Appendix A and the numbers the keyboard draws with cannot drift apart.
///
/// Horizontal values are fractions of the keyboard's width, because the stock
/// keyboard's columns scale with the screen. Vertical values are in points, because
/// its rows do not — a taller phone gets the same 45pt keys, not taller ones.
///
/// All of these came off a screenshot rather than a device. The proportions are
/// trustworthy; the absolute point values still want checking against a simulator.
public enum StockMetrics {
  /// 1290px reference width, so every fraction below is `measuredPixels / 1290`.
  public static let referenceWidthPx: CGFloat = 1290

  public static let sideMarginFraction: CGFloat = 20 / referenceWidthPx
  public static let columnGapFraction: CGFloat = 18 / referenceWidthPx

  /// Widths of the keys that are not plain letters, as fractions of the width.
  public static let shiftWidthFraction: CGFloat = 144 / referenceWidthPx
  public static let deleteWidthFraction: CGFloat = 145 / referenceWidthPx
  public static let planeKeyWidthFraction: CGFloat = 299 / referenceWidthPx
  public static let returnWidthFraction: CGFloat = 300 / referenceWidthPx

  /// Vertical metrics, in points: measured pixels divided by the reference @3x scale.
  public static let rowHeight: CGFloat = 135 / 3
  public static let rowGap: CGFloat = 33 / 3
  public static let suggestionBarHeight: CGFloat = 104 / 3

  /// The row below `return` carrying the globe key. On the stock keyboard this is
  /// where the emoji and dictation buttons sit; a custom keyboard puts the required
  /// next-keyboard button there, which keeps rows 1 through 4 exactly where stock
  /// puts them.
  public static let bottomRowHeight: CGFloat = 47

  /// Total height the extension asks for, excluding the home-indicator safe area.
  public static var totalHeight: CGFloat {
    suggestionBarHeight + 4 * rowHeight + 3 * rowGap + bottomRowHeight
  }
}

/// Every key's frame for one width and one plane. This is the single source of truth
/// for both hit-testing and ideal key positions: computing them separately is how a
/// keyboard ends up predicting against a layout it is no longer drawing.
public struct KeyboardGeometry: Sendable {
  public let width: CGFloat
  public let plane: Plane
  public let keys: [Key]

  /// Centre-to-centre spacing, the unit distances are normalized by. Scores expressed
  /// in these units mean the same thing on every screen size, so a threshold tuned on
  /// one device holds on the next.
  public let columnPitch: CGFloat
  public let rowPitch: CGFloat

  /// The letter rows, in order, as the letters they produce unshifted.
  public static let letterRows: [[Character]] = [
    Array("qwertyuiop"),
    Array("asdfghjkl"),
    Array("zxcvbnm"),
  ]

  public init(width: CGFloat, plane: Plane = .letters) {
    self.width = width
    self.plane = plane

    let margin = width * StockMetrics.sideMarginFraction
    let gap = width * StockMetrics.columnGapFraction
    // The top row's ten keys divide whatever the margins and gaps leave. Deriving the
    // key width from the remainder rather than from its own fraction is what makes the
    // row land exactly on both margins instead of a pixel short.
    let keyWidth = (width - 2 * margin - 9 * gap) / 10

    self.columnPitch = keyWidth + gap
    self.rowPitch = StockMetrics.rowHeight + StockMetrics.rowGap

    var keys: [Key] = []
    let rowHeight = StockMetrics.rowHeight
    let firstRowTop = StockMetrics.suggestionBarHeight

    func rowTop(_ row: Int) -> CGFloat {
      firstRowTop + CGFloat(row) * (rowHeight + StockMetrics.rowGap)
    }

    let glyphRows = Self.glyphRows(for: plane)

    // Rows 0 and 1: plain keys, centred. Row 1 lands half a column pitch in from row 0,
    // which is what the reference measures (first key at x = 84px against row 0's 20px,
    // and half the 126px pitch is 63).
    for row in 0..<2 {
      let glyphs = glyphRows[row]
      let span = CGFloat(glyphs.count) * keyWidth + CGFloat(glyphs.count - 1) * gap
      var x = (width - span) / 2
      for (i, glyph) in glyphs.enumerated() {
        keys.append(
          Key(
            id: KeyID(row: row, index: i),
            role: .letter(glyph),
            frame: CGRect(x: x, y: rowTop(row), width: keyWidth, height: rowHeight),
          ))
        x += keyWidth + gap
      }
    }

    // Row 2: shift, the row's glyphs centred, delete. The glyphs are centred on their
    // own rather than packed against shift, which is what puts them on the same column
    // pitch as the rows above.
    let row2Glyphs = glyphRows[2]
    let shiftWidth = width * StockMetrics.shiftWidthFraction
    let deleteWidth = width * StockMetrics.deleteWidthFraction
    keys.append(
      Key(
        id: KeyID(row: 2, index: 0),
        role: plane == .letters ? .shift : .plane(plane == .numbers ? .symbols : .numbers),
        frame: CGRect(x: margin, y: rowTop(2), width: shiftWidth, height: rowHeight),
      ))
    let row2Span = CGFloat(row2Glyphs.count) * keyWidth + CGFloat(row2Glyphs.count - 1) * gap
    var x2 = (width - row2Span) / 2
    for (i, glyph) in row2Glyphs.enumerated() {
      keys.append(
        Key(
          id: KeyID(row: 2, index: i + 1),
          role: .letter(glyph),
          frame: CGRect(x: x2, y: rowTop(2), width: keyWidth, height: rowHeight),
        ))
      x2 += keyWidth + gap
    }
    keys.append(
      Key(
        id: KeyID(row: 2, index: row2Glyphs.count + 1),
        role: .delete,
        frame: CGRect(
          x: width - margin - deleteWidth, y: rowTop(2), width: deleteWidth, height: rowHeight),
      ))

    // Row 3: plane switch, space, return. Space takes what is left, which reproduces
    // the measured 615px to within a pixel.
    let planeWidth = width * StockMetrics.planeKeyWidthFraction
    let returnWidth = width * StockMetrics.returnWidthFraction
    let spaceWidth = width - 2 * margin - planeWidth - returnWidth - 2 * gap
    keys.append(
      Key(
        id: KeyID(row: 3, index: 0),
        role: .plane(plane == .letters ? .numbers : .letters),
        frame: CGRect(x: margin, y: rowTop(3), width: planeWidth, height: rowHeight),
      ))
    keys.append(
      Key(
        id: KeyID(row: 3, index: 1),
        role: .space,
        frame: CGRect(
          x: margin + planeWidth + gap, y: rowTop(3), width: spaceWidth, height: rowHeight),
      ))
    keys.append(
      Key(
        id: KeyID(row: 3, index: 2),
        role: .newline,
        frame: CGRect(
          x: width - margin - returnWidth, y: rowTop(3), width: returnWidth, height: rowHeight),
      ))

    // Row 4: the globe, in the slot where stock puts the emoji button.
    keys.append(
      Key(
        id: KeyID(row: 4, index: 0),
        role: .nextKeyboard,
        frame: CGRect(
          x: margin, y: rowTop(4), width: shiftWidth, height: StockMetrics.bottomRowHeight),
      ))

    self.keys = keys
  }

  static func glyphRows(for plane: Plane) -> [[Character]] {
    switch plane {
    case .letters:
      return letterRows
    case .numbers:
      return [Array("1234567890"), Array("-/:;()$&@"), Array(".,?!'")]
    case .symbols:
      return [Array("[]{}#%^*+="), Array("_\\|~<>€£¥"), Array(".,?!'")]
    }
  }

  public var height: CGFloat { StockMetrics.totalHeight }

  public func key(_ id: KeyID) -> Key? { keys.first { $0.id == id } }

  /// The key a touch lands on, or `nil` if it landed outside every key. Hit-testing
  /// is by frame first so that the gaps behave the way the stock keyboard's do, and
  /// only falls back to nearest-centre inside the keyboard's own bounds.
  public func hitTest(_ point: CGPoint) -> Key? {
    if let direct = keys.first(where: { $0.frame.contains(point) }) { return direct }
    guard point.y >= StockMetrics.suggestionBarHeight, point.y <= height else { return nil }
    return keys.min {
      Self.squaredDistance($0.center, point) < Self.squaredDistance($1.center, point)
    }
  }

  static func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return dx * dx + dy * dy
  }

  /// Manhattan distance in normalized key units: the metric the whole matcher runs on.
  /// Normalizing by pitch is what lets a score computed on one device be compared with
  /// a threshold tuned on another.
  public func normalizedManhattan(from point: CGPoint, to key: Key) -> Double {
    let dx = abs(point.x - key.center.x) / columnPitch
    let dy = abs(point.y - key.center.y) / rowPitch
    return Double(dx + dy)
  }

  /// Every letter key on this geometry, in row-major order.
  public var letterKeys: [Key] { keys.filter { $0.letter != nil } }

  public func key(for character: Character) -> Key? {
    keys.first { $0.letter == character }
  }
}
