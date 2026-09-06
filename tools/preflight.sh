#!/bin/bash
# Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
# Licensed under the MIT License. See LICENSE at the repository root.
# This file is permitted to be edited by AI models and agents.
#
# Refuses an upload that would repeat a failure this project has already had.
#
#     tools/preflight.sh build/KeyBored.xcarchive/Products/Applications/BoreKey.app
#
# Exits non-zero and names what is wrong. Run it between the archive and the export.
#
# **Every assertion reads the built product**, not the source. That is the whole point.
# Each of the failures below got past a green build, and several got past a full passing
# test suite, because the thing that was wrong was what the build *emitted* — a stale
# version stamp, a bundle key the generator did not write, an icon `actool` never saw. The
# source said the right thing in every case. RELEASING.md has the full account of each.
#
# The two exceptions read git rather than the product, and are here because they are also
# things this project has got wrong at the moment of uploading: a build cut from a dirty
# tree cannot be traced back to anything, and the public history has carried a private
# session URL. AGENTS.md has that one.
#
# Jonah, on the checklist this replaces, 2026-09-05: "A lot of that could be fixed with
# scrips instead of agent softness."

set -u

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: tools/preflight.sh <path to the built .app>" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

fail() {
  echo "  FAIL  $1" >&2
  failures=$((failures + 1))
}

pass() { echo "  ok    $1"; }

# Globbed rather than named: the product is called BoreKey and the target is called
# KeyBoredKeyboard, and which of those names the file carries is exactly the kind of
# thing this script exists to notice changing. There is one extension; if a second ever
# appears this stops rather than silently checking whichever sorted first.
set -- "$APP"/PlugIns/*.appex
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "  FAIL  expected exactly one app extension in $APP/PlugIns, found $#" >&2
  exit 1
fi
APPEX="$1"

# `PlistBuddy` exits non-zero and prints "Does Not Exist" for a missing key, which is what
# distinguishes an absent key from one whose value is empty. Both are failures here, but
# they are different failures and the message says which.
plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null
}

echo "preflight: $APP"

# --- versions, against the project file rather than against memory --------------------
#
# The stale-generator stamp: `project.yml` is edited, `xcodegen generate` is not run, and
# the archive goes up carrying the version that was already spent. App Store Connect
# refuses it, which is the good case; the bad case is that it does not.
want_version=$(grep -E '^ +MARKETING_VERSION:' "$HERE/project.yml" | head -1 | sed -E 's/.*"(.*)".*/\1/')
want_build=$(grep -E '^ +CURRENT_PROJECT_VERSION:' "$HERE/project.yml" | head -1 | sed -E 's/.*"(.*)".*/\1/')

got_version=$(plist "$APP" CFBundleShortVersionString)
got_build=$(plist "$APP" CFBundleVersion)

if [ "$got_version" = "$want_version" ]; then
  pass "app version $got_version matches project.yml"
else
  fail "app version is '$got_version', project.yml says '$want_version' — run xcodegen generate"
fi

if [ "$got_build" = "$want_build" ]; then
  pass "app build $got_build matches project.yml"
else
  fail "app build is '$got_build', project.yml says '$want_build' — run xcodegen generate"
fi

# The extension ships inside the app and has no record of its own, but a mismatched pair is
# rejected at upload rather than at build.
ext_version=$(plist "$APPEX" CFBundleShortVersionString)
ext_build=$(plist "$APPEX" CFBundleVersion)
if [ "$ext_version" = "$got_version" ] && [ "$ext_build" = "$got_build" ]; then
  pass "extension is $ext_version build $ext_build, same as the app"
else
  fail "extension is $ext_version build $ext_build, app is $got_version build $got_build"
fi

# --- this version and build have not already been uploaded ---------------------------
#
# RELEASING.md's version history is the record, because it is the thing a person reads and
# so is the thing that stays true. App Store Connect refuses a second upload of the same
# pair, and the refusal arrives after the whole archive has been sent.
if grep -qE "^- \*\*$got_version build $got_build\.\*\*" "$HERE/RELEASING.md"; then
  fail "$got_version build $got_build is already recorded as uploaded in RELEASING.md"
else
  pass "$got_version build $got_build is not recorded as spent"
fi

# --- the icon, which produces no warning when it is missing ---------------------------
#
# `KeyBored/AppIcon.icon` is an Icon Composer document added as an explicit file reference.
# When the reference is wrong, `actool` never sees it, the build succeeds, and App Store
# Connect rejects the upload. `CFBundleIconName` lives nested under `CFBundleIcons` rather
# than at the top level, which is why this greps the printed plist rather than asking
# PlistBuddy for a path.
if plutil -p "$APP/Info.plist" | grep -q '"CFBundleIconName" => "'; then
  pass "CFBundleIconName is present"
