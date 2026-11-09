# Caffeinator

A tiny macOS menu bar wrapper for `/usr/bin/caffeinate`.

## Usage

- **Click** the cup to add time: 15m → 30m → 1h → 2h → 4h → 8h → ∞ → off.
- **Right-click** (or ctrl-click) for the menu: pick a duration, turn off, toggle *Keep Display Awake*, toggle *Launch at Login*, or quit.
- The menu bar shows a filled cup and the time remaining (`45s`, `59m`, `1h05`, `∞`) while active.

`caffeinate` runs with `-i` (and `-d` when *Keep Display Awake* is on) plus `-w <app pid>`, so it stops if the app quits or crashes.

## Build

Requires the Xcode command line tools (macOS 13+).

```sh
./build.sh               # builds a universal app and installs to ~/Applications
./build.sh --no-install  # build only, output in build/Caffeinator.app
```

Optional launch argument: `--start [minutes]` starts caffeinating immediately (indefinitely if no minutes are given).
