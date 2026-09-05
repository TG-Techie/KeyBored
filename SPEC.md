<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# KeyBored — specification

A domain model for a mechanistically predictable iOS keyboard: what the system is, what
states it can be in, which states are unreachable by construction, and what must always
hold.

This document is the specification. Where a number is a decision, the number is here and
the reasoning with it; where a rule is testable, it is stated so that a test can name it.
Section 8 lists the invariants by identifier, and the test suite refers to them.

---

## 1. The problem

A person typing quickly on glass lands *near* the key they meant and wants the word they
meant.

Every touchscreen keyboard solves some version of this. KeyBored's constraint is how: by
geometry alone, with no model, no learning, and no adaptation. The method is the
constellation matching described by Ken Kocienda in *Creative Selection* — score each word
in a fixed dictionary by how far the taps fell from where that word's letters actually
are, and take the best.

Two properties govern every decision below.

**Mechanistically predictable.** The same taps, against the same lexicon and the same
geometry, produce the same three words — every time, on every device, with no randomness,
no time dependence and no accumulated state. This is not a slogan; it is a property that
can be falsified by a test, and section 8 makes it one.

**Daily driver.** The keyboard has to be right, because a person cannot stop using their
keyboard in the middle of a sentence. A wrong correction costs more than a missing one.

## 2. Scope, as a property of the design

**In.** Stock-matching geometry and presentation; the per-tap letter bubble; constellation
matching under equal word weighting; the three-bubble candidate bar; a lexicon in which
ordinary words, contractions, common non-words and the user's own text replacements are
one kind of thing.

**Designed for, not yet built.** English word-frequency weighting. Section 5.4 defines it
as a single additive term whose coefficient is currently zero, so arriving at it is a data
change rather than a redesign.

**Deliberately absent.** No model of any kind. No learning. No network access. No retention
of keystrokes beyond the word being typed. These are properties of the design rather than
promises about behaviour: section 3.3 states the construction that makes retention
impossible rather than merely absent, and `PRIVACY.md` gives the commands that check each
one.

**Left possible, not built.** Swipe input. A stroke would reduce to the same sequence of
tap neighbourhoods the matcher already consumes, so nothing about the tap record forecloses
it. Nothing is spent on it now.

---

## 3. The domain

The whole of the prediction problem is: a sequence of noisy points, a set of words, and an
ordering over them. The model below makes exactly that expressible.

### 3.1 Entities

Each is defined in terms of the others rather than in terms of the types that implement it.

**Plane** — which characters the keys currently produce: `letters`, `numbers`, `symbols`.
Shift is *not* a plane. Shifted and unshifted letters occupy identical geometry and must
share their constellations, so shift is a modifier on the letter plane and the plane is
unchanged by it.

**Key** — an identity, a role, and a rectangle. The identity is independent of what the key
currently produces. The role is either a letter or a command (shift, delete, space, return,
plane switch, next keyboard). Only letters take part in matching; commands are resolved
before the matcher is consulted and never reach it.

**Geometry** — for one width and one plane, the rectangle of every key, plus the
centre-to-centre column and row pitch. It is the single source of truth for both
hit-testing and for ideal key positions. Deriving those separately is how a keyboard ends
up predicting against a layout it is no longer drawing, so there is one derivation and both
uses read it.

**Tap** — a point in keyboard coordinates. Not a letter. The point is the entire signal the
matcher runs on; rounding a tap to its key at the moment of touch discards the thing being
measured, so a tap is never rounded.

**Tap neighbourhood** — for one tap, the letters that tap could plausibly have meant, each
with its cost. Ordered by cost, non-empty, and bounded in size. Defined in section 5.2.

**Word in progress** — the tap neighbourhoods since the last word boundary, plus whether
shift was down for the first of them. This is the only mutable state in the system and it
is destroyed at every boundary.

**Lexicon entry** — a pair of strings and a source:

    tapForm     the letters you actually press, letter plane only
    insertion   the text that appears when this entry is chosen
    source      builtin | contraction | idiom | textReplacement | userAdded

The separation of `tapForm` from `insertion` is the structural decision of this
specification, and it is what makes four different-looking features one mechanism:

- An ordinary word has them equal: `cat` → `cat`.
- A contraction has them differ by punctuation: `dont` → `don't`. The user never reaches
  the symbols plane, and the constellation is still computed over letters only.
