<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# Releasing KeyBored

Everything needed to take a fresh clone to a TestFlight build, written for the person
doing the App Store Connect work themselves.

**What is verified.** Every command below was run on this machine and its output is quoted.
As of 2026-09-05 the whole path has been walked once, end to end: both App IDs registered,
store provisioning profiles issued, a distribution certificate issued, an App Store Connect
app record created, and version 0.0.1 build 1 uploaded and accepted for processing. No
agreement was presented at any step of that run — not at archive, export, record creation
or upload. That is one observed run on an account whose agreements were already in order,
not a claim that none is ever presented.

## What the project emits

Read out of an actual archive with `plutil`, not from `project.yml`:

    app         com.tg-techie.app.keybored
    extension   com.tg-techie.app.keybored.keyboard
    products    BoreKey.app, and BoreKey.appex inside its PlugIns
    display     BoreKey  (CFBundleDisplayName and CFBundleName, from PRODUCT_DISPLAY_NAME)
    version     0.0.2    (CFBundleShortVersionString, MARKETING_VERSION)
    build       1        (CURRENT_PROJECT_VERSION)
    minimum iOS 26.0

The products are named BoreKey too, and that is not cosmetic. `CFBundleName` cannot be
set from an Info.plist — with `GENERATE_INFOPLIST_FILE` on, Xcode writes
`CFBundleName = $(PRODUCT_NAME)` over whatever the hand-written plist says, and there is
no `INFOPLIST_KEY_CFBundleName` to stop it. Builds 0.0.1 through 0.0.5 all shipped
`CFBundleName = KeyBored` because of that, which is why `PRODUCT_NAME` is now
`$(PRODUCT_DISPLAY_NAME)` for both bundle targets. `PRODUCT_MODULE_NAME` is pinned
beside each one, because the Swift module is not a brand: it is what `@testable import
KeyBored` names, and the project is KeyBored. Read the archived `Info.plist` to check
any of this, never the one in the tree.

The identifiers say KeyBored and the app says BoreKey, on purpose. `KeyBored` was already
taken as an App Store name; a bundle identifier is a separate namespace and is permanent
once a record exists, so it was left alone. The display name is written once, as
`PRODUCT_DISPLAY_NAME` in `project.yml`, and reaches both bundles through
`INFOPLIST_KEY_CFBundleDisplayName`.

The extension's identifier is the app's with `.keyboard` appended, and it has to stay that
way: iOS requires an app extension's bundle identifier to be a child of its containing
app's, and a pair that does not nest is rejected rather than warned about. Both identifiers
are set in `project.yml`; change them there and regenerate, never in Xcode's UI, or the
next `xcodegen generate` silently reverts you.

## The repository side

Verified on macOS 26.5 with Xcode 26.5 (17F42) and xcodegen 2.45.4, 2026-09-05.

`KeyBored.xcodeproj` is tracked, so a clone opens in Xcode with no tooling installed. You
only need `xcodegen` (`brew install xcodegen`) if you add, move or rename files, in which
case run `xcodegen generate` rather than editing the `pbxproj`.

    git clone https://github.com/TG-Techie/KeyBored.git
    cd KeyBored

    # Builds and tests with no signing identity and no Apple account at all.
    xcodebuild -scheme KeyBored \
      -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
    xcodebuild -scheme KeyBored \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

40 tests, all passing as of 2026-09-05.

### Signing

No `DEVELOPMENT_TEAM` is tracked, deliberately: a signing identity belongs to whoever is
building, not to the repository, and a public repo should not carry one. `Signing.xcconfig`
is wired into both configurations and does nothing but `#include? "Local.xcconfig"` — the
`?` makes it optional, which is why a stranger can clone and build without an account.

Create `Local.xcconfig` at the repository root. It is gitignored, so it will not follow you
into a commit:

    DEVELOPMENT_TEAM = YOURTEAMID

Or supply it per invocation and leave no file behind:

    xcodebuild ... DEVELOPMENT_TEAM=YOURTEAMID

Either works; the file is less to remember if you will archive more than once.

### Before any of it: type with it

**Type a sentence into another app with this build and read the result back. Do it in dark
appearance and in light.** This is a required step, not a suggestion, and it goes before the
archive because everything after the archive is expensive to redo.

Two defects reached TestFlight on 2026-09-05 that no build log, no unit test and no
screenshot of the keyboard by itself could have caught:

