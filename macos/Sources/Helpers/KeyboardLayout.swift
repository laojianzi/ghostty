import Carbon
import Cocoa

class KeyboardLayout {
    /// Return a string ID of the current keyboard input source.
    static var id: String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let sourceIdPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceId = unsafeBitCast(sourceIdPointer, to: CFString.self)
            return sourceId as String
        }

        return nil
    }

    /// Translate a physical key through the current keyboard layout without
    /// asking AppKit to reinterpret an NSEvent.
    ///
    /// Control is intentionally ignored; Ghostty encodes control characters.
    /// Command is preserved for layouts such as Dvorak-QWERTY Command.
    static func characters(
        for keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawLayoutData = TISGetInputSourceProperty(
                source,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>
            .fromOpaque(rawLayoutData)
            .takeUnretainedValue() as Data

        var modifierState: UInt32 = 0
        if modifiers.contains(.command) { modifierState |= UInt32(cmdKey >> 8) }
        if modifiers.contains(.shift) { modifierState |= UInt32(shiftKey >> 8) }
        if modifiers.contains(.option) { modifierState |= UInt32(optionKey >> 8) }
        if modifiers.contains(.capsLock) { modifierState |= UInt32(alphaLock >> 8) }

        let maxLength = 4
        var deadKeyState: UInt32 = 0
        var translated = [UniChar](repeating: 0, count: maxLength)
        var translatedCount = 0
        let status = layoutData.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                maxLength,
                &translatedCount,
                &translated
            )
        }

        guard status == noErr, translatedCount > 0 else { return nil }
        return String(utf16CodeUnits: translated, count: translatedCount)
    }
}