- A common non-word — `lol` — is an ordinary entry with a different source.
- A user's iOS text replacement is the same shape: `omw` → `On my way!`.

Because they are one shape, they are one trie, one search and one ranking. There is no
special-case code path anywhere in the matcher, and adding a source cannot introduce one.

**Constellation** — the ideal tap point for each letter of an entry's `tapForm` under a
given geometry: the shape a perfect typist would produce. Derived from the geometry,
never stored with the lexicon, recomputed when the geometry changes.

**Candidate** — an entry together with its score against a tap sequence.

**Candidate bar** — exactly three slots. Section 6.

**Commit** — what a word boundary puts into the text: either the literal or a correction.
Section 6.3.

### 3.2 States and transitions

The system as a whole is a plane, a shift flag, and a word in progress. Everything else is
derived.

    (plane, shifted, word)  --letter tap on letters plane-->  (plane, false, word + tap)
    (plane, shifted, word)  --letter tap on other plane-->    (plane, shifted, ∅)   text inserted as struck
    (plane, shifted, word)  --space / return-->               (plane, shifted, ∅)   commit, then separator
    (plane, shifted, word)  --delete-->                       (plane, shifted, word − last tap)
    (plane, shifted, word)  --shift-->                        (plane, ¬shifted, word)
    (plane, shifted, word)  --plane switch to p-->            (p, shifted, ∅)
    (plane, shifted, word)  --bubble tap-->                   (plane, shifted, ∅)   chosen text inserted

Two of those are the load-bearing ones.

**A word ends at every boundary, and ending it destroys it.** There is no path from a
committed word back to the taps that produced it. That is what makes section 3.3's
retention claim structural.

**A tap on a non-letter plane ends the word.** A digit or a symbol is not a tap the matcher
can score, because the constellation is defined over letters. Rather than scoring it badly,
the model refuses to represent it: the word ends and the character is inserted as struck.

### 3.3 States that cannot be represented

The useful half of a domain model is what it makes impossible. Each of these is a
consequence of the construction, not a rule someone has to remember.

**An empty tap neighbourhood.** Every tap inside the keyboard has a nearest key, and the
neighbourhood is built from that key outwards, so it always contains at least one letter.
No caller handles an empty case because there is no empty case. *(Invariant I3.)*

**A prediction that depends on history.** The word in progress is a value, replaced at
each boundary, and the matcher is a pure function of `(taps, geometry, lexicon)`. There is
no accumulator to consult, so "the same taps give a different answer" has nowhere to come
from. *(Invariant I1.)*

**Retained keystrokes.** There is no buffer of past words, no log, and no store. The only
text that outlives a word boundary is the text that was inserted into the host app's field,
which was already the user's. This is why the privacy claim is checkable rather than
promised.

**A layout the matcher does not share with the view.** Both read one geometry. A key drawn
where the matcher does not think it is cannot be constructed.

**A ranking that depends on enumeration order.** The tie-break in section 5.4 is total, so
two runs cannot order equal-scoring candidates differently. *(Invariant I2.)*

**A correction that changes what a bubble said it would.** The bar is cased and rendered
from the same values the commit inserts. Section 6.

---

## 4. Geometry

The keyboard matches the stock iOS keyboard's dimensions and presentation. A custom
keyboard extension does not inherit stock metrics — it declares its own height and draws
its own keys — so matching is something this project does deliberately and has to keep
doing across iOS releases.

Horizontal metrics are fractions of the keyboard's width, because stock columns scale with
the screen. Vertical metrics are in points, because stock rows do not: a taller phone gets
the same 45pt keys, not taller ones. Appendix A carries the measurements every constant
comes from.

Key width is derived from the remainder — width, less both margins, less the nine gaps,
divided by ten — rather than from its own fraction, so a row lands exactly on both margins
instead of a pixel short.

The suggestion strip is reserved above the first key row unconditionally, whether or not
it has anything in it. Rows that shift by 35pt mid-word because a prediction appeared would
be worse than no bar at all.

Required for a daily driver, and all present: the per-tap letter bubble above the key being
held, planes, shift, delete, return, and the next-keyboard globe (which Apple requires in
any case).

**Hit-testing** is by rectangle first, so that the gaps between keys behave the way stock's
do, falling back to nearest centre only for a point inside the keyboard that landed in no
key. A point above the first row — in the suggestion strip — is not a key press.

