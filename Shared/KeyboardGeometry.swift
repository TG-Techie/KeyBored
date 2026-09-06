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

/// The moment a key's action happens: as the finger lands, or as it lifts.
///
/// It is a property of the role rather than a decision the touch layer makes, so that
/// every key states its own moment once and a key cannot be made to act at both.
public enum KeyResolution: Sendable {
  case touchDown
  case liftOff
}

extension KeyRole {
  /// When this key acts.
  ///
  /// **Lift-off is the default, and the reason is the letters.** While a finger is down
  /// on a letter its selection is still open: the preview shows the current winner and
  /// sliding can still change it, so nothing may be committed until the finger comes up.
  /// SPEC.md A.20 records that as a property we deliberately have.
  ///
  /// **A plane key has no winner to revise.** There is nothing to slide to, nothing in
  /// the constellation depends on it, and it produces no character — so waiting for the
  /// lift buys nothing and costs the whole delay. Stock resolves it as the finger lands:
  /// a capture 280ms into a press on stock's `123` already reads `ABC`, measured on an
  /// iPhone 17 Pro at 402pt, 2026-09-06. SPEC.md A.26.
  ///
  /// The switch is exhaustive on purpose. Shift, delete, the globe and the return key
  /// each have their own argument and none of them has been measured, so a role added
  /// later has to say which moment it wants rather than inheriting one.
  public var resolution: KeyResolution {
    switch self {
    case .plane:
      return .touchDown
    case .letter, .punctuation, .shift, .delete, .space, .newline, .nextKeyboard:
      return .liftOff
    }
  }
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

