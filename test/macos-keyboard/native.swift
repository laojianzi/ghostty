// Native boundary integration tests. Does not replace interactive IME/PTY tests.
import Cocoa
import GhosttyKit

func event(_ code: UInt16, _ mods: NSEvent.ModifierFlags, _ type: NSEvent.EventType = .keyDown) -> NSEvent {
    guard let result = NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: mods,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
        context: nil, characters: "\u{1}", charactersIgnoringModifiers: "A",
        isARepeat: false, keyCode: code
    ) else { fatalError("NSEvent creation failed") }
    return result
}

let sourceID = KeyboardLayout.id ?? "unknown"
print("Native macOS \(ProcessInfo.processInfo.operatingSystemVersionString), input source \(sourceID)")
let modernOS: Bool
if #available(macOS 14, *) { modernOS = true } else { modernOS = false }
let flags: [NSEvent.ModifierFlags] = [.shift, .control, .option, .command, .capsLock]
let codes: [UInt16] = [0x00, 0x08, 0x0C, 0x12, 0x18, 0x2C] // writing-system keys

for code in codes {
    // On macOS 14+ the system API is an independent reference. Never query
    // this API on macOS 12/13, even to construct an expected test value.
    let reference: String?
    if modernOS {
        reference = event(code, []).characters(byApplyingModifiers: [])
    } else {
        reference = KeyboardLayout.characters(for: code)
    }
    check(reference != nil && !reference!.isEmpty, "layout must provide a reference for \(code)")
    let scalars = reference?.unicodeScalars
    let base = scalars?.count == 1 ? scalars!.first!.value : 0
    for mask in 0..<32 {
        var mods: NSEvent.ModifierFlags = []
        for i in 0..<5 where mask & (1 << i) != 0 { mods.insert(flags[i]) }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            TestPlatform.modern = false
            let key = event(code, mods, type).ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
            check(key.unshifted_codepoint == base, "legacy unshifted code=\(code) mask=\(mask) type=\(type)")
            if code == 0 && ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(sourceID) {
                check(key.unshifted_codepoint == 97, "ABC/US Shift+A must report a")
            }
            if modernOS {
                TestPlatform.modern = true
                let native = event(code, mods, type).ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
                check(native.unshifted_codepoint == key.unshifted_codepoint,
                      "legacy/native codepoint parity code=\(code) mask=\(mask)")
            }
        }
    }
}

// These probes use control-character event text, the same entry condition as
// ghosttyCharacters. Command is retained in the independent reference request.
if modernOS {
    let recoveryMods: [NSEvent.ModifierFlags] = [
        [.control], [.control, .shift], [.control, .command],
        [.control, .command, .shift], [.control, .capsLock], [.control, .option]
    ]
    for code: UInt16 in [0x00, 0x08, 0x0C] {
        for mods in recoveryMods {
            let expected = event(code, mods).characters(byApplyingModifiers: mods.subtracting(.control))
            TestPlatform.modern = false
            check(event(code, mods).ghosttyCharacters == expected,
                  "native recovery parity code=\(code) modifiers=\(mods.rawValue)")
        }
    }
} else {
    print("NOTE: native-reference parity requires macOS 14+; not run on this host.")
}
print("NOTE: No interactive IME, event-dispatch, or terminal encoding test was performed.")
finish()
