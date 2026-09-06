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

  /// A key that inserts a character and takes no part in matching.
  ///
  /// The distinction is the matcher's, not the drawing's: a `.punctuation` cap looks
  /// exactly like a letter cap and is struck the same way, but its position is not a
  /// point in any word's constellation, so putting one on the letters plane must not
  /// change what the matcher scores against. Stock's address-field period key is the
  /// only one of these so far — SPEC.md Appendix A.14.
  case punctuation(Character)
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

  /// The character this key inserts, whether or not the matcher scores it. `letter` is
  /// the one to reach for when the question is about matching; this one when the
  /// question is about what the cap draws or what goes into the document.
  public var character: Character? {
    switch role {
    case .letter(let c), .punctuation(let c): return c
    default: return nil
    }
  }
}

/// The measured stock proportions, kept in one place and named, so that the numbers
/// in SPEC.md Appendix A and the numbers the keyboard draws with cannot drift apart.
///
/// Horizontal values are fractions of the keyboard's width, because the stock keyboard's
/// columns scale with the screen. Vertical values are in points, because its rows do not
/// scale continuously — but they are not one number either: the cap height takes one of
/// two values depending on the phone, which is why `rowHeight` is a function. See it for
/// the four devices that were measured.
///
/// The horizontal fractions came off a screenshot of a 430pt phone and were checked
/// against stock on 390pt, 402pt and 440pt simulators on 2026-09-05: every one lands
/// within about a pixel and a half, which is the width of the antialiased cap edge the
/// threshold does not count.
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

  /// The bottom row of an address field's keyboard, which stock divides differently.
  ///
  /// Measured 2026-09-06 on stock in Safari's address field, 1206px wide at 3x, against
  /// this keyboard in the same field minutes apart: stock puts a 100px period key between
  /// a 545px space bar and a 190px return key, where this keyboard had a 575px space bar
  /// and a 280px return. The two fractions below are those two widths carried to the
  /// 1290px reference; the space bar takes what is left, the same way it does without the
  /// period key. SPEC.md Appendix A.14.
  public static let periodKeyWidthFraction: CGFloat = 107 / referenceWidthPx
  public static let returnWidthWithPeriodFraction: CGFloat = 203 / referenceWidthPx

  /// Vertical metrics, in points: measured pixels divided by the reference @3x scale.
  ///
  /// The gap and the strip are the same on every phone measured. The cap height is not,
  /// and that is the one place where "vertical values are in points because stock's rows
  /// do not scale" turned out to be only half true.
  public static let rowGap: CGFloat = 33 / 3

  /// **Three numbers, not one, and conflating two of them shipped a defect.**
  ///
  /// The band above the first key row is measured from the top of the *plate* — the
  /// rounded container a person sees — and a custom keyboard does not own all of it. iOS
  /// draws a band of its own above the input view the extension is given, so the strip
  /// this keyboard lays out inside its own view is the stock band minus that. Writing the
  /// plate-relative figure and the view-relative figure as one constant counts the
  /// system's band twice, and that is exactly what 0.0.5 shipped: on Jonah's phone its
  /// first key row sat 51px below stock's, measured off a stock-and-BoreKey screenshot
  /// pair in the same iMessage field on 2026-09-06, anchored on the globe strip iOS draws
  /// below both. Everything else on that pair was identical — caps 109px wide on 18px
  /// gaps at 20px margins, cap height 135, row gap 33, row pitch 168, space 615 against
  /// stock's 616, return 300 against 300.
  ///
  /// Recorded because the wrong answer is re-derivable from the right measurement: an
  /// earlier note here read the 51px as a defect that a previous commit had *fixed*,
  /// when that commit is what introduced it by changing this constant from 104 to 156 for
  /// both uses at once. SPEC.md Appendix A.17.

  /// What stock reserves above its first key row, from the top of the plate: 156px at 3x.
  ///
  /// Measured 2026-09-05 in a Contacts search field on three simulators — 390pt, 402pt
  /// and 440pt wide — where it came out at exactly 156 on all three. **This is a
  /// description of stock, not a layout value**: nothing positions a key against it,
  /// because this keyboard's own view does not begin at the top of the plate.
  public static let stockPlateToFirstRow: CGFloat = 156 / 3

  /// The band iOS draws above a custom keyboard's input view, which the extension neither
  /// draws in nor is given: 52px at 3x.
  ///
  /// Measured on the 0.0.5 pair above. That build laid its first row out 156px below the
  /// top of its own view and the row landed 206px below the top of the plate, so the band
  /// between the two is 50px, and 52 is where the arithmetic below puts it. The two agree
  /// to within the pixel or so that thresholding a rounded corner costs.
  public static let systemBandAboveInputView: CGFloat = stockPlateToFirstRow - suggestionBarHeight

  /// The strip this keyboard draws above its own first key row, inside its own input
  /// view, and the offset row 0 is laid out at: 104px at 3x.
  ///
  /// This is the one of the three that positions anything.
  public static let suggestionBarHeight: CGFloat = 104 / 3

  /// **The cap height depends on the phone, and there are two of them.**
  ///
  /// Measured 2026-09-05, stock keyboard, Contacts search field, dark, @3x:
  ///
  ///     iPhone 17e       390 pt wide    cap 129 px    row pitch 162 px
  ///     iPhone 17 Pro    402 pt wide    cap 129 px    row pitch 162 px
  ///     iPhone 17 Pro Max 440 pt wide   cap 135 px    row pitch 168 px
  ///     Jonah's phone    430 pt wide    cap 135 px    row pitch 168 px
  ///
  /// The last row is from the screenshot pair in the repository's own notes rather than
  /// from a simulator, and it is the reason this matters: the 135 that used to be the
  /// only value here was measured on a 430pt phone and is right there. It is 6px too tall
  /// on everything smaller, which is every device this project can put side by side with
  /// stock.
  ///
  /// **The boundary is a guess and the two values are not.** Nothing was measured between
  /// 402 and 430. 414 is where it sits because that is the width of the older Plus and
  /// Max phones, which is the same class boundary Apple has drawn before — but a device
  /// between 402 and 414, or between 414 and 430, would settle it and none was tried.
  public static let largePhoneWidth: CGFloat = 414

  public static func rowHeight(forWidth width: CGFloat) -> CGFloat {
    width >= largePhoneWidth ? 135 / 3 : 129 / 3
  }

  /// The height to ask for, which is stock's plate **less thirteen pixels iOS will not
  /// give a custom keyboard.**
  ///
  /// Measured on a 402pt simulator, 2026-09-05, with both keyboards in the same Contacts
  /// search field: stock's plate runs y 1617-2410 and the bottom of a custom keyboard's
  /// input view is pinned at 2397 whatever height it asks for — 765 put its top at 1632,
  /// 793 put its top at 1604, and both ended at 2397. iOS gives its own globe and
  /// dictation strip those last 13px; stock's plate simply extends over them.
  ///
  /// So a keyboard as tall as stock's plate sits 13px high, every row 13px above stock's
  /// in a side-by-side, which is what a whole afternoon of otherwise-identical
  /// measurements kept showing. Asking for 13px less puts the four key rows exactly on
  /// stock's and gives up the bottom 13px of plate instead, which is the right trade:
  /// the rows are where the fingers go, and the band underneath is dark either way.
  ///
  /// **It is not the same on a phone of another size**, which the note here used to say
  /// had not been checked. It has been now, and it is two values rather than one:
  ///
  ///     iPhone 17 Pro      402 pt wide    13 px
  ///     iPhone 17 Pro Max  440 pt wide     7 px
  ///
  /// Measured 2026-09-06 the only way this quantity can be, which is by looking at where
  /// the rows land: both keyboards in the same Contacts search field, dark, our four cap
  /// bands against stock's four. At 402pt they were already on top of each other, tops at
  /// 1773, 1935, 2097 and 2259 in both. At 440pt every one of ours sat exactly 6px below
  /// stock's — 1995 against 1989, 2163 against 2157, 2331 against 2325, 2499 against
  /// 2493 — with identical cap heights of 135, an identical pitch of 168, an identical
  /// plate top and iOS's globe glyph in an identical place. A uniform shift with
  /// everything else equal is a height.
  ///
  /// **The sign is the part to get right, and it is the opposite of the intuition.** The
  /// input view's bottom is pinned wherever it lands and the rows are laid out from its
  /// top, so asking for *less* height moves every row *down*. Ours were already 6px low,
  /// so the inset had to shrink rather than grow. Asking for 6px less first — the reading
  /// that felt right — put them 12px low, which is how this is known rather than assumed.
  /// With 7px the four bands read 1989, 2157, 2325 and 2493: stock's, exactly.
  ///
  /// Reported before it was found, on 0.0.7, as "still ever so shorter (i think its
  /// missing some padding along the bottom)" — which is what it looks like from the
  /// front, because height we do not give up is padding the last row eats.
  /// SPEC.md Appendix A.18.
  ///
  /// **The boundary is `largePhoneWidth` and it is inherited, not measured.** It is the
  /// same 414 that `StockMetrics.rowHeight(forWidth:)` uses and carries the same caveat:
  /// nothing has been measured between 402 and 430, and Jonah's phone at 430 is assumed
  /// to behave as the 440 simulator does because both are above the line. The 6px is a
  /// measurement; where it starts applying is a guess.
  public static func systemBottomInset(forWidth width: CGFloat) -> CGFloat {
    width >= largePhoneWidth ? 7 / 3 : 13 / 3
  }

  public static func declaredHeight(forWidth width: CGFloat) -> CGFloat {
    totalHeight(forWidth: width) - systemBottomInset(forWidth: width)
  }

  /// The bottom row's `123` and the slot beside it, which on stock is the emoji key.
  ///
  /// Their sum plus one gap is `planeKeyWidthFraction`: 140 + 18 + 141 = 299. So the
  /// bottom row is the same row either way, and the globe key — when the system asks
  /// for one — takes stock's emoji slot rather than a row of its own.
  public static let splitPlaneKeyWidthFraction: CGFloat = 140 / referenceWidthPx
  public static let globeKeyWidthFraction: CGFloat = 141 / referenceWidthPx

  /// What stock leaves below the last row: 22px at 3x, and nothing else.
  ///
  /// This was `bottomRowHeight = 47`, a whole row reserved for the globe key. There is
  /// no such row. iOS draws its own globe and dictation strip *below* a custom
  /// keyboard's input view, and stock's emoji key sits inside the bottom row. When
  /// `needsInputModeSwitchKey` is false the reserved row was simply empty, and the
  /// keyboard stood 40 points taller than stock with a band of bare plate under it —
  /// photographed on a phone 2026-09-05 and measured at 142px against stock's 22px.
  /// SPEC.md section 11.4.
  public static let bottomPadding: CGFloat = 22 / 3

  /// The two rules in the candidate bar, measured off a stock keyboard in a Contacts
  /// search field on a simulator 2026-09-05: 3px wide and 72px tall at 3x, `#323234`,
  /// at exactly a third and two thirds of the width, and drawn whether or not the bar
  /// has anything in it.
  ///
  /// **Their vertical position cannot be matched exactly and this is the closest we can
  /// get.** Stock's rules run from 117px to 46px above the top of the first key row. A
  /// custom keyboard's input view starts 104px above that row and iOS draws its own
  /// backdrop in the 48px above it, so the top 13px of stock's rule is in a band this
  /// keyboard does not own. Centring in the strip we do own puts them 7px low.
  public static let barDividerWidth: CGFloat = 3 / 3
  public static let barDividerHeight: CGFloat = 72 / 3

  /// The corner radius of a key cap: 21px at 3x, measured by walking a cap's top edge
  /// until it reaches full width. The keyboard drew 5pt before that was measured.
  public static let capCornerRadius: CGFloat = 21 / 3

  /// Total height the extension asks for, excluding the home-indicator safe area.
  ///
  /// This is the height of the input view, so it counts `suggestionBarHeight` and not
  /// `stockPlateToFirstRow`: the band iOS draws above the view is not the extension's to
  /// ask for. Stock's whole plate on a 402pt phone is 156 + 4×129 + 3×33 + 22 = 793px and
  /// really does run from 1617 to 2410 in a 2622px capture, which is that same sum with
  /// the system's band included — the plate, not the view.
  public static func totalHeight(forWidth width: CGFloat) -> CGFloat {
    suggestionBarHeight + 4 * rowHeight(forWidth: width) + 3 * rowGap + bottomPadding
  }
}