---

## 5. The matcher

### 5.1 The score

For an entry whose `tapForm` is c₁…cₙ and a tap sequence t₁…tₙ of the same length:

    S = Σᵢ  manhattan( tᵢ , centre(cᵢ) )

with distances in **normalized key units**: Δx divided by the column pitch, Δy divided by
the row pitch. Lower is better.

Normalization is what makes a score portable. A threshold tuned on one screen size means
the same thing on the next, because "half a key away" is the unit rather than "twenty-one
points away".

Manhattan rather than Euclidean: it is cheaper, and on keys that are wider than they are
tall it penalizes vertical error more than Euclidean would, which matches the fact that
hitting the wrong row is a worse mistake than drifting within one.

### 5.2 The neighbourhood

For each tap, the admissible letters are the **3×3 block of keys centred on the key that
was struck, clamped to the keys that exist.**

Clamped, not padded. There is no row above `q` and no column left of `a`, so a corner tap
legitimately has four neighbours and an edge tap six. Nine is the interior case, not a
guarantee, and code that assumes nine is wrong at the edges of every keyboard.

Within each row of the block, the column is the key nearest the tap **in x**, found by
position rather than by arithmetic on indices — the rows are offset by half a pitch, so the
key above `s` is not the key with the same index.

An entry is rejected outright if any of its letters falls outside the corresponding
neighbourhood. That rejection is what keeps the search cheap.

### 5.3 The search

The lexicon is a trie over `tapForm`. Matching walks it one tap at a time, extending each
live node only along edges whose letter is in that tap's neighbourhood, and accumulating
cost. Nodes are dropped when their partial cost exceeds a ceiling or when the live set
exceeds the beam width. At depth n, the terminal live nodes are the candidates.

Cost is O(n × beam × 9), with no data-dependent blowup: no backtracking, no probability
mass to normalize, nothing that behaves differently on a second run. The claim is owed a
measurement rather than a re-reading, and section 9 records it.

**Dropped and doubled taps are forgiven**, because that is what fast thumbs on glass
produce. They are not a second matcher; they are two more transitions in the same search:

- an **omission** follows a trie edge without consuming a tap — a letter the user missed;
- an **insertion** consumes a tap without following an edge — a tap that was a stray.

Both cost a penalty expressed in the same normalized key units as the distances, so a slip
competes against sloppiness on one scale rather than two.

### 5.4 Ranking

Sort ascending by score. Ties break in two steps, and neither is discovery order:

1. **The entry that changes nothing wins.** Where `well` and `we'll` fit a tap sequence
   equally, the plain word takes the middle bubble and the contraction takes the right-hand
   one. A keyboard whose stated virtue is predictability should not reach for an apostrophe
   on a coin toss.
2. **Then lexicographic order of `insertion`**, which makes the ordering total.

Never insertion order, never hash order. A ranking that depends on how a dictionary
happened to enumerate is not mechanistically predictable, however deterministic its
individual scores are.

**Frequency weighting, when it arrives**, is one additive term on the same score:

    S' = S + λ · penalty( frequency(entry) )

with λ = 0 giving exactly today's equal weighting. That is the whole of the change, and it
is why the interface is "tap sequence → ranked candidates" with the scorer behind it.

**Where this sits relative to published work.** The literature on touchscreen keyboard
decoding is Bayesian: the probability of a word given a tap sequence is a spatial
likelihood — how well the touches fit the keys — times a language-model prior — how likely
that word was to begin with. KeyBored is that decoder with a **flat prior**. Every word is
equally likely a priori and only the geometry speaks. The restriction is deliberate rather
than unfinished, and frequency weighting is the prior returning rather than a feature
bolted on. *(This framing is second-hand — from a survey of search summaries, not of full
papers — and should be checked against primary sources before this document is cited for
it.)*

**Under a flat prior, the size of the word list is the weighting.** This is why the bundled
list is 19,217 words rather than the 41,000 or 82,000 available under the same licence, and
why it is not a placeholder awaiting a bigger one. With every word weighted equally, each
additional obscure entry is one more equal competitor for the same taps: a larger list does
not make the keyboard know more, it makes it less sure. Growing the list is something
frequency weighting earns.

### 5.5 Constants

