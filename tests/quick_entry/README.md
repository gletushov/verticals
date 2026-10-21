# Quick Entry checks

`python3 -m unittest discover -s tests/quick_entry -v`

The Python checks use a temporary state folder. A recording Chat boundary checks dispatch and HTTP idempotency; it does not stand in for live API/agent acceptance.

`swiftc -o /tmp/quick-entry-keys desktop/macos/QuickEntryKeys.swift tests/quick_entry/keys.swift && /tmp/quick-entry-keys`

Before implementation the gesture check failed at “Fn alone must open after release”; after implementation it checks isolated Fn, other keys and modifiers, release order, and duplicate events.

On macOS, start the isolated desktop gateway on 8388, then compile `QuickEntry.swift`, `QuickEntryKeys.swift`, and `native_smoke.swift` together. This opens a real AppKit panel, sends Cmd+Return through its text view, checks Escape, and forces a network error. It writes two PNGs to `/tmp/quick-entry-evidence`. It creates one synthetic Inbox note in that gateway. It does not test a physical Fn press or Spaces; those need native permissions and owner acceptance.