- The letter keys rendered blank in dark appearance. `KeyCap.label` inherited `.label`,
  which is white, on caps that were hard-coded white. Every test passed; the keyboard was
  legible in the container app, which was light.
- Typing inserted nothing at all into a host app. `KeyboardController` held its
  `TextDocument` weakly and both hosts construct their adapter inline, so it was gone the
  instant `init` returned. Forty tests passed, because every one of them held its fake
  document in a local for the length of the test — an ownership no real host has.

The recipe, on a booted simulator whose id is in `$D`:

    xcodebuild -scheme KeyBored -destination "platform=iOS Simulator,id=$D" \
      -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO build
    xcrun simctl install "$D" build/sim/Build/Products/Debug-iphonesimulator/BoreKey.app

Add the keyboard once per simulator — it does not appear on its own:

    xcrun simctl spawn "$D" defaults write .GlobalPreferences AppleKeyboards \
      -array en_US@sw=QWERTY com.tg-techie.app.keybored.keyboard
    xcrun simctl spawn "$D" launchctl stop com.apple.SpringBoard

Then open a host with a text field — Contacts' search field or Safari's address bar — and
focus it. **Switching to BoreKey is the step that wastes the afternoon if you improvise it.**
Hold the globe in the strip iOS draws below the plate, screenshot the list, measure the
BoreKey row out of that screenshot, and tap it:

    swiftc -O -o tap tools/tap.swift
    HOLD=1200 tools/keys.sh globe
    xcrun simctl io "$D" screenshot list.png
    ./tap <x> <y>          # the BoreKey row, in the Mac's screen points

The list's rows move: when it carries the three keyboard-size buttons along the bottom,
every row above them sits higher, and a tap computed from a list captured without that row
lands on the size buttons and does nothing at all. Then type and read the field:

    tools/keys.sh t h e space c a t
    xcrun simctl ui "$D" appearance dark     # and again with: light
    xcrun simctl io "$D" screenshot shot.png

**Check which keyboard you are looking at before you believe the shot.** These two are now
close enough that neither the palette, the layout, the bar's rules, nor the globe and
dictation strip below the plate — which iOS draws for a custom keyboard as well as for its
own — will tell them apart. What does: the extension's own log line, or a marker drawn in
the input view for one throwaway build. SPEC.md A.9 has the account of an evening spent
measuring stock and reporting it as ours.

Compare against a screenshot of the stock keyboard. A build log is not evidence of any of
this and neither is a passing test.

### The preflight

Between the archive and the export, run it against the built product:

    tools/preflight.sh build/KeyBored.xcarchive/Products/Applications/BoreKey.app

It exits non-zero and names what is wrong. **Every assertion reads the `.app` rather than the
source**, which is the point: each failure it checks for got past a green build, and several
got past a full passing test suite, because what was wrong was what the build emitted and the
source said the right thing throughout. The version stamp against `project.yml`, the version
and build not already spent, the icon and its `Assets.car`, the orientations, the compliance
key, the extension's display name, a clean tree, and the session trailer.

It replaces a list in `sop/tools/xcode/README.md` that an agent was supposed to remember.
Jonah, reading that list on 2026-09-05: "A lot of that could be fixed with scrips instead of
agent softness."

### The archive

    xcodebuild -scheme KeyBored -destination 'generic/platform=iOS' \
      -archivePath build/KeyBored.xcarchive archive

**This fails on an account where the identifiers are not registered**, and the failure is
the useful kind — it names exactly what is missing:

    error: No profiles for 'com.tg-techie.app.keybored' were found …
    ** ARCHIVE FAILED **

`-allowProvisioningUpdates` is what lets Xcode register the identifiers and issue the
profiles. It is left out of the line above on purpose: **it writes to your developer
account**, so it is yours to run knowingly rather than to copy without noticing.

    xcodebuild -scheme KeyBored -destination 'generic/platform=iOS' \
      -archivePath build/KeyBored.xcarchive archive -allowProvisioningUpdates

One quirk, seen here: the very first run registered the identifier, issued the profile, and
then failed with `Build input file cannot be found: …/<uuid>.mobileprovision` because the
profile had not been written to disk yet. Running the same command again succeeded. That is
not a problem with the project.

**An archive is signed for development.** Distribution signing happens at export, so an
archive reporting `Signing Identity: "Apple Development: …"` is correct and not a mistake.

