# Qove

A menu-bar window manager for macOS.

- **Keyboard mode** — press ⌥⌘, then use ←↑→↓ to move the window over a grid, ⇧/⌥ + arrows to grow/shrink, ⌘ + arrows to jump to an edge, Space to select a range, F to fill, 1–9 to run a control, ⇥ for the next display, ↩ to finish, ⎋ to cancel.
- **Green-button palette** — hover over any window's green button for preset layouts and a drag-to-resize grid.
- **Controls** — named layouts (fractions of the screen, center, next/previous display, revert) with global shortcuts, editable in Preferences.

## Build

Requires macOS 13+ and the Swift toolchain (Xcode Command Line Tools are enough).

```sh
./build.sh          # produces build/Qove.app
open build/Qove.app
```

Grant Qove access in System Settings → Privacy & Security → Accessibility.
Ad-hoc signatures change on every build, so macOS forgets that grant after a rebuild;
set `SIGN_IDENTITY` to a code-signing identity to keep it.
