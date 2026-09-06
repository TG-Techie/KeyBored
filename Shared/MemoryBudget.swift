// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   https://developer.apple.com/documentation/os/os_proc_available_memory()

import Foundation
import os

/// What the process is using, and how much room it has left before iOS kills it.
///
/// A keyboard extension gets a much smaller memory allowance than an app and is
/// **jetsammed rather than warned** when it crosses the line: the keyboard simply fails
/// to appear, which looks to the person holding the phone exactly like the extension
/// being broken. So the number worth knowing is not the footprint on its own, it is the
/// footprint against the limit — and the limit is set by the device, is not documented,
/// and cannot be read on a simulator, which does not enforce it.
///
/// `os_proc_available_memory()` is the one instrument that answers it: public API since
/// iOS 13, returning the bytes remaining before this process's limit. Adding the two
/// together gives the limit itself. Measured 2026-09-06: the trie over the bundled
/// 75,646-word list costs 26.8 MB of the extension's ~49 MB footprint, against a ceiling
/// nobody here has measured, because no device was attached to measure it on.
public enum MemoryBudget {
  /// The process's physical footprint in bytes — the figure iOS's jetsam looks at.
  public static var footprint: UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
  }

  /// Bytes left before this process is killed for using too much.
  ///
  /// Zero means the system declined to answer rather than that there is no room; it
  /// returns 0 where there is no limit to report, which is what a simulator does.
  public static var available: UInt64 {
    UInt64(os_proc_available_memory())
  }

  /// One line, written once, in the log a connected Mac can read with
  /// `log stream --predicate 'subsystem == "com.tg-techie.app.keybored"'`.
  ///
  /// This exists to be read off a real phone. Everything about the ceiling is currently
  /// recall rather than measurement, and one line in a build somebody installs turns it
  /// into a number.
  public static func log(_ moment: String) {
    let logger = Logger(subsystem: "com.tg-techie.app.keybored", category: "memory")
    let used = footprint.map { Double($0) / 1_048_576 } ?? .nan
    let left = Double(available) / 1_048_576
    logger.notice(
      """
      \(moment, privacy: .public): footprint \(used, format: .fixed(precision: 1), privacy: .public) MB, \
      \(left, format: .fixed(precision: 1), privacy: .public) MB before the limit, \
      so the limit is \(used + left, format: .fixed(precision: 1), privacy: .public) MB
      """)
  }
}