### The export

    xcodebuild -exportArchive -archivePath build/KeyBored.xcarchive \
      -exportOptionsPlist ExportOptions.plist -exportPath out \
      -allowProvisioningUpdates

with an options plist of:

    method          app-store-connect      (this is the Xcode 15+ name for app-store)
    destination     export                 (or upload, see below)
    teamID          YOURTEAMID
    signingStyle    automatic
    uploadSymbols   true

Write that plist somewhere outside the repository — it carries a team id.

Export before you upload. It separates two failures that otherwise arrive as one: whether
the build can be signed for distribution, and whether it can reach App Store Connect. Check
what actually signed it by asking the artefact rather than the keychain:

    codesign -dvvv Payload/BoreKey.app
    Authority=Apple Distribution: …

`security find-identity` reports the default keychain search list, which is not the same
set — Xcode 26 keeps managed distribution certificates outside it, so that command can show
nothing while a perfectly good certificate is in use.

### The app icon

`KeyBored/AppIcon.icon` is an Icon Composer document: a directory of flat SVG layers plus
`icon.json`. It is added to the project as an explicit file reference rather than by folder
scan, because a folder scan would take it in as a group and `actool` would never see it.

Verify it in the built product rather than in the build log, because a missing icon does not
produce a warning:

    ls build/KeyBored.xcarchive/Products/Applications/BoreKey.app
    Assets.car   AppIcon60x60@2x.png   AppIcon76x76@2x~ipad.png

    plutil -p …/BoreKey.app/Info.plist | grep CFBundleIconName
    "CFBundleIconName" => "AppIcon"

App Store Connect rejects an upload from an app with no icon, so this has to be true before
the first upload rather than fixed in a later build.

## The account side — App Store Connect

**Observed, 2026-09-05.** This section is a transcript of a run that reached processing,
not the documented flow. Where a step was not exercised it says so.

1. **Two identifiers**, in Certificates, Identifiers & Profiles, both of type App ID:
   `com.tg-techie.app.keybored` and `com.tg-techie.app.keybored.keyboard`. Neither needs a
   capability enabled — see the note on entitlements below. `-allowProvisioningUpdates`
   registers these for you, which is what happened on this machine.

2. **One app record** in App Store Connect, for the app identifier only. The extension does
   not get its own record; it ships inside the app. Without it, an upload fails with
   `error: exportArchive Error Downloading App Information`, whose real cause appears only
   in the verbose distribution log as
   `DistributionAppRecordProviderError.missingApp(bundleId: …)`.

   **Xcode's Organizer creates the record itself.** Window ▸ Organizer ▸ Distribute App ▸
   App Store Connect, and when the bundle id has no record it offers a New App form — name,
   SKU, primary language — and posts it. That was watched happening here, and the record for
   this app was made that way. `xcodebuild` cannot: no `-exportOptionsPlist` key or flag
   exposes it, and an upload without a record dies at the fetch step above. So the routes are
   Organizer, the App Store Connect web UI, or the API with a key.

   The **app name must be unique across the whole App Store**, and the bundle id is a
   separate namespace, so the two need not match — here they do not. `KeyBored` was rejected
   with `ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE.DIFFERENT_ACCOUNT` and the record was
   created as `BoreKey`.

   Two traps on that screen, both of which make the UI disagree with what was actually sent.
   Setting the name through the accessibility API rather than typing it updates the field and
   the accessibility value while Xcode keeps the old string, so a screenshot shows the new
   name and the request carries the old one. And immediately after a successful create,
   Organizer re-fetches the app list, gets `missingApp` for the record it has just made, and
   shows `IDEDistribution.DistributionAppRecordProviderError error 0` — a propagation lag
   reported as a failure. **Read the outgoing request and its status in
   `IDEDistributionAppStoreConnect.log` rather than believing the sheet**; the log path is
   printed in the first line of the distribution output.

3. **Agreements.** Apple will raise whatever license, tax and banking agreements the account
   has outstanding. Those are yours to read and accept; no agent accepts anything in your
   name.