These are the specification, not implementation detail. Each is a decision, and the ones
that are starting values rather than measurements say so.

    neighbourhood            3 rows × 3 columns, clamped to existing keys
    omission penalty         1.5 normalized key units       starting value
    insertion penalty        1.5 normalized key units       starting value
    maximum edits per word   1
    beam width               256
    correction slack per tap 0.5 normalized key units       starting value

**One edit per word**, not two: two multiplies the reachable words far faster than it adds
words anybody meant, and every word it adds is one the bar might offer.

**Correction slack of half a key per letter** is the threshold the commit rule needs and
the one number in this document with the least behind it. It is the first thing to tune
against real typing.

---

## 6. The candidate bar and the commit rule

### 6.1 The three slots

    left    the literal — the nearest letter per tap, in order, unchanged
    middle  the best candidate
    right   the second best candidate

**The literal** is computed per tap, independently, with no lexicon involved. It is always
available, always cheap, and always exactly what the fingers did — the ground truth against
which the other two slots are proposals. It is also the fallback for every case the matcher
declines: no candidates, too many taps, a plane the matcher does not run on.

**If the best candidate equals the literal**, it is not shown twice: the literal slides into
the middle slot, where the eye already is, and the runner-up takes the right.

**A slot with nothing to show is empty.** It never falls back to filler.

**Before the first tap of a word, all three slots are empty, and that is a decision.** All
three are functions of the taps — the left one *is* the taps, the other two are the
matcher's answer to them — so with no taps there is no question to answer. The bar could
instead be pre-filled with common words, but under the flat prior of section 5.4 there is
no such thing as a likelier word: every entry ties, so anything shown there would be an
arbitrary three chosen by the trie's iteration order and presented as a prediction.
Frequency weighting is exactly what would make a pre-tap bar meaningful. Until then, an
empty strip is the honest render.

**The left slot is drawn in typographic quotes and the other two are bare.** The quotes are
how the strip distinguishes "this is exactly what you typed" from "this is a word I know".
Without them the three slots read as three dictionary words, one of which happens to be
misspelled, and the left slot's purpose — a visible escape hatch — stops being legible.

The quotes are presentation and nothing else. The literal value holds bare characters,
tapping the bubble inserts bare characters, and both halves are tested. A decoration that
could reach the text field would be a defect.

**Tapping any bubble** commits that text and suppresses correction for that word.

### 6.2 Casing

The matcher works in lowercase: `Don't` and `don't` are one constellation, and splitting
them would double the lexicon to say nothing.

But a commit rewrites text that is already in the field, so casing has to be carried
alongside the taps or the first word of every sentence silently loses its capital. The word
in progress records whether shift was down for its first tap and re-applies that to whatever
is committed — correction or tapped bubble alike — and the bar is cased the same way, so
each bubble shows exactly the text that tapping it inserts.

**First letter only.** A correction can be a different length from the taps that produced
it (`dont` is four taps, `don't` is five characters), so **there is no honest per-tap
mapping** and none is invented.

### 6.3 What a word boundary commits

Neither "always correct" nor "only when tapped". A boundary chooses, and what it chooses on
is how far the typing sits from the word:

    literalCost = Σᵢ distance from tapᵢ to the key it actually struck
    slack       = literalCost + correctionSlackPerTap × tapCount
    commit the correction when bestCandidate.cost ≤ slack, otherwise the literal

`literalCost` is the intrinsic sloppiness of the typing, and comparing against it rather
than against zero is what makes the rule fair in both directions. Someone typing carelessly
does not thereby lose their corrections; someone typing precisely does not have one forced
on them.

A word typed sloppily but unambiguously has a best match barely worse than its own literal,
and corrects. A name, an abbreviation or a password has a best match far worse than its
literal, and stands. That second case is the one a daily driver cannot get wrong.

---

## 7. The lexicon

One trie, built at startup from five sources. There is no special-case path for any of
them; they differ only in `source`.

1. **Built-in dictionary.** The `3esl` list from 12dicts 6.0.2 — 19,217 words after
   filtering to plain lowercase entries — bundled at
   `Shared/Resources/12dicts-3esl-lowercase.txt`. **Public domain**, in its author's own
   words read from the distribution rather than from a summary of it. The README beside the
   file carries the quotation, the acknowledgment its author asks for, and what was
   filtered out. Sized at 19k rather than 41k or 82k for the reason in section 5.4.

