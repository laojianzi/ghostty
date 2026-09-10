#!/bin/bash
# Compile against Apple's actual SDK and the repository's actual C ABI header.
set -euo pipefail
if [[ $(uname -s) != Darwin ]]; then
    echo "Native checks require macOS and Xcode command-line tools." >&2
    exit 2
fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE="$ROOT/test/macos-keyboard"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="$(uname -m)-apple-macosx12.0"
mkdir -p "$TMP/GhosttyKit"
cp "$ROOT/include/ghostty.h" "$TMP/GhosttyKit/ghostty.h"
printf 'module GhosttyKit { header "ghostty.h" export * }\n' > "$TMP/GhosttyKit/module.modulemap"

# Type-check the unmodified production sources before testing forced legacy
# routing. Replacing the availability predicate is confined to a temporary file.
xcrun swiftc -swift-version 5 -target "$TARGET" -sdk "$SDK" -I "$TMP/GhosttyKit" \
    -typecheck "$HERE/support.swift" \
    "$ROOT/macos/Sources/Helpers/KeyboardLayout.swift" \
    "$ROOT/macos/Sources/Ghostty/NSEvent+Extension.swift"
sed 's/if #available(macOS 14, \*)/if TestPlatform.modern/g' \
    "$ROOT/macos/Sources/Ghostty/NSEvent+Extension.swift" > "$TMP/Event.swift"
cp "$HERE/native.swift" "$TMP/main.swift"
for OPT in -Onone -O; do
    xcrun swiftc -whole-module-optimization -swift-version 5 "$OPT" \
        -target "$TARGET" -sdk "$SDK" -I "$TMP/GhosttyKit" \
        "$HERE/support.swift" "$ROOT/macos/Sources/Helpers/KeyboardLayout.swift" \
        "$TMP/Event.swift" "$TMP/main.swift" -o "$TMP/check"
    echo "=== native $OPT ==="
    "$TMP/check"
done
