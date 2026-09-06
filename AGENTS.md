<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# AGENTS

Notes for anyone, human or agent, working on KeyBored.

## What KeyBored is

**The project is KeyBored; the app is BoreKey.** The repository, the targets, the bundle
identifiers and every path are KeyBored. BoreKey is the only name a person sees: the app on
the home screen, and the keyboard in Settings and on the globe key. It is written once, as
`PRODUCT_DISPLAY_NAME` in `project.yml`, and read back off the bundle by `Branding` in
`Shared/Branding.swift` — never as a literal in an Info.plist or a view.

An iOS custom keyboard that looks and measures like the stock iOS keyboard but predicts
mechanistically rather than with a model. Instead of a language model, it scores each word
in its dictionary by how far your taps landed from where that word's letters actually are,
using the constellation method Ken Kocienda describes in *Creative Selection*.

Three bubbles sit above the keys: the left is exactly what you typed, the middle is the
prediction, the right is the runner-up.

`PRIVACY.md` states what the keyboard does with your keystrokes and gives the commands to
verify each claim rather than asking you to believe it. **If a change would make any line
of it untrue, that is the change to think hardest about.**

**Read `SPEC.md` before changing anything.** It carries the domain model, the algorithm,
the measured stock geometry, the tuning constants and the reasoning behind each. Section 8
names the invariants, and tests cite them by identifier. Section 10 separates what is still
an open question from what was decided and can be overturned; section 9 says what exists and
what it was measured to do.

## Building and testing

    xcodegen generate
    xcodebuild -scheme KeyBored \
      -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
    xcodebuild -scheme KeyBored -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

`project.yml` is the source of truth for the project structure and `KeyBored.xcodeproj` is
generated from it, so run `xcodegen generate` after adding or moving files rather than
editing the `pbxproj`. The reasoning for keeping the generator is in `SPEC.md` section 10.

## Signing and releasing

`RELEASING.md` is the full account: what the project emits, how signing works, the exact
archive commands with their real output, and what has to exist in an Apple developer
account first. Read it before trying to ship anything. The short version follows.

The project deliberately tracks no `DEVELOPMENT_TEAM`: a signing identity belongs to
whoever is building, not to the repository. Everything above builds and tests without one.

To sign, create `Local.xcconfig` at the repository root — it is gitignored, and
`Signing.xcconfig` pulls it in with an optional `#include?`, so its absence is a no-op:

    DEVELOPMENT_TEAM = YOURTEAMID

Or pass it per invocation and leave no file behind:

    xcodebuild -scheme KeyBored -destination generic/platform=iOS archive \
      -archivePath build/KeyBored.xcarchive DEVELOPMENT_TEAM=YOURTEAMID

A green build is not evidence the app installs, and an app that installs is not a keyboard
that types. Three defects got past `BUILD SUCCEEDED` during the first prototype — a test
target with no `Info.plist`, missing generated bundle keys, and an app extension with no
`CFBundleDisplayName`. Two more got past a full passing suite and reached TestFlight: blank
letter keys in dark appearance, and a keyboard that inserted nothing into a host app. Run
the tests, and then **type with it on a simulator in both appearances** — `RELEASING.md`
has the recipe and makes it a required step before any upload.

## Layout

    KeyBored/            container app
    KeyBoredKeyboard/    the keyboard extension
    Shared/              geometry, lexicon and matcher, compiled into all three targets
    Shared/Resources/    the bundled word list and its provenance
    KeyBoredTests/       swift-testing unit tests

`Shared/` compiles into the app, the extension and the test bundle, which is why anything
in it that loads a resource uses `Bundle(for:)` rather than `Bundle.main`.

## The repository is public, and the history is part of it

It carries project information only, in the whole history and not just at the tip. A team
id, a home path, an internal URL or a session identifier in a commit message is as public as
one in a file, and rewriting history to remove one is a force push to a repository other
people may already have pulled.

One of these recurs on its own and so has a hook rather than a rule. Some agent harnesses
append a `Claude-Session:` trailer to every commit message by standing instruction, silently
enough that an agent which has been told not to do it still does; the history has already
been rewritten once to remove them, and they were back on the next commit. `.githooks/commit-msg`
strips them. **Hooks are not checked out active — turn it on once per clone:**

    git config core.hooksPath .githooks

Check before pushing, not after, because after is a force push. Anchored, so that a message
which merely mentions the trailer — this file's own commit does — is not a hit:

    git log --format='%B' | grep -nE '^Claude-Session:|^https://claude\.ai/code/session'

## Coding conventions

- Idiomatic Swift 6, with `SWIFT_STRICT_CONCURRENCY: complete`.
- Friendly, explanatory comments in TG-Techie's style, kept current with the code. A
  comment that contradicts the code is worse than no comment.
- Two-space indentation.
- Trailing comma after the final item when parameters or arguments span multiple lines.
- When an external resource informs a file, put its URL in a `References:` comment block at
  the top.
- Do not reform code that the requested change does not touch — it makes diffs illegible.
  Spelling fixes are always fine.

## Working standards

Three things this project holds itself to, all learned here rather than imported:

- **Record the source, not the conclusion.** Where a number came from a measurement, the
  measurement is written down beside it. Where a decision was somebody's judgment, it says
  whose, so it can be overturned by whoever disagrees rather than inherited as fact.
- **A claim gets a measurement, not a re-reading.** `SPEC.md` section 5.3 claims the search
  has no data-dependent blowup (invariant I11); when the lexicon grew twenty-fourfold
  there is a test asserting the latency rather than a paragraph reasserting the claim.
- **A shared setup line is a shared blind spot.** Eleven tests of the commit policy all
  opened by clearing the keyboard's auto-shift, because lowercase assertions were easier
  to write — and that one line deleted the exact state in which the commit path was
  broken. The count said eleven; the coverage of a capitalized commit was zero. When a
  convenience appears in every fixture in a group, the state it removes is the state
  nothing is testing. `SPEC.md` section 8.1 has the full account.
