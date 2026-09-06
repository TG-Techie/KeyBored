// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// What building the trie over a word list costs, measured in a process that does
// nothing else.
//
//   swiftc -O -o /tmp/footprint Shared/Lexicon.swift tools/footprint.swift
//   /tmp/footprint Shared/Resources/12dicts-2of12inf-lowercase.txt
//
// It is a program rather than a test on purpose. A footprint is a differential
// measurement of a whole process, so taking one inside a test bundle measures the test
// bundle: swift-testing runs every test in one process in randomized order, and the same
// assertion in KeyBoredTests reported -80.7 MB on one run and +145.7 MB on the next, with
// the process baseline moving from 101 MB to 243 MB depending on what had run first. An
// assertion of the form `cost < 40` passes automatically on a negative cost, so that test
// was green without ever having measured anything. Measured 2026-09-06:
//
//   12dicts-3esl-lowercase      19,217 words    57,012 nodes    8.4 MB    11 ms
//   12dicts-2of12inf-lowercase  75,646 words   173,902 nodes   26.8 MB    31 ms
//
// Those are host measurements. What they cannot tell you is how much room is left, which
// is the number that decides whether iOS kills the keyboard; only a real device answers
// that, and `MemoryBudget` is what asks it there.

import Foundation

func footprintMB() -> Double {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

@main
enum Footprint {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      FileHandle.standardError.write(Data("usage: footprint <word list>\n".utf8))
      exit(2)
    }
    let path = CommandLine.arguments[1]
    let words = try String(contentsOfFile: path, encoding: .utf8)
      .split(separator: "\n").map(String.init)
    let entries = words.map { LexiconEntry(tapForm: $0) }

    let before = footprintMB()
    var lexicon: Lexicon?
    let elapsed = ContinuousClock().measure { lexicon = Lexicon(entries: entries) }
    let after = footprintMB()

    guard let lexicon else { exit(1) }
    let ms =
      Double(elapsed.components.seconds) * 1000
      + Double(elapsed.components.attoseconds) / 1e15
    print(
      String(
        format: "%@\n  %d words, %d entries, %d nodes\n  %.1f MB before, %.1f MB after, "
          + "cost %.1f MB (%.0f bytes a node)\n  built in %.0f ms",
        path, words.count, lexicon.count, lexicon.nodes.count, before, after,
        after - before,
        (after - before) * 1_048_576 / Double(lexicon.nodes.count), ms))
  }
}
