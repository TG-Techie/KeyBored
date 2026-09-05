// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import SwiftUI

/// The container app. On iOS a custom keyboard ships inside a host app, so this
/// target exists mostly to carry the extension and, later, to hold settings and
/// the enable-the-keyboard walkthrough.
@main
struct KeyBoredApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
