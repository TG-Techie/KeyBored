<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# AGENTS

Notes for anyone, human or agent, working on KeyBored.

## What KeyBored is

**The project is KeyBored; the app is BoreKey.** The repository, the targets, the bundle
identifiers are KeyBored. BoreKey is the only name a person sees: the app on the home
screen, and the keyboard in Settings and on the globe key. It is written once, as
`PRODUCT_DISPLAY_NAME` in `project.yml`, and read back off the bundle by `Branding` in
`Shared/Branding.swift` — never as a literal in an Info.plist or a view.

The built products are named for it too — `BoreKey.app`, and `BoreKey.appex` inside its
`PlugIns` — because `CFBundleName` can only be set through `PRODUCT_NAME` and is otherwise
another place the old name shows. The Swift modules are not: `PRODUCT_MODULE_NAME` is
pinned to the target names, so `@testable import KeyBored` stays true. `TEST_HOST` names
the product and therefore has to be written out in `project.yml`; left to xcodegen's
default it points at a `KeyBored.app` that no longer exists, and the symptom is not a
build error but the whole test suite quietly declining to run.

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

## Changes to the keyboard are architectural, never patches

Every change to the keyboard is made so that the finished code reads as though it had been
written correctly from the beginning. Not "tidily": the test is whether the defect is still
*expressible* afterwards. Adding a second check beside the first one, so that the two now
agree, leaves the disagreement possible and is the thing this rule forbids; the fix is to
arrange the code so that only one of them exists.

The change that produced the rule is the worked example. Taps landing in the 6pt gaps
between key caps did nothing at all — no character, no key preview, no highlight — because
UIKit was choosing which view heard about a touch before any of this project's own
resolution ran. Three symptoms, three places they could have been patched, one cause. What
went in instead was a single touch layer: `KeyboardView.hitTest(_:with:)` claims every
point in its bounds so nothing else can take one, `target(at:)` is the only code allowed to
turn a coordinate into a meaning, and the insertion, the preview and the highlight are all
driven from that one answer. After it, a tap that resolves to a key and draws no preview is
not a bug that happens to be fixed — it is a state the code cannot express.

The same example carries the rule's hardest lesson, because that fix was necessary and not
sufficient, and 0.0.6 shipped believing otherwise. A keyboard extension draws in its own
process and is composited by another one, and the compositing process decides which touches
to forward before any code here runs — by what was drawn. The gaps were transparent, so the
override was answering a question it was never asked. Holistic means the whole system the
change lives in, and the system here has two processes in it: `KeyboardView.touchableFill`
is the same claim made to the other one. Measured, not reasoned: with no fill, six of eight
taps across the q/w boundary arrived; with `.clear`, six of eight; with alpha 1/255, eight
of eight, and the plate reads `#171717` either way.

Granted by Jonah, pbm, 2026-09-06. His words, verbatim: "Do so Systematically and
holistically; this needs to be an architectural, coherent change such that the keyboard
appears to have been written correctly from the beginning, never patched  /  Approach all
changes to the keyboard like that  /  PBM A". Recorded by hazy-zephyr, 2026-09-06; the
wording of the paragraphs above is mine, not his, except where quoted.

## Never assume your conclusions are correct

A conclusion is true over the region you exercised, and nowhere else until you exercise it.
State the boundary with the claim, or do not state the claim.

This is not a new rule — fleet doctrine has carried "never presume your presumptions are
correct" for weeks. It is here because it was broken four times in one morning on this
project, and each time the break had the same shape: something verified in the region that
could be reached, then reported as a property of the whole.

- "The preview and the insertion read the same hit-test result, so they cannot disagree."
  True everywhere a touch was delivered. In the gaps no touch was delivered at all, so the
  shared path had never run there, and the sentence was a claim about the whole keyboard
  drawn from the part of it that worked.
- "The 51px band was a 0.0.3 defect that `3a9fde1` fixed." The reverse: `3a9fde1`
  introduced it. The commit had been re-read, and re-reading is not a check.
- "Stock's key preview is a teardrop with a stem." From memory of what iOS keyboards look
  like. It is a detached rounded rectangle, and his screenshot says so.
- A time and a commit hash, both stated without running the command that would print them,
  and one of them reported a deadline as missed when it had not yet arrived.

The practical form, and the one to actually follow: **anything a command would print gets
the command run at the moment of writing the sentence**, and any claim wider than what was
measured says how wide the measurement was. There is a fleet SOP entry on each of these —
`recalled-values-reported-as-measurements.md` and
`the-process-that-routes-input-may-be-reading-your-pixels.md`.

The companion instruction, given in the same message: **do not use him as a test harness.**
The reference keyboard is on the same device as ours and on the simulator here. Measure
ours against it, find the whole set of defects, fix them, verify them, and bring him a
build — not a question and not a report of what his own keyboard does.

Granted by Jonah, pbm, 2026-09-06. His words, verbatim: "I am not your reverse centaur; go
do it and do it well  /  never assume your conclusions are correct  PBM". Recorded by
hazy-zephyr, 2026-09-06; the wording of the paragraphs above is mine, not his, except where
quoted, and the four examples are my own errors and crisp-kelp's.

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
