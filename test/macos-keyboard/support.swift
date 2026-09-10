import Foundation
#if os(macOS)
import Cocoa
import GhosttyKit
#endif

// Only availability is substituted in temporary test copies of the source.
// No platform override or test seam is added to the application.
enum TestPlatform { static var modern = false }

// Adapter for the standalone source test, not a test of Ghostty.ghosttyMods.
// The production mapper is outside the two files under test.
enum Ghostty {
    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var bits: UInt32 = 0
        if flags.contains(.shift) { bits |= 1 }
        if flags.contains(.control) { bits |= 2 }
        if flags.contains(.option) { bits |= 4 }
        if flags.contains(.command) { bits |= 8 }
        if flags.contains(.capsLock) { bits |= 16 }
        return ghostty_input_mods_e(rawValue: bits)
    }
}

var checks = 0
var failures: [String] = []
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message); print("FAIL: \(message)") }
}
func finish() {
    print("RESULT: \(checks) checks, \(failures.count) failures")
    exit(failures.isEmpty ? 0 : 1)
}