4. **Upload**, once the record exists, by flipping `destination` to `upload` in the export
   options and re-running the export. Organizer does the same thing with a UI; the command
   line is easier to read afterwards.

       xcodebuild -exportArchive -archivePath build/KeyBored.xcarchive \
         -exportOptionsPlist UploadOptions.plist -exportPath out \
         -allowProvisioningUpdates

   ending in `Upload succeeded.` and `** EXPORT SUCCEEDED **`. Processing then takes Apple's
   own time; TestFlight shows the build when it finishes.

   **Orientations are checked at upload and nowhere else.** The first upload attempt was
   rejected outright:

       Invalid bundle. No orientations were specified in the com.tg-techie.app.keybored
       bundle. To support iPad multitasking, specify the "UIInterfaceOrientationPortrait,
       UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft,
       UIInterfaceOrientationLandscapeRight" orientations for the
       UISupportedInterfaceOrientations Info.plist key.
       code = 90474

   `KeyBored/Info.plist` now declares all four. Nothing local catches this: the app builds,
   runs and archives without the key. It is the same shape as the missing icon — a manifest
   key that only App Store Connect validates — so check both in the built product before an
   upload rather than after.

5. **Internal testing** needs no review. External testing needs Beta App Review, and a
   custom keyboard draws attention to what it does with keystrokes: `PRIVACY.md` answers
   that in the terms a reviewer asks it, and every claim in it names the command that
   checks it.

### Entitlements: there are none, and that is a decision

`RequestsOpenAccess` is `false` in `KeyBoredKeyboard/Info.plist`, and there is no app group.
Without Full Access, iOS itself — not a promise in a document — prevents the keyboard from
reaching the network, a shared container, or the pasteboard. That is the load-bearing claim
in `PRIVACY.md`, so if a future change needs Full Access, it is a change to what the app
tells its users and not only a plist edit.

Practically, for this setup: nothing to enable on either identifier, and no provisioning
profile complications from capabilities.

## After the upload

Bump `MARKETING_VERSION` in `project.yml` — it is set once under `settings.base` and applies
to all three targets — then `xcodegen generate`. App Store Connect refuses a second upload
with a version and build pair it has already seen, and it is easier to bump before archiving
than to re-cut. `CURRENT_PROJECT_VERSION` is the build number and only has to increase within
one marketing version, so a new version can start again at 1.

Spent, both uploaded on 2026-09-05 and neither relabellable:

- **0.0.1 build 1.** Rejected at upload the first time for missing orientations; the
  reworked build went up under the same version and build.
- **0.0.2 build 1.** Uploaded and unusable: blank letter keys in dark appearance, and
  typing that inserted nothing into a host app. Both are the reason the section above
  exists.

- **0.0.3 build 1.** Uploaded at 20:51 EDT from commit `9932d04` with a clean tree, after
  typing "Hi there" into Safari with it on a simulator in both appearances.

- **0.0.4 build 1.** Uploaded at 00:37 EDT on 2026-09-06 from commit `a8f40ef` with a clean
  tree. The evidence behind it, in the order it was taken: 66 tests passing; the shipped
  build installed and switched to from the globe's list; "The cat sat on the mat" typed
  into Contacts' search field in light appearance and "the quick fox" in dark, both with
  `tools/keys.sh`; caps lock latched with two strikes and "ABC DEF" typed under it; a
  1500ms hold on delete emptying a ten-character field. The exported ipa was checked with
  `codesign -dvvv` for an `Apple Distribution` authority before it went up.

- **0.0.5 build 1.** Uploaded at 03:59 EDT on 2026-09-06 from commit `65c1f13` with a clean
  tree. What it carries: the address field's period key, the dimmed return key, the fix for
  the flickering suggestion, the anchored-word fix, the never-replace-a-real-word commit
  guard, and the 75,646-word `2of12inf` list in place of the 19k lemma list. The evidence
  behind it, in the order it was taken: 78 tests passing; `tools/preflight.sh` passing
  against the built product, including its two new checks that the bundled word list named
  in `EnglishLexicon.swift` is present in both the app and the appex; the period key
  verified on a device in light and dark; the flicker fix verified by a mid-press screen
  capture with the press held open; the anchor fix verified by typing into the middle of an
  existing word and watching the bar stay empty and the text survive; `dont` still
  correcting to `don't`. The exported ipa was checked with `codesign -dvvv` for an
  `Apple Distribution` authority before it went up.

