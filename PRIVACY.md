<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# What KeyBored does with what you type

A keyboard sees everything: passwords, messages, card numbers. So this document is not a
promise, it is a set of instructions for checking. Every claim below has the command that
verifies it, and you should run them rather than believe them.

## The short version

Your taps are held in memory for the length of one word, used to pick a word, and dropped
at the next space. Nothing is written to disk, nothing is sent anywhere, nothing is logged,
and nothing about your typing survives the word you are typing.

## The strongest guarantee is not ours to give

`KeyBoredKeyboard/Info.plist` sets `RequestsOpenAccess` to `false`.

    grep -A1 RequestsOpenAccess KeyBoredKeyboard/Info.plist

A custom keyboard without open access **cannot** reach the network, cannot share a
container with its host app, cannot use `UIPasteboard`, and cannot see the file system
outside its own container. That is enforced by iOS, not by this code, which makes it worth
more than anything the source could promise. It is also why iOS does not show you an
"Allow Full Access" prompt for this keyboard: there is nothing to allow.

**If that ever changes, this section stops being an OS guarantee and becomes a promise
again.** `SPEC.md` section 10 records that Full Access may eventually be requested for the
keyboard click sound, and that nothing functional may depend on it. If you install a build
whose `RequestsOpenAccess` is `true`, re-read everything below on that basis.

## What the code does, and how to check

**No networking exists anywhere in the app or the keyboard.**

    grep -rn --include='*.swift' -E 'URLSession|URLRequest|NWConnection|CFSocket|dataTask' \
      KeyBored KeyBoredKeyboard Shared

The only imports in the whole project are `CoreGraphics`, `Foundation`, `SwiftUI` and
`UIKit`:

    grep -rh '^import ' --include='*.swift' KeyBored KeyBoredKeyboard Shared | sort -u

**Nothing is written or persisted.** No `UserDefaults`, no files created, no database, no
archiving:

    grep -rn --include='*.swift' -E 'UserDefaults|FileManager|\.write\(|createFile|NSKeyedArchiver|CoreData' \
      KeyBored KeyBoredKeyboard Shared

That returns two lines, both in `Shared/EnglishLexicon.swift`, and neither is a write: one
is a `FileManager` **read** of the bundled word list, the other is the comment above it
explaining why. The read is deliberately `contents(atPath:)` rather than
`String(contentsOf:)`, because the latter accepts a remote URL and a path cannot be one.

**Nothing is logged.** No `print`, no `NSLog`, no analytics:

    grep -rn --include='*.swift' -E 'print\(|NSLog|Analytics|os_log' \
      KeyBored KeyBoredKeyboard Shared

## What is held in memory, and for how long

`WordInProgress` in `Shared/TypingSession.swift` holds the taps of the word you are
currently typing, as `TapNeighborhood` values — a short list of candidate letters and
distances per tap. It is a value type, it lives on the view controller, and `reset()` is
called at every word boundary.

Read `commitWord()` and `endWord(committing:)` in
`KeyBoredKeyboard/KeyboardViewController.swift`. There is no other store, no history, no
buffer of previous words, and no accumulating state of any kind.

## The keyboard does not learn

Prediction is a pure function of your taps, the bundled word list and the key geometry. The
same taps produce the same three words on every device, forever, because there is nothing
that adapts. `KeyBoredTests/MatcherTests.swift` asserts this directly, in
`theSameTapsGiveTheSameAnswerEveryTime`.

Whether the keyboard should learn the words you type is an open question in `SPEC.md`
section 10, and it is open partly because learning would make this section untrue.

## The word list

19,217 English words, public domain, bundled in the app. It is a fixed file and it is not
personalised, downloaded or updated. Its provenance and licence are in
`Shared/Resources/README.md`.

## If you find something this document gets wrong

It is a bug, and a more serious one than anything in the matcher. Open an issue.
