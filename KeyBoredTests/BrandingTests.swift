// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import Testing

@testable import KeyBored

/// The brand appears in exactly two places in this repository: `PRODUCT_DISPLAY_NAME` in
/// `project.yml`, and the literal below.
///
/// The literal is deliberate and is not a second source. It is the assertion that the
/// build setting actually reached the bundle, which nothing else checks — an empty or
/// missing `CFBundleDisplayName` builds, installs and runs, and shows the target name in
/// Settings instead of the brand. Renaming the app is therefore two edits, and doing only
/// the first fails here loudly rather than shipping a keyboard called something else.
@Test func theBundleCarriesTheBrand() {
  #expect(Branding.displayName == "BoreKey")
}

/// The space bar's corner mark is the only place the version is visible on a phone, so
/// it is the only place a bundle key going missing would show — and it would show as the
/// word "unknown" sitting on the keyboard rather than as anything failing. Both halves
/// are read off the bundle by design; this is what notices when the bundle stops
/// carrying them.
@MainActor
@Test func theSpaceBarMarkNamesTheKeyboardAndTheVersionItIs() {
  let mark = KeyboardView.spaceBarMark
  #expect(mark.hasPrefix("BoreKey "))
  #expect(!mark.contains("unknown"), "the mark reads \"\(mark)\", so a bundle key is missing")
  #expect(mark.dropFirst("BoreKey ".count).allSatisfy { $0.isNumber || $0 == "." })
}