  /// The character this key contributes to a word's constellation, or `nil` for a key the
  /// matcher does not score.
  ///
  /// **The space bar is one of these and was not.** Jonah, 2026-09-06 10:35: "tapping
  /// near the space bar should also be accounted as potentially tapping space where the
  /// whole canvas is tap zones where only ... no character entering keys are not in the
  /// constellation matching". So the partition is between keys that enter a character and
  /// keys that do not, and it is stated here once rather than being implied by
  /// `letter != nil` at each call site.
  ///
  /// `.punctuation` stays out for now and that is a deliberate exception rather than an
  /// oversight: the host-provided period key is not a point in any word's constellation,
  /// and no entry in the lexicon contains one. SPEC.md A.14 and A.20.
  public var scoredCharacter: Character? {
    switch role {
    case .letter(let c): return c
    case .space: return " "
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
  ///
  /// Shift and delete were 144 and 145 until 2026-09-06, when a full differential against
  /// stock found them to be the only thing on the keyboard that did not match. Stock's are
  /// 146 and 147 at this reference width, measured at 1290 itself so no scaling is in the
  /// way: shift runs x 20-165 and delete 1124-1270 in a Contacts search field, dark, on a
  /// 430pt simulator. Confirmed independently at 402pt, where stock reads 136 and 137 and
  /// the new fractions predict 136.5 and 137.4 while the old ones predicted 134.6 and
  /// 135.6 — and 134 and 135 is what ours measured there. SPEC.md Appendix A.18.
  public static let shiftWidthFraction: CGFloat = 146 / referenceWidthPx
  public static let deleteWidthFraction: CGFloat = 147 / referenceWidthPx
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

  /// The key preview's shape, as multiples of the cap it rises from.
  ///
  /// Stock draws a teardrop: a rounded bulb above the key, joined to it by a narrower
  /// stem, so that the two read as one object. Measured 2026-09-06 on a 430pt simulator
  /// against a stock keyboard in a Contacts search field, dark, from a 250ms press —
  /// a longer one opens the accent picker instead, which is a different thing entirely
  /// and was mistaken for this one twice:
  ///
  ///     cap            109 x 135 px
  ///     bulb           183 wide, 182 tall, top 207px above the cap's top
  ///     stem           149 wide, running from the bulb down into the cap
  ///
  /// **Ours cannot rise as far as stock's and that is a platform limit, not a choice.**
  /// A keyboard extension's drawing is cut at its input view's edge by the compositor —
  /// no view in the chain clips, and it is still cut — so a top-row preview has only the
  /// suggestion bar's 104px to live in against stock's 207. Reserving the room by asking
  /// for a taller input view does keep the rows in place, but iOS extends the visible
  /// plate with it and the keyboard then stands 34pt taller than stock, which is a worse
  /// defect than the one it fixes. Measured, tried, reverted. So the preview is stock's
  /// shape at stock's size wherever it fits, and pushed down into view on the top row.
  /// SPEC.md Appendix A.19.
  public static let previewBulbWidthInCaps: CGFloat = 183 / 109
  /// Where the bulb's straight sides give out and the teardrop starts drawing in toward
  /// the cap, and where it arrives: 50px above the cap's top edge and 25px below it.
  ///
  /// **There is no stem.** An earlier reading measured the shape at one row, found it
  /// 149px wide, and drew a parallel-sided stem of that width. Stock's silhouette narrows
  /// the whole way down — 155px at y 2065, 145 at 2070, 135 at 2075, 127 at 2080, 119 at
  /// 2086, 115 at 2090, 111 at 2100, and the cap's own 109 from about 2115 — so a single
  /// row could have been read as any width at all.
  ///
  /// **The curve is fitted, not solved.** The left silhouette was read column by column
  /// and the pairs are in SPEC.md A.19. Two circular arcs fit it, one leaving the bulb
  /// and one arriving at the cap, but the two fits do not meet the tangency their own
  /// radii require — off by 5% — so they are not trustworthy enough to draw from. What is
  /// drawn is a cubic with vertical tangents at both ends, and it sits within about 7px
  /// of every measured point where the old parallel stem was out by 14. Recorded as an
  /// approximation so the next pass improves it rather than re-deriving it.
  public static let previewTaperTopInCaps: CGFloat = 50 / 135
  public static let previewTaperBottomInCaps: CGFloat = 25 / 135

  /// How far the cubic's control points sit along the tangent at each end. It is what
  /// sets how sharply the shape turns; 25px is the value that put the fit inside 7px.
  public static let previewTaperPullInCaps: CGFloat = 25 / 135

  public static let previewRiseInCaps: CGFloat = 207 / 135

  /// The bulb's corners are softer than a key cap's: 36px against the cap's 21px.
  ///
  /// Measured rather than guessed, because the eye reads a corner as a width error. Each
  /// row of the bulb's top 32px was scanned for its run of bulb colour and the resulting
  /// widths fitted to a rounded rectangle, on stock and on this keyboard side by side in
  /// the same field. Stock fits 34px and this keyboard, drawing 42px, fits 40px: the
  /// estimator reads 2px light on a known radius, so stock draws 36. Absolute points
  /// rather than a fraction of a cap, the same as `capCornerRadius`, because that is how
  /// it behaves across the two phone widths.
  public static let previewBulbCornerRadius: CGFloat = 36 / 3


  /// **A letter's point size is a property of the letter, not of the key it sits on.**
  /// Stock sets a capital smaller than a minuscule, and it is not a small difference: on a
  /// cap it is 21.75pt against 25pt, and in the preview 35.75pt against 38.25pt.
  ///
  /// **The numbers were found by matching ink, not by dividing out a ratio.** A point size
  /// is not visible in a screenshot, and a cap-height ratio applied to one is a derivation
  /// with a renderer's rounding inside it. So stock was captured in the Contacts search
  /// field on a 402pt simulator, light, @3x, this keyboard was captured in the same field
  /// on the same simulator, and the size was stepped until the ink measured the same. Every
  /// number below is that comparison and not an estimate:
  ///
  ///     drawn            stock ink        ours       at
  ///     E on a cap        46 px           46 px      21.75 pt   (also W, A, O, M)
  ///     e on a cap        40 px           40 px      25 pt      (also w, a)
  ///     E in a preview    76 px           76 px      35.75 pt
  ///     e in a preview    61 px           61 px      38.25 pt
  ///     123 on a cap      82 x 40 px      82 x 40    18 pt
  ///
  /// **One size for both cases is the defect this replaces.** The keyboard drew 25pt on
  /// every letter cap, which is exactly stock's minuscule and 15% over its capital — so the
  /// unshifted keyboard was right and the shifted one was visibly oversized, and no
  /// side-by-side taken in one shift state can find that. It took Jonah sending a shifted
  /// pair on 2026-09-06 at 13:52. Deriving the size from the string being drawn is what
  /// stops one shift state from being right while the other is wrong.
  ///
  /// **Stock is not one font at one size with the case doing the rest.** SF's cap height is
  /// 0.714em and its x-height 0.545em, so a single size would put `E` and `e` in a fixed
  /// 1.31 ratio. Stock's caps are 46 and 40 — a ratio of 1.15 — and its previews 76 and 61,
  /// a ratio of 1.25. Two independent sizes in each place, and the preview's pair is not
  /// the cap's pair scaled.
  ///
  /// **The sizes are constants and not fractions of a cap**, because stock's ink measures
  /// the same 46px and 40px on a 402pt phone and on Jonah's 430pt one, whose caps are 129px
  /// and 135px tall.
  ///
  /// The measurement is of English letters. Nothing says what stock does with a script
  /// whose letters have no case; `Character.isUppercase` answers false for those, so they
  /// are drawn at the minuscule's size.
  public static func capTextPointSize(for text: String) -> CGFloat {
    guard let only = text.first, text.count == 1, only.isLetter else { return keyTitlePointSize }
    return only.isUppercase ? 21.75 : 25
  }

  /// The size of the letter shown in the preview above a pressed key. See
  /// `capTextPointSize(for:)` for how both were measured and why they are two numbers.
  public static func previewLetterPointSize(for text: String) -> CGFloat {
    text.first?.isUppercase == true ? 35.75 : 38.25
  }

  /// What stock sets everything that is not a letter in: `123`, `ABC`, `#+=` and the word
  /// on the return key. Confirmed rather than assumed — stock's `123` glyph measures 82px
  /// by 40px on both phone widths and this keyboard's measures the same 82 by 40.
  public static let keyTitlePointSize: CGFloat = 18

  /// The box the letter is centred in, measured down from the top of the preview.
  ///
  /// Not the bulb, and not any part of the shape: a `UILabel` centres its *line box*, and
  /// a line box is taller than the glyph and not symmetric about it, so the two cannot be
  /// derived from one another. Read off instead. Stock's `a` occupies y 1965-2024 with
  /// the preview's top at 1879; centring in a 201px box put ours at 1960-2018, and 211
  /// puts it on stock's.
  public static let previewLetterBoxInCaps: CGFloat = 211 / 135

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

  /// The faint mark stock leaves in the corner of its space bar, measured off a 430pt
  /// phone at 3x in dark appearance.
  ///
  /// Stock draws a single letter there. Its uppercase `A` measures 28px tall, which is
  /// 13pt at SF's cap-height ratio; its bounding box ends 18px from the cap's right edge
  /// and 18px from its bottom; and its strongest pixel is `#787878` on a `#3D3D3D` cap,
  /// which is white at 0.30 to within a value — the same white the caps draw their
  /// letters in, at that alpha, lands on `#777777`.
  ///
  /// This keyboard puts its own name and version there instead of a letter. That was
  /// Jonah's ask, 2026-09-06 08:30: "you could put the keyboard name and version of the
  /// space key like how iOS does for 'English (US)'". The corner rather than the middle
  /// because stock's space bar is blank in the middle and a permanent label there would
  /// be the first thing that does not look like stock.
  public static let spaceMarkPointSize: CGFloat = 13
  public static let spaceMarkInset: CGFloat = 18 / 3
  public static let spaceMarkAlpha: CGFloat = 0.30

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

  /// What separates two caps in a row, and what separates two rows. Distances are
  /// normalized by these so that a score computed on one device means the same as a
  /// threshold tuned on another. The horizontal unit is not stored as a pitch because
  /// there is no single one: see `normalizedManhattan(from:to:)`.
  public let columnGap: CGFloat
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

    self.columnGap = gap
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
  ///
  /// **The horizontal unit belongs to the key being measured to, not to the grid.** It
  /// used to be one `columnPitch` for every key, which is right while every key is the
  /// same width and silently wrong the moment one is not. The space bar is 615px against
  /// a letter's 109 at 430pt, so its centre sits far from taps that are inside it: a tap
  /// 13px in from the space bar's own left edge scored 2.32 to space and 1.32 to `x`, one
  /// row up. **Space lost inside itself**, which is why simply adding it to the candidate
  /// set would have looked as though it did nothing.
  ///
  /// Dividing by `key.frame.width + columnGap` is identity for a key of the standard
  /// letter width, because that sum is exactly the old `columnPitch`. So every
  /// letter-to-letter score is unchanged to the bit, every tuning constant in SPEC
  /// section 5 keeps the meaning it was fitted with, and only keys that are not
  /// letter-width behave differently. `MatcherTests` asserts that identity rather than
  /// leaving it as an argument. SPEC.md A.20.
  public func normalizedManhattan(from point: CGPoint, to key: Key) -> Double {
    let dx = abs(point.x - key.center.x) / (key.frame.width + columnGap)
    let dy = abs(point.y - key.center.y) / rowPitch
    return Double(dx + dy)
  }

  /// Every letter key on this geometry, in row-major order.
  public var letterKeys: [Key] { keys.filter { $0.letter != nil } }

  /// Every key whose position is a point in a word's constellation: the letters and the
  /// space bar. See `Key.scoredCharacter`.
  public var scoredKeys: [Key] { keys.filter { $0.scoredCharacter != nil } }

  public func key(for character: Character) -> Key? {
    keys.first { $0.letter == character }
  }
}
