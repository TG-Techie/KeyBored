// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   Shared/Resources/README.md — where the word list came from, its licence, what was
//   filtered out of it, and why this list rather than a larger one.

import Foundation

/// Assembles the lexicon the keyboard actually predicts against: a bundled English word
/// list, plus the contractions and idioms that are hand-held because no dictionary
/// carries them in the shape the matcher needs.
///
/// The word list is a bundled data file rather than a Swift literal so that replacing it
/// is a data change. `Lexicon` never learns which it was — it only ever sees
/// `LexiconEntry` values, which is the point of the seam being there.
public enum EnglishLexicon {
  /// The bundled list: 75,646 words, 12dicts `2of12inf` with inflections, unioned with
  /// the `3esl` list it replaced. See the README beside the file for the licence text,
  /// the acknowledgments its authors require, and why the list grew fourfold.
  public static let wordListResource = "12dicts-2of12inf-lowercase"

  /// Contractions, whose tap form has no apostrophe so the user never leaves the letter
  /// plane and the constellation is computed over letters alone.
  ///
  /// These are hand-held rather than taken from the word list because a dictionary's
  /// apostrophe entries are possessives of phrases ("Achilles' heel"), not the
  /// apostrophe-free tap forms people actually type.
  static let contractions: [(String, String)] = [
    ("cant", "can't"), ("dont", "don't"), ("didnt", "didn't"), ("doesnt", "doesn't"),
    ("wont", "won't"), ("wouldnt", "wouldn't"), ("couldnt", "couldn't"),
    ("shouldnt", "shouldn't"), ("isnt", "isn't"), ("arent", "aren't"), ("wasnt", "wasn't"),
    ("werent", "weren't"), ("hasnt", "hasn't"), ("havent", "haven't"), ("hadnt", "hadn't"),
    ("im", "I'm"), ("ive", "I've"), ("ill", "I'll"), ("id", "I'd"),
    ("youre", "you're"), ("youve", "you've"), ("youll", "you'll"), ("youd", "you'd"),
    ("hes", "he's"), ("shes", "she's"), ("its", "it's"), ("thats", "that's"),
    ("theres", "there's"), ("theyre", "they're"), ("theyve", "they've"),
    ("were", "we're"), ("weve", "we've"), ("well", "we'll"),
    ("lets", "let's"), ("whats", "what's"), ("whos", "who's"), ("heres", "here's"),
  ]

  /// Things people type often that are not words. No dictionary has these, by
  /// definition, so they are held here. See SPEC.md section 7, source 3.
  static let idioms = [
    "lol", "lmao", "omg", "btw", "idk", "imo", "tbh", "brb", "ok", "okay", "yep", "nope",
    "hey", "hi", "yay", "ugh", "hmm", "wtf", "fyi", "asap", "eta", "rsvp", "tbd", "afaik",
  ]

  /// Reads the bundled word list, by path.
  ///
  /// Deliberately `FileManager.contents(atPath:)` rather than `String(contentsOf:)`: the
  /// latter accepts a remote URL, and although `Bundle.url` only ever returns a file URL,
  /// a reviewer checking that this keyboard makes no network call should not have to trace
  /// that guarantee somewhere else. The path-based API has no remote form. See PRIVACY.md.
  ///
  /// A missing resource is a build error rather than a runtime condition — the file is
  /// compiled into the bundle or it is not — so this traps with a message naming the
  /// resource rather than quietly returning an empty list. A keyboard that silently
  /// predicts nothing is the failure that would take longest to notice.
  public static func words() -> [String] {
    guard let url = Bundle(for: BundleToken.self)
      .url(forResource: wordListResource, withExtension: "txt")
    else {
      fatalError(
        "\(wordListResource).txt is missing from the bundle. It is listed in project.yml "
          + "under each target's sources; regenerate the project with `xcodegen generate`.")
    }
    guard let data = FileManager.default.contents(atPath: url.path),
      let contents = String(data: data, encoding: .utf8)
    else {
      fatalError("\(wordListResource).txt is in the bundle but could not be read as UTF-8.")
    }
    return contents.split(whereSeparator: \.isNewline).map(String.init)
  }

  /// Entries sharing a tap form all survive, so "its" yields both "its" and "it's" and
  /// the bar can offer each. Which one a tie goes to is the matcher's business: it
  /// prefers the entry that changes nothing, so the plain word wins and the contraction
  /// sits in the next bubble along.
  public static func entries() -> [LexiconEntry] {
    var entries = words().map { LexiconEntry(tapForm: $0, source: .builtin) }
    entries.append(contentsOf: idioms.map { LexiconEntry(tapForm: $0, source: .idiom) })
    entries.append(contentsOf: contractions.map {
      LexiconEntry(tapForm: $0.0, insertion: $0.1, source: .contraction)
    })
    return entries
  }

  public static func make() -> Lexicon { Lexicon(entries: entries()) }
}

/// Resolves to whichever bundle this code was compiled into — the app, the keyboard
/// extension, or the test bundle. `Shared/` is compiled into all three, so a fixed
/// `Bundle.main` would be wrong in at least two of them.
private final class BundleToken {}