/// Every key's frame for one width and one plane. This is the single source of truth
/// for both hit-testing and ideal key positions: computing them separately is how a
/// keyboard ends up predicting against a layout it is no longer drawing.
public struct KeyboardGeometry: Sendable {
  public let width: CGFloat
  public let plane: Plane

  /// Whether the layout carries the next-keyboard globe.
  ///
  /// Part of the geometry rather than of the drawing, because it changes where the
  /// space bar starts. It comes from `UIInputViewController.needsInputModeSwitchKey`,
  /// which is the system's answer to "does this installation need a way off this
  /// keyboard" and is false when iOS provides its own switcher.
  public let hasGlobeKey: Bool

  /// Whether the bottom row carries stock's dedicated period key.
  ///
  /// Like `hasGlobeKey`, this belongs to the geometry rather than to the drawing, because
  /// it moves the space bar and the return key. It is the letters plane only: stock's
  /// number and symbol planes in the same field have no period key in the bottom row and
  /// the full-width return, which was measured in the same sitting. SPEC.md Appendix A.14.
  public let hasPeriodKey: Bool
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

  public init(
    width: CGFloat,
    plane: Plane = .letters,
    hasGlobeKey: Bool = false,
    hasPeriodKey: Bool = false,
  ) {
    self.hasGlobeKey = hasGlobeKey
    // Asking for the key on a plane that does not draw one is not an error; the plane
    // decides, so the two facts stay independent at the call site.
    let drawsPeriodKey = hasPeriodKey && plane == .letters
    self.hasPeriodKey = drawsPeriodKey
    self.width = width
    self.plane = plane

    let margin = width * StockMetrics.sideMarginFraction
    let gap = width * StockMetrics.columnGapFraction
    // The top row's ten keys divide whatever the margins and gaps leave. Deriving the
    // key width from the remainder rather than from its own fraction is what makes the
    // row land exactly on both margins instead of a pixel short.
    let keyWidth = (width - 2 * margin - 9 * gap) / 10

    self.columnPitch = keyWidth + gap
    self.rowPitch = StockMetrics.rowHeight(forWidth: width) + StockMetrics.rowGap

    var keys: [Key] = []
    let rowHeight = StockMetrics.rowHeight(forWidth: width)
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
    //
    // The group always occupies the same span — seven letter keys and the six gaps
    // between them — whatever the plane puts inside it. On the letters plane that is
    // `z`…`m` at the column pitch; on the number and symbol planes the identical span is
    // divided into five wider punctuation caps instead. Measured off stock captures on a
    // 1206px simulator, 2026-09-05: the group runs x 197-1008 on all three planes, with
    // 101px caps on letters against 148px on the other two. SPEC.md Appendix A.
    let row2Glyphs = glyphRows[2]
    let shiftWidth = width * StockMetrics.shiftWidthFraction
    let deleteWidth = width * StockMetrics.deleteWidthFraction
    keys.append(
      Key(
        id: KeyID(row: 2, index: 0),
        role: plane == .letters ? .shift : .plane(plane == .numbers ? .symbols : .numbers),
        frame: CGRect(x: margin, y: rowTop(2), width: shiftWidth, height: rowHeight),
      ))
    let row2Span = 7 * keyWidth + 6 * gap
    let row2KeyWidth =
      (row2Span - CGFloat(row2Glyphs.count - 1) * gap) / CGFloat(row2Glyphs.count)
    var x2 = (width - row2Span) / 2
    for (i, glyph) in row2Glyphs.enumerated() {
      keys.append(
        Key(
          id: KeyID(row: 2, index: i + 1),
          role: .letter(glyph),
          frame: CGRect(x: x2, y: rowTop(2), width: row2KeyWidth, height: rowHeight),
        ))
      x2 += row2KeyWidth + gap
    }
    keys.append(
      Key(
        id: KeyID(row: 2, index: row2Glyphs.count + 1),
        role: .delete,
        frame: CGRect(
          x: width - margin - deleteWidth, y: rowTop(2), width: deleteWidth, height: rowHeight),
      ))

    // Row 3: plane switch, optionally the globe, space, return. Space takes what is
    // left, which reproduces the measured 615px to within a pixel either way — the
    // globe occupies stock's emoji slot, and the two of them plus a gap are exactly as
    // wide as the undivided `123`.
    let planeWidth =
      hasGlobeKey
      ? width * StockMetrics.splitPlaneKeyWidthFraction
      : width * StockMetrics.planeKeyWidthFraction
    let globeWidth = hasGlobeKey ? width * StockMetrics.globeKeyWidthFraction : 0
    // An address field spends part of the return key and part of the space bar on a
    // period key: stock narrows the return from 300/1290 to 203/1290 and puts a 107/1290
    // cap in the gap that opens up.
    let returnWidth =
      width
      * (drawsPeriodKey
        ? StockMetrics.returnWidthWithPeriodFraction : StockMetrics.returnWidthFraction)
    let periodWidth = drawsPeriodKey ? width * StockMetrics.periodKeyWidthFraction : 0
    let leadingWidth = hasGlobeKey ? planeWidth + gap + globeWidth : planeWidth
    let trailingWidth = drawsPeriodKey ? periodWidth + gap + returnWidth : returnWidth
    let spaceWidth = width - 2 * margin - leadingWidth - trailingWidth - 2 * gap
    keys.append(
      Key(
        id: KeyID(row: 3, index: 0),
        role: .plane(plane == .letters ? .numbers : .letters),
        frame: CGRect(x: margin, y: rowTop(3), width: planeWidth, height: rowHeight),
      ))
    if hasGlobeKey {
      keys.append(
        Key(
          id: KeyID(row: 3, index: 1),
          role: .nextKeyboard,
          frame: CGRect(
            x: margin + planeWidth + gap, y: rowTop(3), width: globeWidth, height: rowHeight),
        ))
    }
    keys.append(
      Key(
        id: KeyID(row: 3, index: 2),
        role: .space,
        frame: CGRect(
          x: margin + leadingWidth + gap, y: rowTop(3), width: spaceWidth, height: rowHeight),
      ))
    if drawsPeriodKey {
      keys.append(
        Key(
          id: KeyID(row: 3, index: 3),
          role: .punctuation("."),
          frame: CGRect(
            x: width - margin - returnWidth - gap - periodWidth, y: rowTop(3),
            width: periodWidth, height: rowHeight),
        ))
    }
    keys.append(
      Key(
        id: KeyID(row: 3, index: 4),
        role: .newline,
        frame: CGRect(
          x: width - margin - returnWidth, y: rowTop(3), width: returnWidth, height: rowHeight),
      ))

    self.keys = keys
  }

  /// The glyph on each cap, plane by plane.
  ///
  /// The two quote caps carry the curly characters, `”` and `’`, because that is what
  /// stock draws — its cap is a pair of slanted wedges where a straight `"` is two
  /// vertical bars, and the difference is plain in a screenshot at 3x. The character on
  /// the cap is also the character the key is identified by, but it is **not** always the
  /// character inserted: `SmartPunctuation` picks the opening or the closing form from
  /// what is in front of the cursor, the way stock does.
  static func glyphRows(for plane: Plane) -> [[Character]] {
    switch plane {
    case .letters:
      return letterRows
    case .numbers:
      return [Array("1234567890"), Array("-/:;()$&@”"), Array(".,?!’")]
    // The bullet closing the symbol plane's second row is easy to miss and stock has it;
    // without it the row is nine keys and lands half a column pitch in from the row above,
    // which is the letters plane's arrangement in the wrong place. Both second rows were
    // read off stock captures on 2026-09-05 and both are ten keys wide.
    case .symbols:
      return [Array("[]{}#%^*+="), Array("_\\|~<>€£¥•"), Array(".,?!’")]
    }
  }

  public var height: CGFloat { StockMetrics.totalHeight(forWidth: width) }

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
