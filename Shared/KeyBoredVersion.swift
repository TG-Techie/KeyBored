// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import Foundation

/// The version, read from the bundle rather than written down here.
///
/// It used to be a string literal that had to be kept in step with `MARKETING_VERSION`
/// in `project.yml` by hand. Two places holding one number is two places to forget, so
/// this reads the one the build actually stamped.
public enum KeyBoredVersion {
  public static var marketing: String {
    Bundle(for: BundleToken.self).infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "unknown"
  }
}

/// Resolves to whichever bundle this code was compiled into. See `EnglishLexicon`.
private final class BundleToken {}