2. **Contractions.** `tapForm` without the apostrophe, `insertion` with it. A user who
   *does* type the apostrophe still gets the right result, because the apostrophe ends the
   word and the literal stands.

3. **Idioms.** `lol` and its neighbours: things people type often that are not words.

4. **Text replacements.** From `UILexicon`, via
   `UIInputViewController.requestSupplementaryLexicon(completion:)`. Apple's App Extension
   Programming Guide states this is available to every custom keyboard "independent of the
   value of its RequestsOpenAccess key", and it carries the user's Text Replacement
   shortcuts along with Address Book names and a common-words dictionary. So this
   integration costs no entitlement.

5. **User-added words.** Not built. A keyboard that learns is not mechanistically
   predictable unless what it learned is visible and editable, and sharing such a store
   between app and extension needs Full Access, which section 10 says nothing core may
   depend on. Open question 1 in section 10.

A trie node holds a **list** of entries rather than one, because two entries can share a
tap form: `well` and `we'll`, `its` and `it's`. Storing one would make the other
untypeable, and which one survived would depend on load order.

---

## 8. Invariants

Stated so they can be tested, and named so a test can cite the rule it is checking.

- **I1 — Determinism.** The same tap sequence, lexicon and geometry produce a
  byte-identical bar, within one process and across processes.
- **I2 — Total ordering.** Candidate ranking never depends on enumeration, insertion or
  hash order.
- **I3 — Neighbourhood well-formedness.** Never empty; never larger than the configured
  block; always ordered by cost.
- **I4 — The perfect constellation.** For every entry, feeding its own ideal constellation
  as taps ranks that entry first at cost zero. This is the algorithm's definition, and it
  catches geometry and normalization errors immediately.
- **I5 — The literal.** For any tap sequence, the left slot equals the per-tap nearest
  letter. Checkable as a property over random points inside the keyboard.
- **I6 — Geometry parity.** Built key rectangles match the measured stock proportions in
  Appendix A.
- **I7 — Reserved strip.** The first key row's top edge is the suggestion strip's height,
  regardless of whether the bar has content.
- **I8 — Presentation is not insertion.** What a bubble displays and what tapping it
  inserts differ only by presentation, never by content.
- **I9 — Casing agreement.** The text the bar shows is cased identically to the text a
  commit would insert, on both branches of the commit rule.
- **I10 — Non-words survive.** A tap sequence with no plausible candidate commits as its
  literal.
- **I11 — Bounded latency.** One match against the full lexicon completes well inside a
  keystroke interval. This is the measurement section 5.3's claim is owed.

### 8.1 A shared setup line is a shared blind spot

Recorded because it has already cost this project a bug, and because a count of tests will
not show it.

Every test of the commit rule opened by clearing the keyboard's initial auto-shift, because
lowercase assertions were easier to write. That one convenience line deleted the exact
condition under which the commit path was broken — a correction re-inserted the matcher's
lowercase output, so the first word of every sentence lost its capital. Eleven tests
covered the commit path and the real coverage of a capitalized commit was zero. A twelfth in
the same style would have widened nothing.

**A line repeated in the setup of every test in a group is not covered by any of them.**
When a convenience appears in every fixture, the state it removes is the state nothing is
checking, and the way to find out is to write one test *without* it rather than another
with it.

The test that caught it was not looking for it: it was proving that the left bubble's quotes
are drawn but never typed, and it typed the word the way a person starts a sentence — on a
fresh, shifted keyboard. Fixture realism is not decoration. It is what lets a test find
something nobody was looking for. Prefer fixtures that do what a person does over fixtures
that are convenient to assert against.

---

## 9. What exists, and what it was measured to do

