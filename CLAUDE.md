# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

20-20-20 Eye Care app — a single-screen SwiftUI app for iOS 17+. Prompts users every N minutes to look 20 feet away for 20 seconds (the 20-20-20 rule).

## Build & Run

```bash
# Generate Xcode project from project.yml
xcodegen generate --project .

# Open in Xcode
open EyeCare20.xcodeproj

# Build (unsigned, for sideloading)
xcodebuild build \
  -project EyeCare20.xcodeproj \
  -scheme EyeCare20 \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Package .ipa
mkdir -p Payload && cp -r "build/Build/Products/Release-iphoneos/EyeCare20.app" Payload/
zip -r "EyeCare20.ipa" Payload/
```

CI builds run via GitHub Actions (`.github/workflows/build.yml`) on `macos-latest`, producing an unsigned `.ipa` artifact.

## Project structure

```text
project.yml          — XcodeGen project spec (do NOT commit .xcodeproj)
gen_sounds.js        — Node.js script that generates alert.wav / complete.wav
20-20-20护眼/
  App.swift          — @main entry point, creates TimerManager environmentObject
  ContentView.swift  — All UI views in one file (HeaderView, TimerView,
                       CircularProgressView, ControlsView, StatsView,
                       SettingsToggleView, RestOverlayView)
  TimerManager.swift — All business logic: timer state machine, notifications,
                       background/foreground handling, UserDefaults persistence
  alert.wav          — Rest-start notification sound (generated)
  complete.wav       — Rest-end notification sound (generated)
  Assets.xcassets/   — App icon assets
  Info.plist         — Bundle config (zh_CN locale, portrait only, iOS 17+)
```

## Architecture

**TimerManager** (`@MainActor`, `ObservableObject`) is the single source of truth. All views read from it via `@EnvironmentObject var tm: TimerManager`.

Three phases: `.idle` → `.working` → `.resting` → `.working` → ...

- Timer ticks every 0.2s, tracks `Date` deadline (not cumulative seconds), so it survives background suspend.
- On `returnedToForeground()`, compares deadline to `Date()` — if overshoot is less than the rest duration, the rest timer adjusts; otherwise it auto-advances to the next work cycle.
- State persisted via `UserDefaults` (phase, deadline, isRunning, overlay state). Daily cycle counts keyed by `yyyy-MM-dd`.
- Notifications use `UNUserNotificationSound(named:)` with custom `.wav`/`.caf` sound files.

**ContentView** is a `ZStack` with layered overlays: screen flash (green tint on rest start), rest overlay (full-screen green backdrop), rest-end toast. A `SettingsToggleView` expandable section lets users pick work minutes (1-120) and rest seconds (5/10/15/20/25/30/45/60/90/120).

## Key conventions

- All strings in Chinese (zh_CN)
- No `.xcodeproj` committed — regenerate via `xcodegen generate --project .`
- Custom sounds generated via `node gen_sounds.js` (run from the project root, writes into the source directory)
- `DEVELOPMENT_TEAM` intentionally empty (unsigned builds for sideloading)
- Dark mode toggle persisted in UserDefaults
- Haptic feedback: `UINotificationFeedbackGenerator` on phase transitions
- Bundle ID: `com.luludad.eye20`, deployment target iOS 17.0
