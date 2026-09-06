// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md Appendix A.10 for the measurements every case below came from.

/// What the quote keys actually put in the field.
///
/// The keys are drawn with the curly glyphs, because stock draws them that way — the cap
/// says `’` and `”`, not `'` and `"`. But the glyph on the cap is not the character that
/// goes in: stock picks the opening or the closing form from what is already in front of
/// the cursor, so one key produces two characters and the cap can only show one of them.
///
/// Every case here was read off a simulator on 2026-09-06 by typing with the stock
/// keyboard and then copying the field, so the codepoint comes from the pasteboard rather
/// than from a screenshot of a glyph — `‘` and `’` are a few pixels apart at 3x and
/// telling them apart by eye is exactly the mistake SPEC.md Appendix A.9 is about:
///
///     (empty field) '   →  U+2018    "A "  '  →  U+2018    "("  '  →  U+2018
///     "A"           '   →  U+2019    "5"   '  →  U+2019
///     (empty field) "   →  U+201C    "“"   "  →  U+201D
///
/// The last of those is why the rule below is "opening after nothing, whitespace or an
/// opening bracket, closing otherwise" rather than a paired-quote state machine: stock
/// closes after its own opening quote, which a state machine tracking open pairs would
/// not do.
public enum SmartPunctuation {
  /// The apostrophe key's cap glyph, and the character it produces mid-word.
  public static let apostrophe: Character = "\u{2019}"
  /// The double-quote key's cap glyph, and the character it produces mid-sentence.
  public static let quote: Character = "\u{201D}"

  /// The text a strike on `character` inserts, given what sits before the cursor.
  ///
  /// Anything that is not one of the two quote keys is inserted exactly as struck, which
  /// is the whole of the numbers and symbols planes apart from those two.
  public static func text(for character: Character, after previous: Character?) -> String {
    switch character {
    case apostrophe: return opensQuote(after: previous) ? "\u{2018}" : "\u{2019}"
    case quote: return opensQuote(after: previous) ? "\u{201C}" : "\u{201D}"
    default: return String(character)
    }
  }

  /// The plain form, for a field that turned smart quotes off.
  ///
  /// A field that sets `smartQuotesType = .no` — a code editor, a field taking a literal
  /// — wants the ASCII character, and giving it a curly one would be this keyboard's own
  /// bug rather than a match with stock. **What stock draws on the cap in such a field
  /// was not observed**, and no field asking for `.no` has been found on this simulator
  /// to check against; the cap keeps its curly glyph here either way.
  public static func plain(for character: Character) -> String {
    switch character {
    case apostrophe: return "'"
    case quote: return "\""
    default: return String(character)
    }
  }

  /// Whether the apostrophe key returns the keyboard to the letters plane.
  ///
  /// It does, and the double quote does not, and neither does the period, the comma or a
  /// digit — all four measured the same afternoon by tapping the key and screenshotting
  /// which plane came back. It is a sensible asymmetry rather than an oversight: an
  /// apostrophe is nearly always typed inside a word, so the next tap after it is a
  /// letter, and every other key on that plane is not.
  public static func returnsToLetters(after character: Character) -> Bool {
    character == apostrophe
  }

  /// Opening after nothing, after whitespace, and after an opening bracket; closing after
  /// everything else. The bracket set is the three ASCII pairs plus the same three the
  /// symbols plane draws, so `('` and `['` behave alike.
  private static func opensQuote(after previous: Character?) -> Bool {
    guard let previous else { return true }
    if previous.isWhitespace { return true }
    return "([{".contains(previous)
  }
}
