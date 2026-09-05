// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import Testing

@testable import KeyBored

/// The version comes from the bundle the code is running in, so this asserts the shape
/// rather than a literal — a test that hard-coded the number would have to be edited on
/// every release, which is the drift the property was changed to avoid.
@Test func marketingVersionComesFromTheBundle() {
  let version = KeyBoredVersion.marketing
  #expect(version != "unknown")
  #expect(version.split(separator: ".").count == 3)
  #expect(version.allSatisfy { $0.isNumber || $0 == "." })
}
