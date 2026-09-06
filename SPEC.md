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

The system as a whole is a plane, a shift state, and a word in progress. Everything else is
derived. `A` below is the auto-capitalization of section 3.4 — a fact read out of the field,
not a remembered one — and `s` is one of `off`, `oneShot` and `locked`.

    (plane, s, word)  --letter tap on letters plane-->  (plane, s = oneShot ? off : s, word + tap)
    (plane, s, word)  --letter tap on other plane-->    (plane, s, ∅)         text inserted as struck
    (plane, s, word)  --space / return-->               (plane, A(s), ∅)      commit, then separator
    (plane, s, word)  --delete-->                       (plane, word−1 empty ? A(s) : s, word − last tap)
    (plane, s, word)  --shift, within 0.3s of the last shift-->  (plane, locked, word)
    (plane, s, word)  --shift, otherwise-->             (plane, s = off ? oneShot : off, word)
    (plane, s, word)  --plane switch to p-->            (p, s, ∅)
    (plane, s, word)  --bubble tap-->                   (plane, A(s), ∅)      chosen text inserted
    (plane, s, word)  --host changed the field-->       (plane, A(s), ∅ or word)  see 3.4

`A(s)` is `s` itself when `s` is `locked`, and the field's auto-capitalization otherwise: a
latch is the user's and no boundary clears it. A field asking for `.allCharacters` produces
`locked` directly, which is the same state under a different cause and is why nothing in the
letter path has to special-case that field any more.

Three of those are the load-bearing ones.

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

**A shift that is on but not one of the two ways of being on.** `ShiftState` has three
cases and no flag beside them. This was a `Bool` until 2026-09-05, and the state it could
not hold was caps lock: `off` and `oneShot` both mean "not latched", `oneShot` and `locked`
both mean "shifted", and neither pair collapses without losing the other distinction — so a
double tap on shift undid the first tap instead of latching, and the drawn key could not
tell the two shifted states apart either.

### 3.4 Auto-capitalization is read, never remembered

The shift flag is one bit, and there are two quite different things it can mean: *the user
pressed shift*, and *the cursor is at the start of a sentence*. Only the first is the
keyboard's own state. The second is a fact about the field, and the field can change without
the keyboard touching it.

So at every point where the shift state is the keyboard's to decide — a word boundary, a
delete back to nothing, a change the host made — it is recomputed by asking the document what
precedes the insertion point. `TextDocument.textBeforeInput` is that question;
`UITextDocumentProxy.documentContextBeforeInput` is the answer in the extension. Nothing
before the cursor, a newline, or a terminator followed by a space, all begin a sentence. A
terminator with no space after it does not, so `Dr.` mid-sentence stays mid-sentence.

Pressing shift is untouched by any of this. It is the user's, and it is one-shot: it applies
to the next letter and releases.

**Why it is written down as a rule rather than as a fix.** The flag was initialized `true`
once at construction and thereafter only ever toggled by the shift key. That is
indistinguishable from correct behaviour until something outside the keyboard edits the
field — and then it is silently wrong for the rest of the session. Found on 2026-09-05 by
clearing Safari's find field with the app's own clear button and typing: `hi there`, where
the stock keyboard gives `Hi there`.

The host reports its own edits and the keyboard's through the same callback. They are told
apart by looking rather than by remembering: if the text before the cursor still ends with
the letters this keyboard believes it typed, the change was its own and the word in progress
survives. Otherwise the word is discarded, because it no longer describes anything on screen.

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

1. **Built-in dictionary.** The `2of12inf` list from 12dicts 6.0.2, unioned with the
   `3esl` list it replaced — 75,646 words after filtering to plain lowercase entries —
   bundled at `Shared/Resources/12dicts-2of12inf-lowercase.txt`. `2of12inf` is the core
   vocabulary **with its inflections**, which is the whole point: `3esl` had `edit` and not
   `editing`, `cat` and not `cats`. **Not public domain** — it derives from AGID, whose
   terms are permissive and require the acknowledgment the README beside the file carries,
   along with AGID's own sources' notices and what was filtered out. It was 19,217 words
   until 2026-09-06, for the reason in section 5.4; Appendix A.16 is why that changed and
   what had to change with it.

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
    Shared/Resources/                   12dicts 2of12inf, 75,646 words, plus provenance
    Shared/KeyboardController.swift     routing
    Shared/KeyboardView.swift           the keys, the preview bubble, the bar
    KeyBoredKeyboard/KeyboardViewController.swift  UIKit plumbing, and nothing else
    KeyBored/ContentView.swift          the container app's try-it surface
    KeyBored/AppIcon.icon               Icon Composer document, five flat layers
    KeyBoredTests/MatcherTests.swift    the matcher, by invariant
    KeyBoredTests/KeyboardControllerTests.swift  the routing, end to end
    KeyBoredTests/KeyboardViewTests.swift        what the keyboard draws, not just computes
    KeyBoredTests/StockLikenessTests.swift       geometry and colour against Appendix A

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
- Two taps on shift inside 0.3s latch it, and the latch survives a space; two taps ten
  seconds apart do not latch; a tap on a latched shift releases it without relatching.
- Each of the three shift states draws a glyph, and all three glyphs resolve to an image
  on this SDK — the failure mode of a wrong symbol name is a blank key, not an error.
- Holding delete repeats it, waits before the first repeat, and stops on release.
- Every command cap answers to a touch anywhere inside it, not only at its centre.
- Emptying the field from outside the keyboard re-arms the capital, and the keyboard's own
  insertions do not disturb the word in progress even though the host reports both the same
  way. Section 3.4.
- Every key cap and the candidate bar clear a 4.5:1 contrast ratio against the colour behind
  them, in both `UIUserInterfaceStyle`s.
- One match against the full 19,217-word lexicon runs in under 20ms on a simulator. *(I11)*

**Five defects were found by running rather than by reading**, all fixed. Three in the
scaffold: the test target had no `Info.plist` and could not code sign; neither the app nor
the extension generated the standard bundle keys, so the app built and could not install;
and the extension had no `CFBundleDisplayName`, which the installer refuses.

Two more got past all of that and reached TestFlight, because a green build and a passing
suite say nothing about either:

- **The letter keys rendered blank in dark appearance.** `KeyCap.label` inherited `.label`,
  which is white, on caps hard-coded white. The whole palette is now dynamic, with the dark
  values sampled from a screenshot of the stock keyboard rather than chosen.
- **Typing inserted nothing into a host app.** `KeyboardController` held its `TextDocument`
  weakly and both hosts construct their adapter inline, so it was deallocated the instant
  `init` returned. Forty tests passed because each held its fake document in a local for the
  length of the test — an ownership no real host has. `HostIntegrationTests` now builds its
  document the way a host does.

A build that succeeds is not an app that runs, and an app that runs is not a keyboard that
types. `RELEASING.md` makes typing with it on a simulator a required step before an upload.

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

9. **Stock's caps are slightly translucent and these were painted. Both halves are now
   done, and neither needed the structural change this entry expected.** The plate: an
   `UIInputViewController`'s `view` already *is* a `UIInputView` drawing the keyboard
   material, so the fix was to stop painting over it, and the plate is byte-identical to
   stock on every backdrop measured. The caps: a wash can be identified from two states
   without knowing which effect style draws it, and `a = 0.25` over `#AFAFAF` predicts all
   six measured channels. The dark cap is now exact over a black-backed host and one unit
   low over Safari, against three units before. A.11 has the numbers, the residual, and
   the reason light stays opaque white.
