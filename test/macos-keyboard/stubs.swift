// Test doubles for Linux only. These are NOT implementations of AppKit/Carbon.
// The runner compiles the production Swift bodies against these controlled
// boundaries to test branching, modifier forwarding, and failure handling.
import Foundation

typealias UniChar = UInt16
typealias CFString = NSString
typealias CFData = NSData
struct UCKeyboardLayout { var fixture: UInt32 = 0 }
let cmdKey = 0x100, shiftKey = 0x200, alphaLock = 0x400, optionKey = 0x800
let kUCKeyActionDown = 0, kUCKeyTranslateNoDeadKeysMask = 1
let noErr: Int32 = 0
let kTISPropertyInputSourceID = "id", kTISPropertyUnicodeKeyLayoutData = "data"

enum Fixture {
    static var sourceAvailable = true
    static var dataAvailable = true
    static var status: Int32 = 0
    static var text = "a"
    static var output: [UInt16]?
    static var lastModifiers: UInt32?
    static var calls = 0
    static var deadStates: [UInt32] = []
    static var options: [UInt32] = []
    static var keyboardType: UInt8 = 40
    static var receivedKeyboardType: UInt32?
    static var commandSensitive = false
    static func reset() {
        sourceAvailable = true; dataAvailable = true; status = 0
        text = "a"; output = nil; lastModifiers = nil; calls = 0
        deadStates = []; options = []; keyboardType = 40
        receivedKeyboardType = nil; commandSensitive = false
    }
}

final class FixtureSource {
    let data = Data(repeating: 0, count: 8) as NSData
    let name = "fixture.layout" as NSString
}
func TISCopyCurrentKeyboardLayoutInputSource() -> Unmanaged<FixtureSource>? {
    Fixture.sourceAvailable ? .passRetained(FixtureSource()) : nil
}
func TISCopyCurrentKeyboardInputSource() -> Unmanaged<FixtureSource>? {
    TISCopyCurrentKeyboardLayoutInputSource()
}
func TISGetInputSourceProperty(_ source: FixtureSource, _ name: String) -> UnsafeMutableRawPointer? {
    if name == kTISPropertyInputSourceID { return Unmanaged.passUnretained(source.name).toOpaque() }
    return Fixture.dataAvailable ? Unmanaged.passUnretained(source.data).toOpaque() : nil
}
func LMGetKbdType() -> UInt8 { Fixture.keyboardType }
func UCKeyTranslate(
    _ layout: UnsafePointer<UCKeyboardLayout>?, _ code: UInt16,
    _ action: UInt16, _ modifiers: UInt32, _ keyboardType: UInt32,
    _ options: UInt32, _ dead: UnsafeMutablePointer<UInt32>,
    _ capacity: Int, _ count: UnsafeMutablePointer<Int>,
    _ output: UnsafeMutablePointer<UInt16>
) -> Int32 {
    Fixture.calls += 1; Fixture.lastModifiers = modifiers
    Fixture.deadStates.append(dead.pointee); Fixture.options.append(options)
    Fixture.receivedKeyboardType = keyboardType
    dead.pointee = 17 // A subsequent independent query must start from zero.
    if Fixture.status != noErr { return Fixture.status }
    // Deliberately artificial command-dependent layout: Command changes j to c.
    let text = Fixture.commandSensitive ? (modifiers & 1 == 0 ? "j" : "c") : Fixture.text
    let units = Fixture.output ?? Array(text.utf16)
    guard units.count <= capacity else { return -25340 }
    count.pointee = units.count
    for (i, unit) in units.enumerated() { output[i] = unit }
    return noErr
}

final class NSEvent {
    struct ModifierFlags: OptionSet {
        let rawValue: UInt
        static let capsLock = Self(rawValue: 1 << 16)
        static let shift = Self(rawValue: 1 << 17)
        static let control = Self(rawValue: 1 << 18)
        static let option = Self(rawValue: 1 << 19)
        static let command = Self(rawValue: 1 << 20)
    }
    enum EventType { case keyDown, keyUp, flagsChanged }
    var type: EventType = .keyDown
    let keyCode: UInt16
    let modifierFlags: ModifierFlags
    let characters: String?
    let charactersIgnoringModifiers: String?
    var nativeResult: String? = "native"
    var nativeCalls: [ModifierFlags] = []
    init(_ code: UInt16 = 0, _ mods: ModifierFlags = [], _ text: String? = "a", _ ignoring: String? = "a") {
        keyCode = code; modifierFlags = mods; characters = text
        charactersIgnoringModifiers = ignoring
    }
    func characters(byApplyingModifiers mods: ModifierFlags) -> String? {
        nativeCalls.append(mods)
        return nativeResult
    }
}

// Data-only GhosttyKit stand-ins. Native tests import the real include/ghostty.h.
typealias ghostty_input_action_e = Int32
let GHOSTTY_ACTION_RELEASE: Int32 = 0, GHOSTTY_ACTION_PRESS: Int32 = 1, GHOSTTY_ACTION_REPEAT: Int32 = 2
struct ghostty_input_mods_e { var rawValue: UInt32 = 0 }
struct ghostty_input_key_s {
    var action: ghostty_input_action_e = 0
    var keycode: UInt32 = 0
    var text: UnsafePointer<CChar>?
    var composing = false
    var mods = ghostty_input_mods_e()
    var consumed_mods = ghostty_input_mods_e()
    var unshifted_codepoint: UInt32 = 0
}