**Routing lives in `Shared/`, not in the extension.** What a space commits, what delete
undoes and when a word ends is where a keyboard's real behaviour is; behind
`UIInputViewController` all of it would be reachable only by installing a keyboard and
typing on it by hand. The controller takes a two-method text destination instead, so the
extension, the container app's try-it surface and the tests all drive the same code. The
container app is not a mock-up: it runs the same controller and the same view.

    Shared/KeyboardGeometry.swift       stock metrics, geometry, hit-testing
    Shared/Lexicon.swift                lexicon entries, the trie
    Shared/ConstellationMatcher.swift   tuning, neighbourhoods, the beam search
    Shared/TypingSession.swift          word in progress, candidate bar, the commit rule
    Shared/EnglishLexicon.swift         loads the bundled list and the hand-held entries
    Shared/Resources/                   12dicts 3esl, 19,217 words, plus its provenance
    Shared/KeyboardController.swift     routing
    Shared/KeyboardView.swift           the keys, the preview bubble, the bar
    KeyBoredKeyboard/KeyboardViewController.swift  UIKit plumbing, and nothing else
    KeyBored/ContentView.swift          the container app's try-it surface
    KeyBored/AppIcon.icon               Icon Composer document, five flat layers
    KeyBoredTests/MatcherTests.swift    the matcher, by invariant
    KeyBoredTests/KeyboardControllerTests.swift  the routing, end to end
    KeyBoredTests/KeyboardViewTests.swift        what the keyboard draws, not just computes

Measured behaviour, from the tests rather than from reading the code:

- Geometry lands within 1.5px of every measured value in Appendix A at 430pt. *(I6)*
- A word's own perfect constellation ranks it first at cost zero. *(I4)*
- `hello` typed with every tap a third of a key right and a quarter low still ranks `hello`
  first.
- `helo` and `helllo` both reach `hello` through one edit.
- `dont` predicts and commits `don't`; `well` commits unchanged; `xkqjv` is left alone.
  *(I10)*
- On a fresh, shifted keyboard `dont` commits as `Don't`; after shift is cleared, as
  `don't`. *(I9)*
- After typing `dont` on a fresh keyboard the three bubbles read “Dont”, Don't and Font —
  asserted off the rendered buttons, and rendered to a PNG by the same test so it can be
  checked by eye. *(I8)*
- The same taps give the same answer across eight fresh matchers. *(I1)*
- Shift starts on and releases after one letter; delete walks the word back a tap at a
  time; switching to the digits plane ends the word and types literally.
- One match against the full 19,217-word lexicon runs in under 20ms on a simulator. *(I11)*

**Three scaffold defects were found by running rather than by reading**, all fixed: the
test target had no `Info.plist` and could not code sign; neither the app nor the extension
generated the standard bundle keys, so the app built and could not install; and the
extension had no `CFBundleDisplayName`, which the installer refuses. A build that succeeds
is not an app that runs.

---

## 10. Targets, entitlements, distribution

    KeyBored/            container app, com.tg-techie.app.keybored
    KeyBoredKeyboard/    extension,     com.tg-techie.app.keybored.keyboard
    Shared/              compiled into app, extension and tests
    KeyBoredTests/       swift-testing