- **0.0.6 build 1.** Uploaded at 08:37 EDT on 2026-09-06 from commit `4d1dff3` with a clean
  tree. What it carries: the first row raised back to where stock draws it, after the
  discovery that one constant was standing for both the stock plate-to-first-row distance
  and our own suggestion bar's height; and one touch layer in place of three, which turns
  on `isMultipleTouchEnabled` and so stops the keyboard dropping every touch but the first
  of a multi-touch sequence. The evidence behind it, in the order it was taken: 80 tests
  passing, two of them new sweeps over every point of the keyboard at 1pt spacing; the row
  position measured against a stock screenshot on the simulator, stock plate to row 0 at
  156px against ours at 154px, where it had been 206px; and the archive checked in the
  built product for its icon, its `CFBundleName`, all four orientations, and exactly one
  appex.

  **One defect in this build is fixed on paper and not on the device.** A tap landing in
  the 6pt drawn gap between two key caps still registers nothing. After a SpringBoard
  restart, with BoreKey confirmed active by its 153px suggestion band against stock's 156,
  a sweep at x = 30, 34, 38, 40, 42, 44, 46, 50 produced "Qqqqww" — the two taps at 42 and
  44 lost. That is the same result as before the change, so the `hitTest` override is not
  by itself sufficient, and it is not a stale extension process either. Jonah was told
  before this went up and asked for it to ship anyway.

- **0.0.7 build 1.** Uploaded at 08:58 EDT on 2026-09-06 from commit `cdfff93` with a clean
  tree. It carries one change and it is the one 0.0.6 was meant to carry: taps landing in
  the gaps between the key caps now register. 0.0.6's `hitTest` override was necessary and
  not sufficient, because a keyboard extension draws in its own process and is composited
  by another one, and the compositing process decides which touches to forward by what was
  drawn — so a region left fully transparent was never offered to the extension at all.
  The evidence, in the order it was taken: a probe on the first line of `hitTest` showing
  that taps at x = 42 and 44 across the q/w boundary never called it while the six either
  side did; the same x = 42 reaching `hitTest` in the suggestion bar and in rows 1 and 2
  and failing at every height inside row 0, which is the only row where it falls in a
  drawn gap; three builds measured against the same eight taps, no fill six of eight,
  `.clear` six of eight, alpha 1/255 eight of eight; the field reading "Qqqqww" before and
  "Qqqqqwww" after; and the plate sampled at the q/w gap with and without the fill, which
  reads `#171717` either way in dark and `#E1E3E7` either way in light, so the fill is
  invisible in both appearances. 81 tests passing, one of them new and standing in for a
  property no unit test can reach.

  **Still unproven on a device:** multi-touch at real typing speed, which needs his phone
  and cannot be exercised here. Fixed in 0.0.6, unit-green, never typed on fast.

- **0.0.8 build 1.** Uploaded at 10:27 EDT on 2026-09-06 from commit `1d83880` with a clean
  tree, 82 tests passing. It carries the key preview, which Jonah had reported twice: "the
  preview bubble is still not reliably showing when a tap matches a key" and "the
  confirmation bubble is still poorly sized and placed".

  **Not reliably showing** was one shared preview view between all fingers. Until 0.0.6 the
  keyboard had multi-touch off, so UIKit delivered one finger and discarded the rest and
  there was never a second preview to draw; turning multi-touch on removed that accidental
  guarantee and left the single view behind. A second finger retargeted the first finger's
  preview instead of adding one, and the first finger lifting hid it while the second was
  still down. There is now one preview per touch, keyed by the touch.

  **Poorly sized and placed** was four separate errors, each found by measuring against
  stock in the same Contacts field on a 430pt simulator rather than by looking at the two
  side by side. The shoulders were the cap corner's radius doubled, 42px, against stock's
  36. The letter was 25.2pt, the size of the one on the cap, against stock's 37.5. The
  letter was centred in the bulb, which no label can be, because a label centres its line
  box. And the shape had a parallel-sided stem taken from one row's reading of a silhouette
  that narrows the whole way down, which put it 14px per side too wide where it meets the
  key. It is one path now and it reads within a pixel of stock from the top of the bulb to
  y 2065 and within 3 to 4px a side at its worst. SPEC.md A.19 has every number.

  **And one defect found while checking the fix**: on the top row, where there is not room
  for the full rise, the whole preview had been pushed down rather than shortened, which
  hung its foot a third of a cap below the letter it was announcing. It shortens now.

  **Still unproven on a device:** multi-touch at real typing speed, which needs his phone.
  Also unmeasured: the preview at 402pt and in light appearance.