else
  fail "CFBundleIconName is absent — actool did not see AppIcon.icon"
fi

if [ -f "$APP/Assets.car" ]; then
  pass "Assets.car exists"
else
  fail "Assets.car is missing — nothing was compiled into the asset catalog"
fi

# --- the word list, in the extension and not only in the app --------------------------
#
# The keyboard traps at load if the bundled list is missing, so the whole keyboard is dead
# and the only symptom is that it never appears. Observed 2026-09-06 on a simulator: the
# resource was renamed on disk without regenerating the project, the extension crashed in
# `EnglishLexicon.words()` 0.66 seconds after launch, and nothing in the build said a word
# about it. **The app having the file proves nothing about the extension**, which is a
# separate bundle with its own copy phase, so both are checked.
list_name=$(sed -n 's/.*wordListResource = "\(.*\)"/\1/p' \
  "$(dirname "$0")/../Shared/EnglishLexicon.swift")
if [ -z "$list_name" ]; then
  fail "could not read wordListResource out of Shared/EnglishLexicon.swift"
else
  for bundle in "$APP" "$APP/PlugIns"/*.appex; do
    [ -d "$bundle" ] || continue
    if [ -f "$bundle/$list_name.txt" ]; then
      pass "$list_name.txt is in $(basename "$bundle")"
    else
      fail "$list_name.txt is missing from $(basename "$bundle") — the keyboard traps at load"
    fi
  done
fi

# --- orientations, checked at upload and nowhere else ---------------------------------
if plutil -p "$APP/Info.plist" | grep -A1 '"UISupportedInterfaceOrientations" =>' | grep -q 'UIInterfaceOrientation'; then
  pass "UISupportedInterfaceOrientations is non-empty"
else
  fail "UISupportedInterfaceOrientations is empty or absent — the first 0.0.1 upload died here"
fi

# --- export compliance, declared in the plist so it is not asked per build -------------
if plutil -p "$APP/Info.plist" | grep -q '"ITSAppUsesNonExemptEncryption"'; then
  pass "ITSAppUsesNonExemptEncryption is declared"
else
  fail "ITSAppUsesNonExemptEncryption is absent — every build will ask for it by hand"
fi

# --- the extension's display name, which is what a person sees on the globe key --------
#
# An app extension with no `CFBundleDisplayName` installs, appears in Settings with no name,
# and cannot be told apart on the keyboard list. It got past a green build once already.
ext_name=$(plist "$APPEX" CFBundleDisplayName)
if [ -n "$ext_name" ]; then
  pass "extension display name is '$ext_name'"
else
  fail "extension has no CFBundleDisplayName — it will be nameless in Settings"
fi

# --- git: what this build can be traced back to ---------------------------------------
if [ -z "$(git -C "$HERE" status --porcelain)" ]; then
  pass "tree is clean at $(git -C "$HERE" rev-parse --short HEAD)"
else
  fail "tree is dirty — this build cannot be traced to a commit"
  git -C "$HERE" status --short >&2
fi

# --- the public history carries project information only --------------------------------
#
# Anchored, so a commit message that merely mentions the trailer is not a hit. AGENTS.md
# has the account, and `.githooks/commit-msg` is what stops it recurring.
#
# Split into a failure and a warning on purpose, because they need different people. The
# commit being shipped is one an agent can amend on the spot, so a trailer there is a
# refusal. Older commits are published, and removing them is a force push over history
# other people may hold — Jonah's decision, not a build step. Failing the upload on those
# would block every release until he made it, which turns a hygiene problem into a
# shipping problem and teaches the next agent to pass `--no-verify` to something.
if git -C "$HERE" log -1 --format='%B' \
  | grep -qE '^Claude-Session:|^https://claude\.ai/code/session'; then
  fail "the commit being shipped carries a session trailer — amend it, and see AGENTS.md"
else
  pass "the commit being shipped has no session trailer"
fi

older=$(git -C "$HERE" log --format='%B' \
  | grep -cE '^Claude-Session:|^https://claude\.ai/code/session')
if [ "$older" -gt 0 ]; then
  echo "  warn  $older commit message(s) in the history carry a session trailer."
  echo "        Published, so removing them is a force push and is Jonah's call. AGENTS.md."
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "preflight passed: $got_version build $got_build"
  exit 0
fi
echo "preflight failed: $failures check(s). Do not upload." >&2
exit 1