Deployment target iOS 26.0; Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`. The project
tracks no `DEVELOPMENT_TEAM`: a signing identity belongs to whoever is building, not to the
repository. `RELEASING.md` carries the archive and distribution procedure.

**The project is KeyBored and the shipped app is BoreKey.** Everything above — targets,
directories, bundle identifiers, the App Store Connect SKU — is KeyBored, and none of it is
user-visible. BoreKey is the name a person reads: the app on the home screen, and the
keyboard in Settings and on the globe key. The two are separate namespaces and a bundle
identifier is permanent once a store record exists, so they are not kept in step. The brand
is written once, as `PRODUCT_DISPLAY_NAME` in `project.yml`, feeds
`INFOPLIST_KEY_CFBundleDisplayName` for all three targets, and is read back off the bundle
by `Branding` — the same arrangement `KeyBoredVersion` uses for `MARKETING_VERSION`, so that
neither `Info.plist` carries a literal copy.

**Full Access (`RequestsOpenAccess`) is off, and what that costs is specific.** From
Apple's App Extension Programming Guide, a keyboard without it cannot share a container
with its containing app, cannot use `UIPasteboard`, and cannot play keyboard clicks via
`playInputClick`. It *can* use `UILexicon`. So:

- text replacements need no Full Access;
- the keyboard click sound does;
- any setting the host app writes and the keyboard reads does, being a shared container;
- a learned-words store shared with the host app does.

Full Access may therefore be requested, but **nothing core may sit behind it**. The
matcher, the lexicon, the geometry and the bar all run without it; the click sound and any
host-app setting degrade when it is off rather than breaking. An app group is worth adding
only in the same breath as Full Access, since without it the group buys nothing.

### Open

1. **Does the keyboard learn words you type?** A keyboard that adapts is not mechanistically
   predictable unless what it learned is visible and editable, and storing it across app and
   extension needs Full Access. This is a question about what kind of product KeyBored is,
   and it is unresolved.

### Decided, and reversible

Each of these was decided rather than deferred. Any can be overturned; the reasoning is
here so that overturning one is an argument rather than a guess.

2. **The word list is 12dicts `3esl`, public domain, 19,217 words.** Its author released
   12dicts to the public domain, so nothing ships with the binary. The frequency-ordered
   `2+2+3frq` list is **not** usable until AGID's terms are established: its `agid.txt`
   carries a bare copyright line and no grant of permission at all, and a licence is not
   something to infer.
3. **`project.yml` and xcodegen stay.** Two targets and a test bundle share a source root,
   which is where a generated project earns its keep. Cheaper to drop later than to add
   later.
4. **No keystroke leaves the device, ever.** A floor, and it also keeps the App Store
   networked-keyboard guidelines out of the picture.
5. **Correction slack is 0.5 normalized key units per tap.** A starting value.
6. **One edit forgiven per word.**
7. **The bar is empty until the first tap of a word.**
8. **A tie prefers the entry that changes nothing.**

---

## Appendix A — measured stock geometry

Measured 2026-09-05 from a screenshot of the stock iOS keyboard on an iPhone 15 Pro Max, by
thresholding key caps at RGB > 246 and scanning for runs of light pixels. The screenshot is
not in this repository; the numbers below are the part of it that mattered.

**This is a screenshot, not a device measurement.** The proportions are real; the absolute
point values are derived by dividing by 3 and still want checking against a simulator or a
device. The tests assert the built geometry against the pixel figures below, so the
relationship can be re-derived without the image.

Device: iPhone 15 Pro Max, 1290 × 2796 px, @3x, so 430 × 932 pt.

Pixels, as measured:

    keyboard plate top edge          y = 1807 (hairline separator at 1805–1806)
    suggestion strip                 y = 1807 … 1910          height 104
    row 1  Q W E R T Y U I O P       y = 1911 … 2045          height 135
    row 2  A S D F G H J K L         y = 2079 … 2213          height 135
    row 3  ⇧ Z X C V B N M ⌫         y = 2247 … 2381          height 135
    row 4  123 space return          y = 2415 … 2549          height 135
    row pitch                        168          vertical gap 33
    key width, letter rows           108          column pitch 126, gap 18
    left margin 20, right margin 19
    row 2 is offset by half a column pitch: first key left edge x = 84
    shift 144 wide, delete 145 wide
    123 = 299 wide, space = 615 wide, return = 300 wide

Derived points (÷3), to be verified before use:

    key 36.0 × 45.0        column pitch 42.0      row pitch 56.0
    horizontal gap 6.0     vertical gap 11.0      side margin ≈ 6.5
    shift / delete 48.0    123 ≈ 99.7   space ≈ 205.0   return ≈ 100.0
    suggestion strip ≈ 34.7

The measurement script was scratch and is not kept. The numbers above are the record, and
the geometry tests check the code against them on every run, which is a stronger guarantee
than a retained script would be.

## Appendix B — sources

- Ken Kocienda, *Creative Selection* — the origin of the constellation method.
- Apple, App Extension Programming Guide, "Custom Keyboard":
  <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html>
  — the Full Access facts in section 10 and the `UILexicon` fact in section 7.
- Apple, `requestSupplementaryLexicon(completion:)`:
  <https://developer.apple.com/documentation/uikit/uiinputviewcontroller/requestsupplementarylexicon(completion:)>
- 12dicts 6.0.2, Alan Beale, `http://downloads.sourceforge.net/wordlist/12dicts-6.0.2.zip`
  — the bundled word list and its public-domain statement; see
  `Shared/Resources/README.md`.

## What is not verified

- **The Apple documentation cited is the archived Extensibility guide.** It is the
  authoritative statement of the Full Access rules but predates recent iOS releases. The
  `UILexicon` claim is corroborated by the current API reference; the shared-container claim
  is not, and should be confirmed against current documentation before Full Access is either
  taken or refused on the strength of it.
- **The point values in Appendix A come from a screenshot**, not from a running keyboard.
- **The prior-art framing in section 5.4 is second-hand**, from a survey of search summaries
  rather than of full papers.
- **Latency was measured on a simulator**, not on a device.