- **0.0.9 build 1.** Uploaded at 10:53 EDT on 2026-09-06 from commit `11634e6` with a clean
  tree, 91 tests passing. Two changes, both of them things Jonah asked for that morning.

  **The space bar says what keyboard this is.** Stock leaves a faint mark in the
  bottom-right of its own space bar and this puts the name and version there in the same
  treatment — measured, not styled: 28px of cap height at 3x, ending 18px from the right
  edge and 18px from the bottom, at the white the caps letter with at alpha 0.30, which
  lands on `#777777` against stock's `#787878`. It is also the identity check that catches
  a simulator quietly reverting to the system keyboard, which had already produced one
  stock-against-stock measurement that came back perfect. SPEC.md A.19 has the numbers.

  **The space bar is a point in the constellation.** It was not one, and could not have
  been: the candidate pool was the letter keys, so a tap on a letter could never be scored
  as a space and a tap on the space bar was not scored at all. Adding it alone would have
  changed nothing, because the cost function divided every horizontal distance by one
  column pitch and the space bar is 615px wide against a letter's 109 — a tap 13px inside
  its own left edge scored 2.32 to space and 1.32 to `x` one row up. The normalizer now
  belongs to the key being measured to, which is identity for a key of the standard letter
  width, so no letter-to-letter score moves and no tuning constant changes meaning.
  SPEC.md A.20.

  **Verified in the hand.** On a 430pt simulator, `hi there` types normally; the bottom
  edge of `b` gives `b`; a tap a hair inside the space bar under `b` gives a space; and a
  tap 13px inside the space bar's left edge gives a space where it would have given `x`.

  **Not in this build, and named so it is not mistaken for done:** `isnthere` still cannot
  become `is there`, because a candidate word cannot contain a boundary. The period key is
  excluded from matching against Jonah's stated rule, as a judgment recorded in A.20 for
  him to overturn. The preview at 402pt is unmeasured, and multi-touch at real typing speed
  has still never been exercised on a device.

- **0.0.10 build 1.** Uploaded at 11:35:03 EDT on 2026-09-06 from commit `5da46b0` with a
  clean tree, 94 tests passing. Timestamp read off the export log, not from memory: the run
  started 11:33:45 and printed `Upload succeeded.` at 11:35:03, then `** EXPORT SUCCEEDED **`.
  Three changes.

  **An exact tie in the commit rule keeps what the user typed.** The rule compared the best
  candidate against the slack with `<=`, so a candidate that tied exactly replaced the
  typing. A tie means the arithmetic cannot separate the two and the two outcomes are not
  equally cheap to undo, so the typing wins. Measured at dead-centre taps, where
  `literalCost` is exactly zero and the slack is `0.5 * tapCount` and nothing else: eleven of
  thirty-one deliberate non-words were being rewritten on space, and six of those were exact
  ties — including `jonah` going in as `josh` and the `isnthere` fixture going in as
  `anthers`. All six now stand. SPEC.md A.22.

  **A key preview leans inward rather than being sliced by the keyboard's edge.** The bulb is
  two thirds wider than a cap, so one centred over `q` started 16px left of the keyboard's
  own margin — where an extension cannot draw — and the input view cut it flat. Stock's sits
  fully inside with its left edge on the cap's. Exactly two letters lean now, `q` and `p`, by
  11.5px each. SPEC.md A.23.

  **The 402pt differential, which found the second of those.** Every row band on all three
  planes matches stock exactly and every cap within 1px, on the same measurement that showed
  a 37px row-1 offset a day earlier. The host was Safari's URL field rather than Contacts.

  **Verified in the hand at 402pt in both appearances**, which is the first time this
  keyboard has been exercised at that width at all: `hi there` types correctly in light and
  `hi there hi ` in dark, the letters are legible in both, and the space bar reads
  `BoreKey 0.0.10`.

  **Not in this build, and named so it is not mistaken for done:** the letters plane's space
  bar is 549px against stock's 545 and pushes the period key 2px right — left out as
  structural and recorded in A.23, and it goes to Jonah with the period-key decision it is
  related to. The candidate bar is drawn in every non-secure field including Safari's URL
  field, where stock draws none; `keyboardType` is read only to decide the period key and is
  not carried in `DocumentTraits`, so nothing else can consult it. `isnthere` still cannot
  become `is there`. Multi-touch at real typing speed has still never been exercised on a
  device.

