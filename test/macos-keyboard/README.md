# macOS keyboard compatibility checks

These tests target PR #3's unshifted-codepoint and Command-modifier regressions.
They add no test flags, caches, strategy objects, or new interfaces to the app.

## Linux: executable boundary tests and ablation

```sh
python3 test/macos-keyboard/check.py
python3 test/macos-keyboard/check.py --ablate
```

Requires Python 3 and a Swift compiler. The runner compiles the **production
Swift function bodies** with controlled AppKit/Carbon/GhosttyKit boundaries. It
only substitutes framework imports and the OS availability predicate in temporary
files, so both OS branches execute. This is NOT an AppKit, Carbon, IME, ABI, or
terminal-encoder runtime test. The fixtures model inputs and record forwarded
arguments; they are not evidence of Apple's runtime behavior.

Coverage: all 32 Shift/Control/Option/Command/Caps Lock combinations; key-down
and key-up; control-text recovery including a Command-dependent fixture; failed,
empty, BMP, non-BMP, and multi-scalar translations; original and consumed
modifiers; modifier-only events; committed text and function-key filtering;
per-query dead-key state; no-dead-keys mask; keyboard type and layout refresh;
modern/legacy routing.

Ablation recompiles each one-factor mutant and requires an assertion failure:
replace the unshifted lookup with `charactersIgnoringModifiers`; omit Command;
restore either lossy fallback; omit single-scalar validation; omit the no-dead-keys
mask. Compile errors and crashes are **not** accepted as killed mutants.

To test an older revision without changing the worktree, copy its two source
files from `git show <ref>:<path>` into a temporary directory retaining their
repository paths, then pass `--source-root <directory>` to this runner.

## macOS: actual SDK, C header, and native layout translation

```sh
bash test/macos-keyboard/native-check.sh
```

Requires Xcode command-line tools and a usable current keyboard layout. The
script type-checks unchanged sources against the actual Apple SDK and
`include/ghostty.h`, then runs debug and optimized native boundary executables.
No compiled Ghostty library is needed: only its data types are imported. The
standalone `Ghostty.ghosttyMods` adapter is not a test of that unchanged mapper.

Deployment target is 12.0 and Swift language mode is 5. This does **not** prove
compatibility with Swift 5.7/Xcode 14.1 unless that toolchain is actually selected.
The selected input source is printed; the script does not change system settings.
On macOS 14+, it compares forced-legacy output with independent native AppKit
queries. On 12/13 it never calls the affected API, checks mapping invariants, and
checks the explicit `a` identity when the current input source is ABC or US.
Repeat with ABC/US, Swiss German, Dvorak-QWERTY Command, and a dead-key layout.
Native-reference parity is explicitly reported as not run on pre-14 systems.

The focused GitHub workflow runs on macOS 15 Apple Silicon and Intel. It cannot
reproduce the macOS 12/13 OS defect and is not a substitute for the gate below.

## Human pre-merge gate: actual target system and full app

Record OS, CPU architecture, Xcode/SDK, layout, tested commit, and raw key output.
Do not mark a row passed merely because a stub or native-boundary test passed.

- Build the complete `ReleaseLocal` app using the README's Xcode 14.1 / SDK 13 /
  Zig 0.15.2 commands; run it on 12.7.6 and 13.x, Intel and Apple Silicon.
- In a clean configuration without matching consumed keybindings, capture legacy
  and Kitty protocol output (including alternate keys, report events, and report
  all) using a key inspector, then test `nvim --clean` and the affected TUI.
- Verify Ctrl+A-Z, Shift+A, Ctrl+Shift+C, Ctrl+[, Ctrl+\\, Ctrl+], Ctrl+^,
  Ctrl+_, Ctrl+/, Ctrl+Enter, and Ctrl+Space. Verify repeat and release reports.
- Test ABC/US, Swiss German, Dvorak-QWERTY Command, and dead-key layouts. Include
  Shift+1, Caps Lock, Command-dependent shortcuts, and a live layout change.
- Verify all four option-as-alt settings and Chinese/Japanese/Korean composition,
  candidate confirmation, and cancellation/backspace. Verify no duplicated input.
- Check the same scenarios on macOS 14+; multi-scalar identities now remain 0,
  matching the function's documented single-scalar contract. Modern translation
  otherwise continues to use AppKit; ordinary/committed text is unchanged.

Scope: the pre-existing `SurfaceView_AppKit` call used to construct a distinct
modifier-adjusted event is not rewritten by this PR. Its option-as-alt/IME path
is part of the full-app manual gate, not covered by the standalone boundary tests.
