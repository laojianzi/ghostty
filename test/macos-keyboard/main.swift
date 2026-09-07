// Boundary tests, NOT macOS runtime/IME tests. See README.md.
import Foundation

typealias Mods = NSEvent.ModifierFlags
let flags: [Mods] = [.shift, .control, .option, .command, .capsLock]

TestPlatform.modern = false
for mask in 0..<32 {
    Fixture.reset()
    var mods: Mods = []
    for i in 0..<5 where mask & (1 << i) != 0 { mods.insert(flags[i]) }
    let expected: UInt32 = (mods.contains(.shift) ? 2 : 0)
        | (mods.contains(.option) ? 8 : 0)
        | (mods.contains(.command) ? 1 : 0)
        | (mods.contains(.capsLock) ? 4 : 0)
    _ = KeyboardLayout.characters(for: 0, modifiers: mods)
    check(Fixture.lastModifiers == expected, "Carbon modifier forwarding mask=\(mask)")

    for type in [NSEvent.EventType.keyDown, .keyUp] {
        Fixture.reset()
        // The supplied NSEvent text must NOT be used as its unshifted identity.
        let event = NSEvent(0, mods, "A", "A")
        event.type = type
        let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        check(key.unshifted_codepoint == 97, "unshifted a mask=\(mask) type=\(type)")
        check(Fixture.lastModifiers == 0, "unshifted lookup removes ALL modifiers mask=\(mask)")
        check(event.nativeCalls.isEmpty, "legacy lookup must not call AppKit mask=\(mask)")
        check(key.mods.rawValue == Ghostty.ghosttyMods(mods).rawValue, "original modifiers preserved")
        check(key.text == nil && !key.composing, "mapper must not fabricate text/composition")
    }
}

Fixture.reset()
Fixture.commandSensitive = true
let command = NSEvent(8, [.control, .command], "\u{3}", "j")
check(command.ghosttyCharacters == "c", "Ctrl+Command recovers command-layout character")
check(command.nativeCalls.isEmpty, "control recovery must not call legacy AppKit")

Fixture.reset()
let ctrlShift = NSEvent(8, [.control, .shift], "\u{3}", "C")
Fixture.text = "C"
check(ctrlShift.ghosttyCharacters == "C", "Ctrl+Shift text recovery")
check(Fixture.lastModifiers == 2, "text recovery strips Control, keeps Shift")

for mods: Mods in [[.control, .option], [.control, .option, .command, .capsLock], [.control]] {
    Fixture.reset()
    let event = NSEvent(0, mods, "\u{1}", "a")
    _ = event.ghosttyCharacters
    let expected = Ghostty.ghosttyMods(mods.subtracting(.control))
    check(expected.rawValue == event.ghosttyKeyEvent(GHOSTTY_ACTION_REPEAT).consumed_mods.rawValue
          + (mods.contains(.command) ? 8 : 0), "consumed modifiers remain independent of translation")
}

// A failed lookup is unknown, never a shifted/Option-stripped guessed key.
for fault in ["source", "data", "status", "empty"] {
    Fixture.reset()
    switch fault {
    case "source": Fixture.sourceAvailable = false
    case "data": Fixture.dataAvailable = false
    case "status": Fixture.status = -50
    default: Fixture.text = ""
    }
    let event = NSEvent(0, [.control, .option, .shift], "\u{1}", "A")
    check(event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS).unshifted_codepoint == 0,
          "failed unshifted lookup stays unknown: \(fault)")
    check(event.ghosttyCharacters == nil, "failed text lookup must not discard Option: \(fault)")
    check(event.nativeCalls.isEmpty, "failure must not invoke unsafe native fallback")
}

// Unicode scalar, not Character.count (one grapheme may have several scalars).
for (text, expected): (String, UInt32) in [
    ("a", 97), ("é", 233), ("😀", 0x1F600), ("e\u{301}", 0), ("ab", 0), ("", 0)
] {
    Fixture.reset(); Fixture.text = text
    let event = NSEvent(0, [.control])
    check(event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS).unshifted_codepoint == expected,
          "single scalar contract: \(text.debugDescription)")
}

Fixture.reset()
for code: UInt16 in [0, 8, 12] { _ = KeyboardLayout.characters(for: code) }
check(Fixture.deadStates == [0, 0, 0], "translation must not carry dead-key state between queries")
check(Fixture.options == [1, 1, 1], "no-dead-keys MASK, not bit index")
Fixture.keyboardType = 41
_ = KeyboardLayout.characters(for: 0)
check(Fixture.receivedKeyboardType == 41, "keyboard type is forwarded")
Fixture.text = "b"
check(KeyboardLayout.characters(for: 0) == "b", "layout change cannot return cached text")

Fixture.reset()
let modifier = NSEvent()
modifier.type = .flagsChanged
check(modifier.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE).unshifted_codepoint == 0, "modifier-only event")
check(Fixture.calls == 0 && modifier.nativeCalls.isEmpty, "modifier-only must not translate")

for text: String? in [nil, "", "text", "你好", "e\u{301}", "😀"] {
    Fixture.reset()
    let event = NSEvent(0, [], text)
    check(event.ghosttyCharacters == text, "ordinary/committed text is untouched")
    check(Fixture.calls == 0, "committed text must not be retranslated")
}
for codepoint: UInt32 in [0xF700, 0xF8FF] {
    let event = NSEvent(0, [], String(UnicodeScalar(codepoint)!))
    check(event.ghosttyCharacters == nil, "function key PUA is filtered")
}

// Modern routing still forwards [] for identity and only removes Control for text.
TestPlatform.modern = true
Fixture.reset()
let modern = NSEvent(8, [.control, .command, .shift], "\u{3}")
modern.nativeResult = "c"
let key = modern.ghosttyKeyEvent(GHOSTTY_ACTION_REPEAT)
check(key.unshifted_codepoint == 99 && key.action == GHOSTTY_ACTION_REPEAT, "modern codepoint/action")
check(modern.nativeCalls == [[]], "modern unshifted request")
modern.nativeResult = "C"
check(modern.ghosttyCharacters == "C", "modern recovered text")
check(modern.nativeCalls.last == [.command, .shift], "modern text retains Command and Shift")
check(Fixture.calls == 0, "modern branch does not use legacy translator")
finish()
