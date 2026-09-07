#!/usr/bin/env python3
"""Compile production Swift bodies with deterministic OS-boundary stubs.

No AppKit runtime, Carbon layout behavior, or terminal encoder is simulated as
proof of a native fix. Only the imports and OS availability predicate are
substituted in temporary source copies. Production files are never rewritten.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
EVENT = pathlib.Path("macos/Sources/Ghostty/NSEvent+Extension.swift")
LAYOUT = pathlib.Path("macos/Sources/Helpers/KeyboardLayout.swift")


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("Mutation anchor must occur exactly once: " + repr(old))
    return text.replace(old, new, 1)


def compile_and_run(event, layout, swiftc, name, optimize=False):
    with tempfile.TemporaryDirectory(prefix="ghostty-keyboard-") as tmp:
        tmp = pathlib.Path(tmp)
        # Availability is replaced only so both paths can be exercised on Linux.
        event = event.replace("if #available(macOS 14, *)", "if TestPlatform.modern")
        for module in ("Cocoa", "Carbon", "GhosttyKit"):
            event = event.replace("import " + module + "\n", "")
            layout = layout.replace("import " + module + "\n", "")
        (tmp / "Event.swift").write_text("import Foundation\n" + event)
        (tmp / "Layout.swift").write_text("import Foundation\n" + layout)
        exe = tmp / "check"
        build = subprocess.run([
            swiftc, "-whole-module-optimization", "-swift-version", "5",
            "-O" if optimize else "-Onone", "-o", str(exe),
            str(HERE / "stubs.swift"), str(HERE / "support.swift"),
            str(tmp / "Event.swift"), str(tmp / "Layout.swift"), str(HERE / "main.swift"),
        ], capture_output=True, text=True, timeout=60)
        if build.returncode:
            raise RuntimeError(name + " did not compile:\n" + build.stdout + build.stderr)
        run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=15)
        print("=== " + name + " ===")
        print(run.stdout, end="")
        if run.stderr:
            print(run.stderr, file=sys.stderr)
        if run.returncode not in (0, 1):
            raise RuntimeError(name + " crashed rather than reporting assertions")
        return run.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=pathlib.Path, default=ROOT)
    parser.add_argument("--ablate", action="store_true", help="require each single-factor mutant to fail")
    parser.add_argument("--optimize", action="store_true", help="also support optimized Swift compilation")
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("This is the Linux boundary suite; use native-check.sh on macOS")
    swiftc = shutil.which("swiftc")
    if not swiftc:
        parser.error("swiftc is required")
    event = (args.source_root / EVENT).read_text()
    layout = (args.source_root / LAYOUT).read_text()
    if compile_and_run(event, layout, swiftc, "production", args.optimize):
        return 1
    if args.ablate:
        variants = [
            ("remove-unshifted-fix", replace_once(event,
                "chars = KeyboardLayout.characters(for: keyCode)",
                "chars = charactersIgnoringModifiers"), layout),
            ("remove-command-bit", event, replace_once(layout,
                "        if modifiers.contains(.command) { modifierState |= UInt32(cmdKey >> 8) }\n", "")),
            ("restore-unshifted-fallback", replace_once(event,
                "chars = KeyboardLayout.characters(for: keyCode)",
                "chars = KeyboardLayout.characters(for: keyCode) ?? charactersIgnoringModifiers"), layout),
            ("restore-text-fallback", replace_once(event,
                "                    modifiers: translationMods\n                )",
                "                    modifiers: translationMods\n                ) ?? charactersIgnoringModifiers"), layout),
            ("remove-scalar-check", replace_once(event,
                "               chars.unicodeScalars.count == 1,\n", ""), layout),
            ("remove-no-dead-keys-mask", event, replace_once(layout,
                "UInt32(kUCKeyTranslateNoDeadKeysMask)", "UInt32(0)")),
        ]
        for name, mutant_event, mutant_layout in variants:
            if compile_and_run(mutant_event, mutant_layout, swiftc, name, args.optimize) == 0:
                raise RuntimeError("Surviving mutant: " + name)
        print("ABLATION: all " + str(len(variants)) + " mutants rejected")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
