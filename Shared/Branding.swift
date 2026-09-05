// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import Foundation

/// The user-facing name of the app, read from the bundle rather than written down here.
///
/// The project, the targets, the bundle identifiers and the repository are all KeyBored.
/// What a person sees is BoreKey: the app on the home screen, and the keyboard in
/// Settings and on the globe key. Those are two different names on purpose, and only
/// this one is a brand.
///
/// It is written in exactly one place — `PRODUCT_DISPLAY_NAME` in `project.yml`, which
/// feeds `INFOPLIST_KEY_CFBundleDisplayName` for all three targets — and read back from
/// whichever bundle this code was compiled into. That is the same arrangement
/// `KeyBoredVersion` uses for `MARKETING_VERSION`, and for the same reason: a literal
/// repeated in an Info.plist and a Swift file is two places to forget.
public enum Branding {
  public static var displayName: String {
    Bundle(for: BundleToken.self).infoDictionary?["CFBundleDisplayName"] as? String
      ?? "unknown"
  }
}

/// Resolves to whichever bundle this code was compiled into. See `EnglishLexicon`.
private final class BundleToken {}