10. **Delete repeats but does not accelerate.** Stock waits about four tenths of a second,
    repeats about ten times a second, and after a few seconds starts taking whole words.
    This does the first two. The third has not been timed off a stock keyboard, and
    guessing when it kicks in would be guessing.
11. **The caps-lock window is 0.3s and it was not measured.** It is the conventional
    double-tap interval, not a number read off stock. `KeyboardController.capsLockWindow`.
12. **The globe's long press has never been seen working.** It is wired the way Apple
    documents — an invisible `UIControl` over the cap with
    `handleInputModeList(from:with:)` on it — and nothing has raised the keyboard list on
    a screen yet. Appendix A.8 says why a script cannot press it.
13. **Seven of the ten return-key types have never been put in front of a stock keyboard.**
    `.go` and `.search` draw measured glyphs; `.default` draws a measured `↵`. The other
    seven draw their words, because a symbol name that looks right in the source is not
    evidence. Appendix A.5.

1. **Does the keyboard learn words you type?** A keyboard that adapts is not mechanistically
   predictable unless what it learned is visible and editable, and storing it across app and
   extension needs Full Access. This is a question about what kind of product KeyBored is,
   and it is unresolved.

### Decided, and reversible

Each of these was decided rather than deferred. Any can be overturned; the reasoning is
here so that overturning one is an argument rather than a guess.

2. **The word list is 12dicts `2of12inf`, 75,646 words, and it is not public domain.**
   It derives from AGID, and `agid.txt` does carry a grant of permission — two thirds of
   the way down, under a heading of its own. This entry said the opposite until
   2026-09-06, on a reading that stopped at the copyright line near the top, and it said
   the frequency-ordered `2+2+3frq` list was unusable for that reason. It is not unusable;
   it is available on the same terms as the list now bundled. The acknowledgments AGID and
   its sources require travel in `Shared/Resources/README.md`.
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

## 11. The system keyboard API, and what this keyboard does by hand

