<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# Releasing KeyBored

Everything needed to take a fresh clone to a TestFlight build of 0.0.1, written for the
person doing the App Store Connect setup themselves.

**What is verified and what is not.** Everything under "The repository side" was run on
this machine and the output is quoted. Nothing under "Your side" was: no agent has touched
this project's App Store Connect account, no identifiers have been registered, no app
record exists, and no agreement has been accepted. Those steps are written from Apple's
documented flow, not from having done them here, and they are marked. Where a command was
not run, it says so rather than reading as tested.

## What the project emits

Read out of an actual archive with `plutil`, not from `project.yml`:

    app         com.tg-techie.app.keybored.alpha-v0-1-0
    extension   com.tg-techie.app.keybored.alpha-v0-1-0.Keyboard
    version     0.0.1  (CFBundleShortVersionString, MARKETING_VERSION)
    build       1      (CURRENT_PROJECT_VERSION)
    minimum iOS 26.0

The extension's identifier is the app's with `.Keyboard` appended, and it has to stay that
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

### The archive

    xcodebuild -scheme KeyBored -destination 'generic/platform=iOS' \
      -archivePath build/KeyBored.xcarchive archive

**This fails until the identifiers exist in your account**, and the failure is the useful
kind — it names exactly what is missing. Run verbatim on this machine, with a valid team id
in `Local.xcconfig` and nothing registered:

    error: No profiles for 'com.tg-techie.app.keybored.alpha-v0-1-0' were found: Xcode
    couldn't find any iOS App Development provisioning profiles matching
    'com.tg-techie.app.keybored.alpha-v0-1-0'.
    ** ARCHIVE FAILED **

Adding `-allowProvisioningUpdates` is what lets Xcode register the identifiers and generate
the profiles for you. It is left out of the line above on purpose: it writes to your
developer account, so it is yours to run knowingly rather than something to copy without
noticing.

That everything *except* provisioning is archive-ready was verified separately, by cutting
an archive with signing switched off:

    xcodebuild -scheme KeyBored -destination 'generic/platform=iOS' \
      -archivePath build/Unsigned.xcarchive archive CODE_SIGNING_ALLOWED=NO
    ** ARCHIVE SUCCEEDED **

The resulting archive contains `KeyBored.app` with `PlugIns/KeyBoredKeyboard.appex`
embedded and the two identifiers above. So if the signed archive fails, the cause is on the
account side, not in the project.

### The app icon is not in the archive yet

`KeyBored/Assets.xcassets/AppIcon.appiconset/Contents.json` declares one universal
1024×1024 iOS slot and no image fills it. Verified on the archive above: the built `.app`
has no `Assets.car` and its `Info.plist` has no icon keys at all.

App Store Connect rejects an upload with no app icon, so **the icon has to land before the
first upload**, not after. Drop the 1024×1024 into that slot — or open the asset catalog in
Xcode and drag it in, which writes the same thing — and re-archive. Nothing else needs
changing: `ASSETCATALOG_COMPILER_APPICON_NAME` is already set to `AppIcon` on the app
target.

## Your side — App Store Connect

**Not verified here.** No agent has touched the account, and this section is the documented
flow rather than a transcript. Expect the details to have moved since it was written.

1. **Two identifiers**, in Certificates, Identifiers & Profiles, both of type App ID:
   `com.tg-techie.app.keybored.alpha-v0-1-0` and
   `com.tg-techie.app.keybored.alpha-v0-1-0.Keyboard`. Register the app's first. Neither
   needs any capability enabled — see the note on entitlements below.
2. **One app record** in App Store Connect, for the app identifier only. The extension does
   not get its own record; it ships inside the app.
3. **Agreements.** Apple will raise whatever license and tax agreements the account has
   outstanding, and possibly a fresh developer agreement. Those are yours to read and
   accept. No agent has accepted, or may accept, anything in your name.
4. **Then archive**, with `-allowProvisioningUpdates` or by letting Xcode manage signing.
5. **Upload.** Xcode's Organizer (Window ▸ Organizer ▸ Distribute App ▸ TestFlight) is the
   path with the fewest moving parts, and it surfaces validation failures — the missing
   icon among them — before the upload rather than as an email afterwards. The CLI
   equivalent is `xcrun altool --upload-app`, which needs an API key; it is listed as an
   alternative and was not run here.
6. **Internal testing** needs no review. External testing needs Beta App Review, and a
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

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` — they are set once
under `settings.base` and apply to all three targets — then `xcodegen generate`. App Store
Connect refuses a second upload with a build number it has already seen, and it is easier
to bump before archiving than to re-cut.