- **0.0.11 build 1.** Uploaded at 13:17:12 EDT on 2026-09-06 from commit `9ea27c4` with a
  clean tree, 97 tests passing. Timestamp read off the export log, not from memory: the run
  started 13:16:07 and printed `Upload succeeded.` at 13:17:12, then `** EXPORT SUCCEEDED **`.
  Two changes, both of them things Jonah reported within four minutes of each other.

  **A word boundary commits the word it ends.** Reported at 12:59: a comma at the end of a
  word, then a space, and the correction that would otherwise have fired does not. The comma
  was the report and the boundary was the defect — `handle` had two ways to end a word and
  picked between them by hand at each case, and the comma, every digit and symbol on the
  numbers plane, the address-field period key and the plane key all picked the one that
  discarded the pending correction. Reproduced in two taps at 402pt and fixed by naming the
  two verbs apart. SPEC.md A.27.

  **No drop shadow under the caps.** Reported at 12:56. One declaration in `KeyCap.init`
  drew it under every key and nothing else in the project sets a shadow property. Stock
  draws none, established by scanning down a column through a cap's bottom edge: stock's
  intermediate pixels sit between cap and plate in both appearances, ours sat below the
  plate in both, and only a shadow can do that. SPEC.md A.28.

  **Verified in the hand at 402pt in both appearances**, in Contacts' search field: `hrllo`
  then a comma gives `hello,`, and the cap edges read `#FFFFFF` → `#F1F2F4` → plate in light
  and `#3D3D3D` → `#2B2B2B` → plate in dark, which is stock's profile.

  **Not in this build:** the slack formula still overwrites five words it should leave
  (`iphone`, `keybored`, `sry`, `np`, `pw`); `isnthere` still cannot become `is there`; the
  bottom row is the same in every field kind and has no emoji key; there are no long-press
  alternates and no space-bar trackpad. Also measured and not acted on: stock does not
  autocorrect in Contacts' search field and this keyboard does, because `DocumentTraits`
  never reads `autocorrectionType`.

- **0.0.12 build 1.** Uploaded at 13:38:01 EDT on 2026-09-06 from commit `e16c428` with a
  clean tree, 99 tests passing. Run started 13:36:33. One change, shipped alone on purpose
  because it alters what the keyboard does to every word typed.

  **The boundary never buys an edit.** The slack was `literalCost + 0.5 * tapCount` and an
  edit costs a flat 1.5, so from three taps up an edit was always affordable and got more
  affordable the longer the word. Measured over the whole probe set, the edit count
  separates the classes exactly: all sixteen one-key-slip fixtures reach their word with
  zero edits, and every edit-carrying candidate among the deliberate non-words is junk. So
  a correction may re-read a tap and may not invent one or throw one away. `iphone` stands
  now, and `borekey` is safe by construction rather than by half a unit out of four.
  SPEC.md A.29.

  **Not fixed, and named so it is not mistaken for done:** `keybored`, `sry`, `np` and `pw`
  are edit-free substitutions costing exactly what a genuine slip of the same length costs.
  Nothing in this scorer can separate them from the corrections that must keep firing.

  **The rule shipped wrong once between builds and the device caught it.** Written first as
  a veto on the best candidate rather than a filter over the candidates, it passed every
  test and then stopped `hrllo` correcting at 402pt; the fixtures all tap dead centre and
  cannot express it. Verified after the fix in Contacts' search field at 402pt: `hrllo` goes
  in as `hello`, `Hrllo` as `Hello`, and `iphone` stands.

- **0.0.13 build 1.** Uploaded at 13:51:20 EDT on 2026-09-06 from commit `4c86bfb` with a
  clean tree, 100 tests passing. Run started 13:50:09. One change.

  **The letter in a clipped key preview rises with the bulb.** Reported at 13:28: on the top
  row the letter is "still obscured by the finger". That bulb cannot rise its full height,
  so it is clamped, and the letter box was measured down from the bulb's top — so the letter
  followed the top down and sat over the cap. It was 15.3pt above the top row's cap against
  44.9pt on every other row at 402pt; it is 23.0pt now, with the other rows untouched. One
  expression rather than a case for the top row: the letter keeps its measured height above
  the cap, and where the bulb is too short it is centred in the room the bulb has. SPEC.md
  A.30.

  **Verified in the hand at 402pt**, pressing `e` in Contacts' search field and capturing
  280ms into the press: the letter sits at the top of the shortened bulb, clear of the row.

The tree is at 0.0.13 build 1, which is spent. Bump before archiving again.