Read on 2026-09-05 out of the iOS 26.5 SDK headers on this machine, not out of the archived
Extensibility guide Appendix B cites and not out of anyone's recollection of UIKit:

    $(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/UIKit.framework/Headers/
      UIInputViewController.h   UIInputView.h   UITextInputTraits.h   UITextInput.h   UILexicon.h

Headers rather than the documentation website because they carry the exact declarations and
the availability annotations, and because they are the version this project actually links
against. Where a claim below is about behaviour rather than about a declaration, it says so.

The survey exists because everything in sections 4 and 9 was derived by measuring a
screenshot. Measuring is how the geometry got right; it is also why the keyboard drew a
plate colour it could have been handed and inferred a capital the field would have told it.

### 11.1 The inheritance nobody had looked up

`UITextDocumentProxy` inherits `UIKeyInput`, and `UIKeyInput` inherits `UITextInputTraits`:

    @protocol UITextDocumentProxy <UIKeyInput>
    @protocol UIKeyInput <UITextInputTraits>

So the field being typed into can be asked what it wants, through the proxy this keyboard
already holds. **Every member of `UITextInputTraits` is `@optional`**, which Swift imports as
an optional: `proxy.keyboardAppearance` has type `UIKeyboardAppearance?`, not
`UIKeyboardAppearance`. A `nil` is a real outcome and not an error, so each of these needs a
stated fallback rather than a `!`. Verified by type-checking against the iOS 26.0 target.

### 11.2 What the system offers, and what this keyboard was doing instead

| API | This keyboard, before the survey | Decision |
|---|---|---|
| `keyboardAppearance` | drew from `traitCollection.userInterfaceStyle` | **proposed, implemented, and rejected by measurement.** See 11.3. The trait collection keeps the decision. |
| `autocapitalizationType` | inferred `.sentences` by reading text back (§3.4) | the field's declared intent leads; the read-back is how `.sentences` is *implemented*, and `.none`, `.words` and `.allCharacters` are its own answers. |
| `returnKeyType` | the word "return", always | label from the type: Go, Search, Send, Done, Next, Join, Continue. |
| `keyboardType` | QWERTY, always | a field asking for `.numberPad` and getting letters is a correctness bug. At minimum open on the digits plane for the numeric types; a real number pad is out of scope and recorded as such. |
| `isSecureTextEntry` | ignored | **the candidate bar would print a password in 40pt type.** Nothing is stored — PRIVACY.md still holds — but it is on screen. The bar is suppressed for a secure field. |
| `enablesReturnKeyAutomatically` | ignored | return is disabled while the document is empty. |
| `selectedText` (iOS 11) | ignored | a selection means the next insert replaces it, so the word in progress no longer describes the field. |
| `documentIdentifier` (iOS 11) | ignored | changes when the host moves to a *different field*, which is the one thing §3.4's suffix comparison cannot detect at all — it compares text, and two fields can hold the same text. It complements that check rather than replacing it. Recorded, not yet used. |
| `documentInputMode` (iOS 10) | ignored | the field's own language. Recorded, not used: the lexicon is English-only. |
| `setMarkedText:selectedRange:` / `unmarkText` (iOS 13) | ignored | provisional text, underlined, replaced on commit — the mechanism a prediction could use instead of insert-then-delete. Out of scope for now, recorded because §6.3's delete-and-reinsert is the thing it would replace. |
| `hasText` (UIKeyInput) | ignored | cheaper than reading the context back. |
| `adjustTextPositionByCharacterOffset:` | ignored | no cursor keys, so nothing needs it. |
| `UIInputView(frame:inputViewStyle:)` with `.keyboard` | **adopted, by deletion** | "mimics the keyboard background", per the header's own comment — and `UIInputViewController.view` already is one, so the keyboard was painting over the material rather than lacking it. `view.backgroundColor = .clear` is the whole adoption; the sampled colours stay as what the container app draws. A.11. |
| `UIInputView.allowsSelfSizing` (iOS 9) | a height constraint activated in `viewDidAppear` | the supported way to let autolayout size the input view. The workaround in `KeyboardViewController` exists because nobody had read this. |
| `handleInputModeListFromView:withEvent:` (iOS 10) | `advanceToNextInputMode` only | that is a tap; this is the long press that shows the keyboard list. Both, as the stock globe key does. |
| `hasDictationKey` | ignored | whether the host wants a dictation key drawn. |
| `hasFullAccess` (iOS 11) | ignored | this keyboard requires none; asserting it is how PRIVACY.md's claim gets a runtime check rather than a promise. |
| `needsInputModeSwitchKey` | used, correctly | unchanged. |
| `primaryLanguage`, `dismissKeyboard` | ignored | recorded; neither is needed yet. |
| `requestSupplementaryLexiconWithCompletion:` / `UILexicon` | named in `Shared/Lexicon.swift`, not called | the user's own text shortcuts. A real feature and its own piece of work. |

### 11.3 The proposal the measurement rejected

`keyboardAppearance` is the field's own statement of which appearance the keyboard should
draw, and reading it instead of the view's trait collection looked like a plain correction:
they are different questions, and a light app can legitimately want a dark keyboard.

It was implemented, and it turned the keyboard white inside a black app.

Measured on a simulator in dark mode, 2026-09-05, in Safari's address bar:

    textDocumentProxy.keyboardAppearance   = Optional(2)   // .light
    traitCollection.userInterfaceStyle     = 2             // .dark

and a screenshot of **the stock keyboard in that same field**, taken minutes later by
switching to it with the globe: dark. So the field says `.light`, and Apple's own keyboard
does not obey it.

The reading, and it is a derivation: `.light` predates dark mode by six years, apps set it
once and never revisited it, and the system stopped treating it as authoritative. The trait
collection therefore keeps the decision, and `overrideUserInterfaceStyle` stays
`.unspecified` — which is where the code started, but now because it was checked rather than
because nobody had asked.

**Not established:** whether a field asking for `.dark` inside a light app is honoured by
stock. That is the case where the trait would carry real information, and no field doing it
has been found to test against. If one is, this is the paragraph to replace.

This section exists because the survey's value is not only the things it changed. A change
that looks obviously right, is cheap to make, and is wrong is exactly what a survey read out
of headers rather than out of behaviour produces — and the only thing that caught it was
putting the two keyboards side by side in the same field.

### 11.4 The 40 points of dead space, and where they came from

`StockMetrics.bottomRowHeight` reserved 47 points for "the row below `return` carrying the
globe key". There is no such row on the stock keyboard: iOS draws its own globe and dictation
strip *below* a custom keyboard's input view, and stock puts its emoji key **inside** row 4,
between `123` and the space bar. When `needsInputModeSwitchKey` is false the reserved row is
simply empty, which is what Jonah photographed on 2026-09-05.

Measured from that photograph against a stock keyboard in the same field, both at 3x:

    row 4 bottom to the keyboard's bottom     BoreKey 142px (47pt)    stock 22px (7.3pt)
    whole plate                               BoreKey 1110px (370pt)  stock 991px (330pt)
    cap height, row pitch, every cap x        identical within 1px
    plate top to row 1 top                    105px vs 106px

So the geometry was right and the total was 40 points too tall, all of it below the last row.
`bottomRowHeight` is replaced by a measured 22/3 points of bottom padding, and the globe key,
when the system asks for one, takes stock's emoji slot in row 4.

**A recorded divergence:** with no globe key needed, stock still shows an emoji key there and
this keyboard shows a wider `123`. Our `planeKeyWidthFraction` of 299/1290 is exactly stock's
`123` (140px) plus the 18px gap plus its emoji key (141px), so the slot is available. It is
left unfilled because switching to the emoji keyboard is an input-mode change, which only
`advanceToNextInputMode` and `handleInputModeList` can make and only when
`needsInputModeSwitchKey` is true. A key that looked like stock's and did nothing would be
worse than a wider `123`.

### 11.5 Also measured from the same pair of screenshots

    cap corner radius     stock 21px (7pt)      BoreKey 13px (4.3pt)
    space bar             stock blank, with a small dictation "A" at its right end
    return key            stock draws the glyph; this keyboard printed the word
    shift glyph           stock's is a heavier outlined arrow
    candidate bar         stock: dimmed text, hairline dividers, Siri and formatting
                          affordances at the ends; ours: three candidates at full glyph weight

The Siri and formatting affordances belong to the system and are not reproduced. The dimming,
the dividers and the slot alignment are what make the bar read as part of the keyboard, and
those are ours to match.

---

## Appendix A — measured stock geometry

Measured 2026-09-05 from a screenshot of the stock iOS keyboard on an iPhone 15 Pro Max, by
thresholding key caps at RGB > 246 and scanning for runs of light pixels. The screenshot is
not in this repository; the numbers below are the part of it that mattered.

**This was a screenshot, not a device measurement**, and it was the only one for a while.
Section A.3 is the pass that checked it against running stock keyboards on three simulator
sizes, and found the horizontal fractions right and one of the vertical numbers wrong. Where
the two disagree, A.3 wins and says why.

The tests assert the built geometry against the pixel figures below, so the relationship can
be re-derived without the image.

Device: iPhone 15 Pro Max, 1290 × 2796 px, @3x, so 430 × 932 pt.

Pixels, as measured:

    keyboard plate top edge          y = 1807 (hairline separator at 1805–1806)
    suggestion strip                 y = 1807 … 1910          height 104   (but see A.3:
                                     the strip is 156, and 52 of it is the band iOS draws
                                     above a custom keyboard's own input view)
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

### A.2 — the number and symbol planes

Measured 2026-09-05 off the stock English keyboard in Safari's URL field on an iPhone 17 Pro
simulator, captured with `xcrun simctl io booted screenshot` at 1206 × 2622 px, @3x, so
402 pt wide. A different device from the measurements above, so the pixel figures are not
directly comparable with them — the proportions are, and they agree.

The characters, which are the part that was wrong:

    numbers  1 2 3 4 5 6 7 8 9 0
             - / : ; ( ) $ & @ "          ← the closing quote
             #+=  . , ? ! '  ⌫
             ABC  space  return

    symbols  [ ] { } # % ^ * + =
             _ \ | ~ < > € £ ¥ •          ← the bullet, U+2022
             123  . , ? ! '  ⌫
             ABC  space  return

Both second rows are **ten** keys, and both land on the same grid as the row above them —
neither is inset by half a column pitch the way the letters plane's `asdfghjkl` is. KeyBored
0.0.3 shipped nine glyphs in each, and the missing tenth is what pushed the row into the
letters plane's offset.

Pixels, as measured, identical on both planes:

    row 0   10 caps   x 20-119, 138-238, … 1086-1186     width 100/101, pitch 118.5
    row 1   10 caps   x 20-119, 138-238, … 1086-1186     identical to row 0
    row 2    7 caps   #+= 20-155 (136), five of 148 running x 197-344 … 861-1008,
                      ⌫ 1050-1186 (137)
    row 3    3 caps   ABC 20-297 (278), space 316-889 (574), return 908-1186 (279)

The five punctuation caps are not on the letter grid. They occupy **exactly** the span the
letters plane's `z`…`m` occupy in the same capture — x 197 to 1008, 812 px — divided five
ways instead of seven, which is where the 148 px comes from against a letter's 101. That
span is `7 × keyWidth + 6 × gap`, and stating it that way is what the geometry does, so the
three planes cannot drift apart.

Row 3 carries no emoji key here because a custom keyboard is installed, so iOS draws its own
globe and dictation strip below the keyboard and stock drops the slot. That is the same
observation as section 11.4, arriving from the other side.

Thresholding under-reports a cap by a pixel or so at each edge, because the antialiased
rounded corner falls below the cut. The figures above are the raw scan; the tests assert the
computed geometry, which comes out about 1.5 px wider on each cap and is not a disagreement.

### A.3 — the vertical metrics, checked against three running simulators

Everything above came off one screenshot of one phone. On 2026-09-05 the stock keyboard was
put in a Contacts search field on three simulators and measured the same way, to find out
which of those numbers were properties of the keyboard and which were properties of that
phone.

    device              width    cap height    row pitch    strip    row 0 top
    iPhone 17e          390 pt      129 px       162 px     156 px     1683
    iPhone 17 Pro       402 pt      129 px       162 px     156 px     1773
    iPhone 17 Pro Max   440 pt      135 px       168 px     156 px     1989
    (Appendix A above)  430 pt      135 px       168 px       —          —

Three findings, and the third is the one that cost the afternoon.

**The horizontal fractions are right.** Every one of them lands within about a pixel and a
half at all three widths, which is the width of the antialiased cap edge the threshold does
not count. Side margin 20, column gap 18, shift 144, delete 145, `123` 299, return 300, all
over 1290 — they scale.

**The gap between rows and the strip above them are constants**, 33px and 156px, identical
on all three. So "vertical values are in points, not fractions" holds for those.

**The cap height is not one number.** It is 129px on the two smaller phones and 135px on the
larger one, and the 135 in Appendix A was measured on a 430pt phone and written down as
though it were universal. It is 6px per row too tall on anything narrower, which is 24px of
keyboard, and it is why this keyboard read as slightly oversized in every side-by-side taken
on a simulator. `StockMetrics.rowHeight(forWidth:)` now carries both values.

**The boundary between them is a guess.** Nothing was measured between 402pt and 430pt. The
code puts it at 414, which is the width of the older Plus and Max phones and so the same
class boundary Apple has drawn before. A device in that gap would settle it.

**The strip is 156px, not 104.** The 104 in Appendix A is the part of it a custom keyboard
draws inside its own input view. iOS draws the other 52 above that view, and measuring only
our half is what put the first key row too high.

**Thirteen pixels at the bottom are not available.** Stock's plate runs y 1617–2410 on the
402pt simulator. A custom keyboard's input view has its bottom pinned at 2397 whatever
height it asks for: 765 put its top at 1632, 793 put its top at 1604, and both ended at
2397. iOS keeps those 13px for its own globe and dictation strip; stock's plate simply draws
over them. So this keyboard asks for stock's height less 13, which puts all four key rows
exactly on stock's and gives up the bottom sliver of plate instead. `systemBottomInset` in
`KeyboardViewController` is that number, and it was measured on one device only.

### A.4 — the palette, measured in the same capture as the thing it is compared to

A colour read out of one screenshot and rendered back through another pipeline is not a
measurement of a difference: the two pipelines differ by a few units on their own. The stock
column below was sampled with `pick.swift` out of `xcrun simctl io screenshot` captures of a
stock keyboard, in Safari and in Contacts, on the iPhone 17 Pro simulator. Our own render
reads back byte-exact through the same capture path, so a difference against this column is
a real difference and not the pipeline. The 0.0.3 column is not a measurement at all — it is
the constant that shipped, read out of `git show 48d00d2:Shared/KeyboardView.swift` and
converted to hex, which is why it is exact.

    dark               stock       KeyBored 0.0.3 as shipped
    plate              #1B1B1D     #1F1F1F
    every cap          #404041     #434343
    action return      #007AFF     — no action fill at all
    bar rules          #323234     — 0.0.3 drew no rules at all

    light              stock       KeyBored 0.0.3 as shipped
    plate              #DFE0E6     #D1D6DB
    letter cap         #FFFFFF     #FFFFFF
    command cap        #FFFFFF     #ABB3BD
    action return      #007AFF     — no action fill at all

    light bar rule     #B8B8B8     — 0.0.3 drew no rules at all

The bar rules are 3px wide and 72px tall in both appearances, measured in an empty Contacts
search field: dark draws them at x 399–401, light at x 400–402, and in the light capture the
rule runs y 1659–1730, which is 72 rows exactly. The light grey `#B8B8B8` had been chosen
before it was measured and turned out to be the right value; it is now a reading.

The light capture also settles the cap question directly rather than by inference from the
dark one. In `lt-c2.png` the `Q` cap, the shift cap, the delete cap, the `123` cap and the
space bar all read `#FFFFFF`, and the return key reads `#007AFF`.

**There is one cap colour, and iOS 26 uses it for every key.** Not just in dark, where that
had already been noticed, but in light too — shift, delete, `123` and the space bar are the
same white as a letter. The `letterKeyColor` / `commandKeyColor` pair carried the older iOS
arrangement and has been collapsed into `capColor`, because two names for one colour is an
invitation to re-diverge them.

**The return key is the exception, and it is blue in both appearances.** `#007AFF` exactly,
which is `systemBlue`'s light value; stock does not switch to the dark one.

**Stock's caps are slightly translucent and ours are not.** The same stock cap read `#404041`
over Safari and `#3D3D3D` over the black Contacts list. This is recorded and not fixed: the
values above are the Safari ones, and matching the material properly means drawing on a
`UIInputView` with the `.keyboard` style rather than on a painted plate. Section 10 carries
it as an open question.

**And so is the plate, which makes every stock number in this table a reading rather than a
constant.** A.11 measures the light plate moving from `#E1E3E6` to `#E2E4E8` under one
keyboard in one field when only the content behind it changed. The `#DFE0E6` above is a true
reading of the backdrop it was taken over and is what ships; it is not a value stock holds
still at. Read A.11 before treating any row here as a target to hit exactly.

### A.5 — what stock draws on the return key

iOS 26 draws glyphs where earlier iOS drew words, and two of them were measured directly:

    field                          returnKeyType    stock draws
    Safari address bar             .go              a right arrow, white on #007AFF
    Contacts search field          .search          a magnifier, white on #007AFF
    an ordinary text field         .default         ↵, on the ordinary cap colour

The other seven cases of `UIReturnKeyType` were not put in front of a stock keyboard, so the
keyboard draws their words on the blue cap and `KeyboardView.returnKeySymbol` says plainly
that guessing a symbol name for them is the kind of thing that looks right in the source and
wrong on a phone.

**Stock does dim the action key, and neither of the two earlier notes had the rule.**
The first said it dims on an empty field; the second retracted that, because going back
deliberately read `#007AFF` on an empty Contacts field in both appearances, and Safari's
`.go` key read `#007AFF` with `https://example.com` in the bar and after clearing it. The
retraction attributed the grey to a frame of the presentation animation. Both notes were
fitting a rule to one variable while a second one moved unwatched: the state is a latch on
whether anything has been typed since the keyboard was presented, so an empty field reads
grey on a fresh presentation and blue once you have typed and deleted. The early capture
`c3.png` was correct, and its `#747474` is the exact value A.13 measures. **A.13 has the
four states, the four colours and what the keyboard now does with them.**


### A.6 — the cap itself, ours beside stock in one pipeline

The two earlier findings about the cap — that stock's corner is 22px against our 16 or 17,
and that stock's cap is translucent where ours is opaque — both came from comparing a stock
screenshot against a render measured with a different threshold. Redone properly, with the
same tool, the same cut, the same appearance and the same host app, they do not survive.

Stock is `dk-c3.png`: Contacts, dark, stock keyboard. Ours is `app-dk1.png`: the container
app drawing the same `KeyboardView`, dark, minutes later. Both `xcrun simctl io screenshot`
on the iPhone 17 Pro simulator. The `Q` cap, flooded from a point inside it at a luminance
cut of 45:

    measurement                     stock          KeyBored
    cap box                         101 x 127      101 x 127
    left-edge inset at dy 0..15     13 11 9 8 7 5 5 4 3 3 2 2 1 1 1 0   (identical)
    cap fill                        #404041        #404041
    plate                           #1B1B1D        #1B1B1D

Sixteen rows of corner profile, the same in both. `capCornerRadius` at 7pt is right, and the
"stock 22 vs ours 16" was two thresholds, not two corners. The cap colour is byte-equal in
the same host.

**The translucency is real but it is three units.** The same stock cap reads `#404041` over
the Contacts list and `#3D3D3D` over a Safari page; ours reads `#404041` over both, because
it is a painted opaque cap. That is a 3/255 difference on one channel, against a backdrop
change large enough to be the whole screen. It stays in section 10 as a known divergence
rather than as work: fixing it means drawing on a `UIInputView` with the `.keyboard` style
instead of on a plate we paint, which is a structural change, and the payoff is three units.

### A.7 — the bottom row does not change with the field

The note this appendix inherited said stock's URL keyboard lays out its bottom row as `123`
/ space 545 / `.` 100 / return 190 in a 1206px capture, against our 279 / 575 / 280 — a
period key we do not draw and three widths that are all wrong.

That is not what iOS 26 does. Scanned across the bottom row of two stock captures taken on
2026-09-05, one in Safari's address bar (`.URL`, `.go`) and one in a Contacts search field
(`.default`, `.search`):

    key        Safari .URL     Contacts .default    KeyBored
    123        x 19-297        x 19-297             x 19-297
    space      x 315-889       x 315-889            x 315-889
    return     x 907-1186      x 907-1186           x 907-1186

The same three keys at the same three spans in all three, and no period key in either stock
row. Whatever iOS the original note described, this one lays the bottom row out the same way
whatever the field asked for, and this keyboard already matches it to the pixel. Nothing to
implement; the open question is closed by measurement rather than by code.

### A.8 — three things stock does that this keyboard now does too

Added 2026-09-05, after the geometry and the palette were settled and what was left was
behaviour.

**Caps lock.** A second strike on shift within 0.3s latches it; the latched key draws
`capslock.fill`, a barred arrow, where the one-shot draws `shift.fill`. Section 3.2 has the
transitions and section 3.3 says why `ShiftState` has three cases rather than a flag. The
0.3s is the conventional double-tap interval and was not timed off a stock keyboard;
section 10 carries it as a tunable.

**Delete repeats while it is held.** 0.4s to the first repeat, then one every 0.1s, on a
run-loop timer in the common modes so that a tracking run loop does not stop delivering it.
Stock also accelerates into whole words after a few seconds and this does not; section 10.

**The globe raises the keyboard list on a long press.** `handleInputModeList(from:with:)` is
the only route iOS gives to that list, and it wants a `UIControl` and the event UIKit hands
a control — neither of which a plate that hit-tests its own touches can supply. So the globe
cap carries an invisible `UIControl` on top of it and the extension puts that selector on
it, which also handles the short tap; `advanceToNextInputMode()` is no longer called by
hand. The container app never wires it, and its control stays inert.

**How each was checked, since none of them could be tapped from a script.** A System Events
click reaches the simulator through the accessibility layer: it lands only on elements the
app exposes, and it lands at their centre. Shift, delete, the globe and the space bar drew
images or nothing, exposed nothing, and swallowed every click aimed at them — which reads
exactly like a keyboard whose bottom two rows are dead, and cost most of an evening before
`123` was tried and worked because it draws text. Every cap now carries an
`accessibilityLabel` and the `.keyboardKey` trait, which is what stock does and what
VoiceOver needs, and which was missing entirely for half the keyboard.

So: caps lock's transitions are covered by four controller tests over the real clock path;
its appearance by a render of the latched keyboard written to the simulator's Documents
directory as `keyboard-capslock.png`, looked at rather than asserted; the delete repeat by a
test that holds the key with the repeat shortened forty-fold; and every command cap by a
test that hit-tests each of its four corners rather than its centre. The globe's long press
is the one thing here with no artifact behind it: it is wired the way Apple documents and
has not been seen working.

**All three have since been seen working on a running keyboard.** A.9 says how, and
supersedes the paragraph above about what could not be tapped: the accessibility layer was
never the only route, it was only the route that had been tried.

### A.9 — how to drive the real keyboard, and what that turned up

Written 2026-09-06. The section it most changes is A.8, whose account of what a script can
reach is superseded here rather than edited in place, so the reasoning that produced it
stays legible.

**A synthetic mouse event reaches every key; an accessibility click does not.** A.8's
finding — that a System Events `click at` lands only on exposed elements, and at their
centre — is correct about System Events and wrong as a claim about the simulator. `CGEvent`
posted to `.cghidEventTap` at a screen point is delivered as a real mouse event, and the
Simulator turns it into a touch wherever it is aimed: shift, delete, space, the globe, a
cap's corner, a long press. That is `scratchpad/tap.swift`, and `mtap.sh` and `key.sh`
wrap it in the device-point coordinates the screenshots are measured in. **A gap named in
A.8 turned out to be a route that had not been tried, not a route that does not exist.**

**Selecting this keyboard from the globe's long-press list.** The list's rows move: when it
carries the three keyboard-size buttons along the bottom, every row above them sits higher,
and a tap computed from a capture taken without that row lands on the size buttons and does
nothing at all. Screenshot the list, measure the row, then tap. Hours went into the theory
that the extension was failing to present when the tap had simply missed.

**A retraction, and how it happened.** Between 23:45 and 00:10 on 2026-09-05/06 this
keyboard was reported here as failing to present, and stock was measured repeatedly as
though it were ours. Three discriminators were tried and all three were wrong: the
dictation mic and the globe strip below the plate are drawn by iOS for a custom keyboard
too, so their presence says nothing; the quoted left bubble is stock's own format, which is
where ours got it; and the bar's rules land within a pixel of each other. What settled it
was a red 24×24 square drawn in the input view's corner for one build — an artifact that
cannot be confused for stock — and the extension's own `os_log` on each key. **Neither
palette nor layout can tell these two keyboards apart any more, which is the point of the
work and is also why identifying which one is on screen now needs a marker build or a log
line rather than a look.**

The measurements below were taken through that route, both keyboards in the same Contacts
search field, same simulator, same `xcrun simctl io screenshot`, minutes apart.

**Caps lock, seen working.** Two strikes on shift, then `abc`, space, `def`: the field takes
`ABC DEF` and the shift cap draws the barred `capslock.fill`. The lock survives the space,
which is what section 3.2 says it should.

**Delete repeat, seen working.** A 1500ms hold on delete emitted 13 delete events and
emptied a ten-character field. 0.4s to the first repeat and 0.1s after it predicts 12 in
that window; 13 is that, with the run-loop timer's jitter.

**The number plane, ours against stock, light appearance.** Every cap in both of the ten-key
rows ends on exactly stock's pixel — 119, 238, 356, 475, 593, 712, 830, 949, 1067, 1186 of
1206. The leading edges differ by a pixel on some caps and not others, and *which* ones
alternates: on the digits row ours begins at 19, 138, 256, 375, 493, 612, 730 where stock
begins at 20, 138, 257, 375, 494, 612, 731. That is a third of a point — the two layouts
place the same edges at the same fractional coordinates and the rasteriser rounds a few of
them the other way. **Left alone deliberately.** The letters plane's cap is byte-equal to
stock's (A.6), and chasing a third of a point on one plane is the kind of change that
breaks the plane that already matches.

**The light plate is three units off, and this contradicts A.4.** Ours reads `#DFE0E6` and
stock `#E2E4E8` in this pair, where A.4 recorded stock's light plate as `#DFE0E6` — which
is the value ours is now set to. One of the two stock readings is wrong, or stock's plate is
not one colour in every context. **Resolved by A.11: the second half is the answer, and
neither reading is wrong.** Both stock numbers stand as readings of different backdrops.

**Whether stock dims the return key on an empty field is open, and the evidence is
contradictory. Resolved by A.13: it is not the field being empty, it is the field's
`enablesReturnKeyAutomatically` trait plus whether anything has been typed since this
presentation.** A.5 recorded that it does not, retracting an earlier note that said it
does. On 2026-09-06 an empty Contacts search field was captured twice, both on a settled
screen and minutes apart: once with the magnifier on grey and once with it on `#007AFF`.
So the grey is real and is not only a frame of the presentation animation, but it is not a
function of the field being empty either, and nothing here says what it *is* a function of.
**Do not implement `enablesReturnKeyAutomatically` on the strength of this.** What would
settle it is a capture of the same field in both states with the difference in the field
recorded, which is a small experiment nobody has run. It has now been run; A.13 is the
result, and the two captures above are the two sides of the latch rather than a
contradiction.

### A.10 — the quote keys, read off the pasteboard rather than off a screenshot

Measured 2026-09-06 on the iPhone 17 Pro simulator, iOS 26.5, dark appearance, in the
Contacts search field, typing with the **stock** keyboard driven by `tools/keys.sh`.

**The caps carry curly glyphs.** Stock's apostrophe cap is a single slanted wedge and its
double-quote cap a pair of them; this keyboard drew a straight `'` (U+0027) and `"`
(U+0022), which is two vertical bars. Plain in `scratchpad/q-stock.png` beside
`scratchpad/q-ours.png`, both crops of the same cap position, the second from a build
carrying the red identification marker of A.9 so there is no doubt which keyboard it is.

**The character inserted is not the character on the cap.** Stock picks the opening or the
closing form from what is in front of the cursor. Every row below was produced by typing
into an empty field, selecting all, copying, and reading `xcrun simctl pbpaste booted |
xxd` — **the codepoint comes from the pasteboard, not from a glyph in a screenshot**,
because `‘` and `’` are a few pixels apart at 3x and I had already read one of them wrong
by eye that evening. That mistake is A.9's subject and this is the cheap instrument that
avoids it.

| what was already in the field | key struck | bytes | character |
| --- | --- | --- | --- |
| nothing | `'` | `e2 80 98` | U+2018 `‘` |
| `A` and a space | `'` | `41 20 e2 80 98` | U+2018 `‘` |
| `(` | `'` | `28 e2 80 98` | U+2018 `‘` |
| `A` | `'` | `41 e2 80 99` | U+2019 `’` |
| `5` | `'` | `35 e2 80 99` | U+2019 `’` |
| nothing, struck twice | `"` `"` | `e2 80 9c e2 80 9d` | U+201C then U+201D |

The last row is the one that decides the shape of the rule. A paired-quote state machine
would open again after its own `“`; stock closes. So the rule implemented in
`Shared/SmartPunctuation.swift` is positional and has no state: **opening after nothing,
after whitespace, or after an opening bracket; closing after everything else.**

**The apostrophe hands the keyboard back to the letters plane, and nothing else on that
plane does.** Tap the key, screenshot, look at which plane came back: after `'` the letters
are showing (`scratchpad/rv2c.jpg`); after `"`, after `.`, and after a digit the numbers
plane is still there (`rv3c.jpg`, `rv1c.jpg`). A sensible asymmetry rather than an
oversight — an apostrophe is nearly always typed inside a word, so the tap after it is a
letter.

**Not observed, and left as a divergence rather than guessed at.** What stock does in a
field that sets `smartQuotesType = .no`: no field on this simulator asks for it, so there
was nothing to capture. This keyboard inserts the ASCII characters there and keeps the
curly glyph on the cap, on the reasoning that a field asking for a literal quote wants a
literal quote and that giving it a curly one would be this keyboard's own bug rather than a
match with stock. Whether stock also changes the cap is unknown.

**Also not chased:** smart dashes (`--` to an em dash) and smart insert/delete, which are
the other two halves of the same iOS setting. Neither was measured and neither is
implemented.

### A.11 — stock's plate is not a colour, and that is why two captures disagreed

Measured 2026-09-06 between 01:20 and 01:35, light appearance, Contacts search field, one
keyboard swapped for the other in the same field within a minute or two. **Which keyboard
was on screen was confirmed from the globe's long-press list before every reading** — the
highlighted row is the current keyboard — because the bar's quoted literal, which had been
serving as a tell, is stock's own format and identified nothing. A.9 is about that mistake;
this is what checking costs, which is one long press and one screenshot.

    backdrop behind the keyboard        stock            BoreKey
    the Contacts list                   #E1E3E6/#E1E3E7  not sampled
    "No Results", the list filtered out #E2E4E7/#E2E4E8  #DFE0E6

Nothing changed between the two stock rows but the content **underneath** the keyboard: the
same field, the same keyboard, the same appearance, seconds apart, three `z` keystrokes
filtering the list away. The plate moved by three units and BoreKey's did not move at all,
because BoreKey paints a constant and stock does not.

**Stock's plate is a blurred material over the host's content.** It reads uniform across the
width because the blur averages the whole backdrop, which is exactly why it looked like a
flat colour in every single capture and why two honest measurements of it disagreed. A.4's
`#DFE0E6` and A.9's `#E2E4E8` are both correct readings of different backdrops, and the
premise they contradict — that there is one value to measure — is the thing that was wrong.

This is the same mechanism A.4 already recorded for the caps, where one stock cap read
`#404041` over Safari and `#3D3D3D` over the black Contacts list. It is now measured on the
plate as well, deliberately rather than incidentally.

**And the fix was one line, because the material was already there.** Section 10 had this
down as "draw on a `UIInputView` with the `.keyboard` style rather than on a painted
plate", which sounded like a rewrite. `UIInputViewController`'s `view` **is** a
`UIInputView` drawing that material; this keyboard was painting `plateColor` over the top
of it. Removing the paint — `view.backgroundColor = .clear` — is the whole change, and the
result is byte-identical to stock on every backdrop and appearance measured:

    backdrop                              stock            BoreKey, plate painted   BoreKey, paint removed
    light, the Contacts list              #E1E3E6/#E1E3E7  #DFE0E6                  #E1E3E6/#E1E3E7
    light, "No Results"                   #E2E4E7/#E2E4E8  #DFE0E6                  #E2E4E7/#E2E4E8
    dark, "No Results"                    #171717          #1F1F1F                  #171717

Note what the middle column says about the old A.4 target as well: `#DFE0E6` was measured
off a real stock capture, and it still did not match stock in either of the two states
measured here, because there was never a value that would.

`KeyboardView.plateColor` is kept. The container app draws the same `KeyboardView` on an
ordinary view with no material behind it, and there a painted colour is the right thing.

**The caps are the same problem, and they turned out to be solvable by arithmetic rather
than by guessing.** There is no documented system view for a key cap the way `UIInputView`
is one for the background, and picking a `UIVisualEffectView` style by eye would have been a
guess. But a wash does not need a style to be identified — it needs two states. Dark
appearance, three hosts, stock and this keyboard in the same field minutes apart, identity
checked from the globe's list every time:

    host                       plate      stock cap   BoreKey cap, before
    Safari, the start page     #1B1B1D    #404041     #404041
    Contacts, the list         #171717    #3D3D3D     #404041
    Settings, the list         #171717    #3D3D3D     #404041

Solving `cap = a·C + (1 - a)·plate` on the red and green channels of the two distinct states
gives `a = 0.25` and `C = 175`, and that pair then **predicts both blue channels exactly** —
`0.25·175 + 0.75·29 = 65` and `0.25·175 + 0.75·23 = 61`, against the `#404041` and `#3D3D3D`
measured. Two parameters, six numbers, no residual. So stock's dark cap is a quarter of
`#AFAFAF` over whatever is underneath, and `KeyboardView.capMaterial` is now that.

Note what the third column says: the old constant was not wrong, it was *right for one
host*. It was sampled over Safari and it is exact there. Every host with a black backdrop is
where it drifted.

**Light stays opaque white and that is also a measurement.** Stock's light cap reads
`#FFFFFF` over both light plates measured; white is the ceiling, a saturated channel carries
no signal to fit a wash to, and ours is already byte-equal to stock there (A.6). A wash
fitted to no data could only move it off.

**What the built keyboard then rendered, which is not quite what the arithmetic said.**

    state                          stock cap   before      after
    Safari, start page             #404041     #404041     #3F3F40   (one unit low)
    Contacts, the list             #3D3D3D     #404041     #3D3D3D   (exact)
    Contacts, "No Results"         #3D3D3D     #404041     #3C3C3C   (one unit low)

Strictly better — never more than one unit out, against three — and left there. The single unit is smaller than the three-unit gap A.4 measures
between two capture pipelines rendering the same colour, and raising `C` to close it in
Safari pushes Contacts off by the same unit in the other direction, which is a trade and not
a fix. **The cause of the unit is not established.** The likeliest candidate is the cap's
own drop shadow darkening the material directly under it, so the wash is not compositing
over the plate colour sampled from the gap between rows; that was not tested.

**What was not tried:** whether the drift is larger over a backdrop that is not mostly
white or mostly black, and any host other than Contacts for the paint-removed build.

### A.12 — the pressed cap, which a screenshot turned out to be able to show

A.4 recorded one value as unmeasurable: "the dark pressed state: a static screenshot cannot
show a key being held". That was true of a screenshot taken by hand and untrue of one taken
by a script. `tools/tap.swift` posts the mouse-down, waits, and posts the mouse-up
separately, so the hold is an interval you control — post the down, sleep, `xcrun simctl io
screenshot`, then let the up fire.

Measured 2026-09-06 on the **stock** keyboard, in a Contacts search field, delete held for
two seconds and the capture taken at 0.7s. Sampled at four corners of the cap, flat across
all of them.

    appearance   plate      stock pressed   what this keyboard drew
    dark         #171717    #7D7D7D         #6B6B6B  (18 units too dark)
    light        #E2E4E8    #C5C5C9         #D9DEE3  (20 too light, and blue where
                                                      stock is very nearly neutral)

Both are now the measured values.

**The press has to actually take, or the cap does not change.** Three earlier attempts read
nothing: delete held on an empty field, the search return key, and a letter. The first two
produced no highlight at all, and whether that is because nothing happened or because stock
does not highlight those was not separated. The one that worked has text in the field, and
`press6.png` shows it plainly — the field mid-repeat at "He", the delete cap lit, stock's
own suggestions in the bar. **When a press-state capture reads the same as the resting one,
suspect the press before you believe the colour.**

**Stock's own pressed cap does not clear 4.5:1, and the test now says so.**
`everyCapIsLegibleInBothAppearances` held every cap to WCAG AA against the glyph on it, and
`#7D7D7D` under a white glyph is 4.17:1. The old constant passed that bar by being 18 units
darker than stock — which is to say the keyboard was diverging from what it is copying in
order to satisfy a threshold this project chose. The floor is kept and lowered to 3:1 for
the pressed state only, at the level stock actually reaches; the resting cap still has to
clear 4.5. The state lasts as long as a finger is down, and the finger is on the glyph.

**It is not the resting wash.** A.11 identifies the resting dark cap as `a = 0.25` over
`#AFAFAF`. Matching `#7D7D7D` over a `#171717` plate with that same `a` would need
`C = 431`, which is not a colour. Whether the pressed cap is a wash with some other `a`
could not be decided: it needs two backdrops, and in dark appearance every host tried
except Safari's start page reads `#171717`, while Safari's start page turns into its
suggestion list the moment a character is typed — and a character has to be typed for the
delete press to take at all. So the constants above are opaque, and the plate each was read
over is recorded so a wash can be fitted later without re-measuring the first point.

### A.13 — the dimmed return key, which is a latch and not a test of the field

A.9 left this open with two captures of the same empty Contacts search field disagreeing
with each other. Both were right. The state is not "the field is empty" — it is "nothing has
been typed since this keyboard was presented", which an empty field satisfies on a fresh
presentation and stops satisfying the moment you type, and keeps not satisfying after you
delete back to empty.

Measured 2026-09-06 on the **stock** keyboard, Contacts search field, keyboard identity
confirmed from the globe long-press list before each reading:

    what was done                     return key
    presented, field empty            grey
    one character typed               #007AFF
    that character deleted, empty     #007AFF   (stays; the latch does not reset)
    dismissed and presented again     grey

**It is field-gated, not universal.** Safari's URL bar, empty and freshly presented, is
`#007AFF`. So the rule is the field's `enablesReturnKeyAutomatically` trait and not a
property of emptiness, and a keyboard that dimmed on "the document is empty" would be wrong
in Safari — which is exactly what a reading of A.9 without this appendix would have built.

The four colours, each with the plate it was read over, because A.11's lesson is that a cap
colour is meaningless without its backdrop:

    appearance   plate      dimmed fill   dimmed glyph
    dark         #171717    #747474       #818181
    light        #E1E3E6    #C0C2C5       #ADAEB1

`KeyboardView.dimmedActionKeyColor` and `dimmedActionKeyTextColor` are those values,
**opaque**, for A.12's reason: one backdrop per appearance cannot separate a wash from a
solid, and inventing an `a` to fit a single point fits anything. The plates are recorded so
whoever finds a second backdrop can fit one without re-measuring the first.

**The glyph is deliberately illegible, and the test says so out loud.** Stock's dimmed glyph
against stock's dimmed cap is about 1.1:1 — the point of the state is that the key reads as
unavailable. `everyCapIsLegibleInBothAppearances` therefore asserts the opposite bound for
this pair, `< 1.5:1`, rather than exempting it silently. It also asserts the dimmed fill is
*not* `actionKeyColor`, as an inequality: a luminance contrast ratio is the wrong instrument
for telling grey from blue, and `1.16` between them proves nothing either way.

The keyboard reproduces the latch with `KeyboardController.hasTypedSincePresentation`, set
by every insertion that goes through the `insert(_:)` funnel and cleared by `didPresent()`,
which `KeyboardViewController.viewDidAppear` calls. The rewrite in `commitWord` bypasses the
funnel on purpose: replacing what you already typed is not typing something new, and stock
does not un-latch either.

**Not tested: whether stock also dims a plain `↵`** — a return key whose trait is `.default`
rather than an action word — in a field that sets `enablesReturnKeyAutomatically`. No field
doing both was found on this device, so the keyboard dims only action return keys, which is
what was observed rather than what was generalised from it.

### A.14 — the period key an address field gets, and the row it rearranges

Safari's address field is the one host this keyboard has been compared against more than
any other, and its bottom row had never been measured key by key. It is not the same row.

Measured 2026-09-06, iPhone 17 Pro simulator, light, Safari's address field, 1206px wide at
3x. Stock and this keyboard were captured in the same field minutes apart, and which
keyboard was on screen was confirmed from the globe long-press list before each capture
rather than inferred from what the row looked like.

    key       stock            this keyboard
    123       20-297           19-297
    space     316-860  (545)   315-889  (575)
    .         879-978  (100)   absent
    return    997-1186 (190)   907-1186 (280)

Gaps are 18px throughout in both, and the period cap occupies rows 2259-2387, the same band
as the rest of row 3. Stock spends the difference the obvious way: the return key gives up
110px and the space bar 30, and 100 of that becomes a cap with a period on it.

The three widths this keyboard sets — the `123` key, the period cap and the return — land on
stock's to within a pixel. The space bar is the remainder and comes out four reference
pixels wide, 549 against stock's 545 at 402pt. The row now has three gaps where it had two,
and the gap fraction is a shade under the 18px stock draws, so the shortfall lands in the
one key that absorbs it. Closing it would mean moving the column gap, which every other row
is measured against, for 1.2pt on the bottom row.

**It is the letters plane only.** The number and symbol planes of the same field, captured
in the same sitting, have no period key and the full-width return — stock's space bar there
is 316-889, which is this keyboard's to within a pixel. So the period key is not a property
of the field alone; it is the letters plane of that field.

**The field is `.webSearch`, and that was read rather than assumed.** Safari's address bar
looks like the textbook `UIKeyboardType.URL` and is not. A probe build of this keyboard,
installed for the purpose, inserted `keyboardType`'s raw value into the field on
presentation and it came back `10`, which is `.webSearch`, with `returnKeyType` `1`, which
is `.go`. Both agree with what stock draws.

**Whether `.URL` and `.emailAddress` behave the same way is untested, and the keyboard does
nothing for them.** Reaching a field of either kind means an app that has one; the obvious
route, an email field in a Contacts card, needed the edit screen, and taps on that screen
would not land — three attempts on the Edit button did nothing, with the same script that
had just driven Safari and the globe list. `wantsPeriodKey` therefore answers true for
`.webSearch` and false for everything else, which is what was seen rather than what would
be reasonable.

The key is a new `KeyRole.punctuation`, not a `.letter`. The difference is the matcher's:
`letterKeys` is the constellation, and a period on the letters plane is a point no word has.
It ends the word in progress and inserts the character the way a tap on another plane does,
and then the field's capitalization rule gets its say, because a period is one of the things
`.sentences` capitalizes after.

**What else was measured in the same sitting, and matched.** The symbols plane, which was
the reason for going in: rows land at 1774/1936/2097/2259 on stock against 1773/1935/2097/
2259 here, every inter-key gap in rows 1 and 3 is the same to within a pixel, and the cap's
left edge tracks stock's to within one pixel from the top of the cap down. The one residue
is the corner: stock's cap stops narrowing about 20px below its top edge and this one stops
at about 16, on a radius drawn at 21. That is a sub-point difference at 3x measured through
a brightness threshold, and it is recorded rather than acted on.

### A.15 — the flickering suggestion was the keyboard's own key preview

Reported 2026-09-05 as "the suggested word keeps flickering or fading in and out", and
still there in the 0.0.3 build he was looking at on 2026-09-06. It is not the bar being
recomputed and it is not an animation. It is one line in `touchesBegan`.

A top-row key's preview wants to be at a negative `y`, and a custom keyboard's input view is
clipped by its host, so the preview is clamped down into the candidate bar — the fix for the
other thing he reported the same evening, "popup being cutoff". The clamped preview overlaps
one third of the bar, and `hideBarSlot(under:)` hid whichever suggestion it covered, on the
reasoning that a half-covered word looks broken. Restored on release. So every letter struck
in the top row blanked a third of the bar for as long as the finger was down.

The hiding is gone. The preview is opaque and drawn in front, so it covers the part of a
word it sits on and leaves the rest legible, which is what a key floating over a bar looks
like.

Verified on the simulator 2026-09-06, BoreKey confirmed current from the globe list, with
the press held by a script so the capture lands mid-press: with `hel` typed and the bar
reading `"hel" | gel`, a held `y` — whose preview sits squarely over the middle third —
leaves `hell` legible either side of the cap instead of blanking it (`fky.png`). The same
capture settles a second question raised from a phone screenshot: the preview draws the
lowercase glyph when the keyboard is unshifted.

### A.16 — two ways the keyboard replaced text the user had typed

Both reported on 2026-09-06, both reproduced, and both the same shape: the keyboard
rewriting characters that were already right.

**One — taps that land inside a word already in the field.** `WordInProgress` is the taps
since the last boundary, and everything downstream assumes the taps and the word are the
same thing: the bar calls the taps "what you typed", and a commit deletes exactly
`tapCount` characters back from the cursor and puts a correction there. Put the cursor
inside a word the keyboard did not compose and neither holds.

Reproduced in Safari's address field on a simulator, BoreKey confirmed current from the
globe list: type `cat`, space, delete, then `hte`. The field reads `cathte` — which is what
the user typed — and the bar reads `"hte" | he | hate`, which is about a fragment. The next
space took the field to `cathe`: three characters deleted and `he` put in their place
(`wb2.png`, `wb3.png`).

The word now records whether it began where a word begins, decided once, on the first tap,
from the character in front of the cursor at that moment. A word that did not is not one
this keyboard may describe or rewrite: no bar, no correction, no bubble commit. Deleting
back into a word and carrying on typing is the common way to reach this, and it is why the
keyboard cannot simply read the word out of the document instead — the letters are there but
the taps that produced them are not, and the taps are what the matcher scores.

**Two — a correctly typed word replaced by a different one.** His words: "It also make a
bunch of poor corrections like editinf to doting and/or often drooping an s to turn it into
a wholehxdifferent word".

The commit rule in section 6.3 asked one question — is the best candidate within
`literalCost + 0.5 per tap` — and a candidate that close can be a different real word.
Nothing in the cost separates a typo from a correctly typed word, because accurate fingers
put both in the same place. Dropping a trailing `s` is the sharpest case: both spellings are
real words and the taps barely distinguish them.

**A word the user actually typed is now never replaced.** The rule tests the insertion and
not the tap form, so the corrections that exist to turn a word into a different string keep
firing: `dont` is in the lexicon with `don't` as its insertion, so it is not "already a
word" by this test, while `editing` inserts itself and is.

What to suggest and when to overwrite are two decisions, and this changes only the second.
The candidate is still ranked, still shown in the bar, and still applied if it is tapped.
That separation is the one idea taken from a look at FUTO's Android keyboard, which exposes
it to its users as an autocorrect-confidence threshold distinct from its ranking weights;
nothing was copied, and their code is source-available rather than open source.

**What this does not do.** It does not make the ranking better, and a genuinely mistyped
non-word still gets whatever the constellation search offers. It also does not help a word
that is missing from the lexicon, which was reported in the same message and is not
diagnosed: a word absent from the list and a word present but never ranked into the top
three are different defects, and which of the two he hit was not established.

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
