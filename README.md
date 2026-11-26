# MacTools — native macOS menu-bar utilities

Five lightweight menu-bar apps for macOS written in Swift without Xcode projects or third-party dependencies: every app is compiled with `swiftc` by a single build script.

**Stack:** Swift 5 · AppKit · SwiftUI · CoreGraphics · AVFoundation · ScreenCaptureKit · Objective-C bridge · Bash

| App | What it does |
|---|---|
| **Orbit** | Window manager: snap layouts and hotkeys, command palette (⇧⌘Space) with calculator and quick actions, focus tracker with daily reports |
| **Reel** | Screen recorder with automatic zoom that follows the cursor, built-in editor and headless re-export |
| **NotchDeck** | Dynamic-Island-style widget: universal *Now Playing* controls via a MediaRemote bridge, custom volume / brightness HUD (CGEventTap) |
| **Shifty** | Drag-and-drop file converter plus lightweight photo and video editors |
| **Awake** | Keeps the Mac awake for long-running tasks and AI agents, including a lid-closed mode |

`Shared/` contains the common design system, global hotkey handling and status-bar icons.

## Build

Requires macOS 15+ on Apple Silicon and Xcode Command Line Tools.

```bash
./build.sh            # build and install all apps to /Applications
./build.sh Orbit Reel # build only selected apps
```

Apps are ad-hoc signed with an identifier-based designated requirement, so macOS privacy permissions (Accessibility, Screen Recording) survive rebuilds.

## Notes

- NotchDeck's Now Playing bridge (`NotchDeck/Bridge`) is a small Objective-C dynamic library loaded by the system `perl` binary, because macOS 15.4+ only exposes MediaRemote data to Apple-signed processes.
- Designed to stay light on CPU: no background polling where system notifications are available.
