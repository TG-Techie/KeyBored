// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import Foundation

/// Where an entry came from. It carries no behaviour today; it exists so that a word
/// the keyboard suggests can always be traced to why it knows the word, which is a
/// question a daily driver's user will eventually ask.
public enum EntrySource: String, Sendable {
  case builtin
  case contraction
  case idiom
  case textReplacement
  case userAdded
}

/// The structural decision of this project, in two fields.
///
/// `tapForm` is what your fingers do; `insertion` is what appears. Keeping them apart
/// means a contraction, a word that is not a word, and an iOS text replacement are all
/// the same kind of thing rather than three special cases:
///
///   cat  -> cat            an ordinary word, the two are equal
///   dont -> don't          the apostrophe is never typed, never matched against
///   lol  -> lol            a non-word people type constantly
///   omw  -> On my way!     a user's own text replacement, straight from UILexicon
///
/// Only `tapForm` is matched, and it is letters only, so nothing in the matcher ever
/// has to know that apostrophes or capitals exist.
public struct LexiconEntry: Sendable, Equatable {
  public let tapForm: String
  public let insertion: String
  public let source: EntrySource

  public init(tapForm: String, insertion: String? = nil, source: EntrySource = .builtin) {
    self.tapForm = tapForm
    self.insertion = insertion ?? tapForm
    self.source = source
  }
}

/// A trie over `tapForm`, flattened into arrays.
///
/// The trie is not an optimisation detail, it is what makes the search cheap in the
/// way the algorithm requires: at each tap only the edges whose letter is in that
/// tap's neighbourhood are followed, so an entry that disagrees with the typing in its
/// first letter costs one dictionary lookup rather than a whole word comparison.
public struct Lexicon: Sendable {
  struct Node: Sendable {
    var children: [Character: Int] = [:]
    /// Several entries can share one tap form: "well" is both a word and how you type
    /// "we'll", and "its" is both a word and how most people type "it's". Collapsing
    /// them would make one of the two untypeable, so a node holds all of them and the
    /// matcher offers each as its own candidate.
    var entries: [Int] = []
  }

  var nodes: [Node]
  public private(set) var entries: [LexiconEntry]

  /// Reserving is not a micro-optimisation here, it is most of the cost.
  ///
  /// The trie is built once, at the moment the keyboard extension loads, and until it is
  /// built the keyboard cannot offer a candidate — so this is on the path somebody
  /// watches. Growing two arrays from empty through 75,000 words means reallocating and
  /// copying both of them a few dozen times. The node estimate is the observed ratio of
  /// nodes to entries on the bundled list rounded up; being wrong about it costs one
  /// reallocation, and being right saves all of them.
  public init(entries: [LexiconEntry]) {
    self.nodes = [Node()]
    self.nodes.reserveCapacity(entries.count * 3 + 1)
    self.entries = []
    self.entries.reserveCapacity(entries.count)
    for entry in entries { insert(entry) }
  }

  /// An entry whose tap form and insertion both match one already present is dropped;
  /// anything else is added alongside. So loading the same list twice is harmless, and
  /// a user's text replacement joins a built-in word rather than displacing it.
  public mutating func insert(_ entry: LexiconEntry) {
    var node = 0
    for character in entry.tapForm {
      if let next = nodes[node].children[character] {
        node = next
      } else {
        nodes.append(Node())
        let next = nodes.count - 1
        nodes[node].children[character] = next
        node = next
      }
    }
    if nodes[node].entries.contains(where: { entries[$0] == entry }) { return }
    entries.append(entry)
    nodes[node].entries.append(entries.count - 1)
  }

  public var count: Int { entries.count }

  /// Every entry with exactly this tap form, used to ask whether what the user
  /// literally typed is itself known. A literal that is already a word is not a typo.
  public func entries(forTapForm tapForm: String) -> [LexiconEntry] {
    var node = 0
    for character in tapForm {
      guard let next = nodes[node].children[character] else { return [] }
      node = next
    }
    return nodes[node].entries.map { entries[$0] }
  }

  func children(of node: Int) -> [Character: Int] { nodes[node].children }
  func entryIndices(at node: Int) -> [Int] { nodes[node].entries }
}
