# TestPilot macOS App — Design Spec

**Date:** 2026-04-08
**Status:** Approved

## Overview

A native macOS SwiftUI window app that wraps the `testpilot analyze` CLI, making it accessible to non-technical users (designers, PMs) without requiring terminal knowledge. The app bundles the `testpilot` bash script, detects connected devices automatically, and presents a polished animated running state.

---

## App Type & Build

- **Type:** Regular macOS window app (shows in Dock)
- **UI Framework:** SwiftUI
- **Build system:** Xcode project at `mac-app/TestPilot.xcodeproj`
- **Location in repo:** `mac-app/` directory at the repo root
- **Bundled resource:** The `testpilot` bash script is included in `Bundle.main` and executed via `Foundation.Process`

---

## Window Layout

Single resizable window (~720×520pt minimum) using `NavigationSplitView`:

- **Sidebar** (narrow, always visible): three items — "New Analysis", "History", "Settings"
- **Detail pane** (main area): swaps content based on sidebar selection or app state

The "Running" state replaces the "New Analysis" detail view in-place (same navigation slot, not a new screen).

---

## Views

### 1. Run Form ("New Analysis")

The primary screen. Divided into required fields and an optional advanced section.

**Required fields:**
- **Platform** — segmented picker: `iOS` / `Android`
- **Device** — dropdown auto-populated by platform:
  - iOS: booted simulators (`xcrun simctl list devices --json`) + connected physical devices (`xcrun devicectl list devices`)
  - Android: connected devices/emulators (`adb devices`)
  - Refresh button (↺) next to the dropdown
- **App name** — text field (e.g. "Pharmia")
- **Objective** — multi-line text editor, 3–4 rows, with placeholder text

**Advanced** (collapsible `DisclosureGroup`):
- Language — picker: `en` / `pt-BR` (default: `en`)
- Max steps — stepper, default: 20
- Output path — text field + folder picker button (default: `~/Desktop/report.html`)
- Provider override — picker: Anthropic / OpenAI / Gemini (falls back to Settings value)

**Run button:** Full-width, primary style. Disabled until platform, device, app name, and objective are all filled.

Device list refreshes automatically when the app becomes frontmost (e.g. user returns from Simulator.app).

---

### 2. Running State (Animation)

Replaces the Run form when analysis is in progress.

**Layout (centered, full detail pane):**
- Top: small label — app name + truncated objective
- Center: looping SwiftUI animation — a robot holding/reading a smartphone (screen glow, arm movement, "thinking" indicator). Built with `TimelineView` + custom SwiftUI shapes/paths. No external animation libraries.
- Below animation: single status line cycling through messages parsed from subprocess stdout (e.g. "Capturing screenshot 3…", "Navigating to login screen…")
- Bottom: "Cancel" button — sends `SIGTERM` to the subprocess

**On completion:**
- Animation fades out → checkmark + "Analysis complete"
- "Open Report" button — opens the `.html` file in the default browser
- "Run Another" button — returns to the Run form
- Run is automatically appended to History

---

### 3. History

Lightweight list of recent runs.

**Each row:**
- App name + platform badge (iOS / Android)
- Truncated objective
- Relative timestamp ("2 hours ago")
- "Open Report" button — opens `.html` in default browser; shows inline error if file no longer exists

**Storage:** JSON array at `~/Library/Application Support/TestPilot/history.json`. Maximum 50 entries; oldest are dropped automatically when the limit is exceeded.

---

### 4. Settings

A SwiftUI `Form` with two sections:

**Section 1 — AI Provider:**
- Provider picker: Anthropic / OpenAI / Gemini
- API Key — `SecureField`, stored in Keychain
- Team ID — text field (required for physical iOS devices)

**Section 2 — Raw .env (collapsible `DisclosureGroup`):**
- Plain text editor showing the contents of `~/.testpilot/.env`
- Edits sync bidirectionally with the individual fields above
- Allows power users to paste a full `.env` block; casual users use the form fields

The `.env` file at `~/.testpilot/.env` is a portability convenience (shareable with the CLI). At runtime, the app always injects `TESTPILOT_API_KEY`, `TESTPILOT_PROVIDER`, and `TESTPILOT_TEAM_ID` directly into `Process.environment` — the subprocess never reads the file.

---

## CLI Execution

The app launches the bundled `testpilot` script via `Foundation.Process`:

```
<Bundle.main>/testpilot analyze
  --platform <ios|android>
  --app <name>
  --objective <text>
  --device <UDID>           # only when a physical device is selected
  --team-id <TEAM_ID>       # only when a physical device is selected
  --provider <provider>     # from settings or override
  --max-steps <n>
  --output <path>
  --lang <en|pt-BR>
```

Environment variables injected: `TESTPILOT_API_KEY`, `TESTPILOT_PROVIDER`, `TESTPILOT_TEAM_ID`.

stdout is read line-by-line and used to drive the status message in the running animation view.

---

## Project Structure

```
mac-app/
  TestPilot.xcodeproj
  TestPilotApp/
    App.swift                    # @main entry, window configuration
    Views/
      ContentView.swift          # NavigationSplitView root
      RunView.swift              # Run form
      RunningView.swift          # Animation + status
      SettingsView.swift         # Provider/key/team-id + raw .env editor
      HistoryView.swift          # Recent runs list
    Models/
      RunConfig.swift            # Form state (platform, device, app, objective, etc.)
      RunRecord.swift            # Single history entry
      DeviceInfo.swift           # Device model (name, UDID, type)
    Services/
      DeviceDetector.swift       # xcrun simctl + devicectl + adb queries
      AnalysisRunner.swift       # Foundation.Process launch, env injection, stdout parsing
      SettingsStore.swift        # Keychain + UserDefaults + ~/.testpilot/.env read/write
      HistoryStore.swift         # history.json persistence
    Animations/
      RobotAnimationView.swift   # SwiftUI robot + smartphone looping animation
    Resources/
      testpilot                  # Bundled bash script (copied from repo root at build time)
```

---

## Data Flow

```
User fills form
  → RunView submits RunConfig
    → DeviceDetector-resolved UDID/device name
    → AnalysisRunner builds argument list
    → AnalysisRunner reads API key from SettingsStore (Keychain)
    → Process launched with injected env vars
      → stdout lines → RunningView status label
      → on exit(0): RunRecord appended to HistoryStore → completion UI shown
      → on exit(!=0): error banner shown with last stderr line
```

---

## Out of Scope

- Android device auto-detection (Android requires ADB which may not be in PATH; the device dropdown for Android shows ADB-connected devices best-effort, with a manual fallback field)
- App Store distribution / notarization (not required for internal team use)
- Multiple simultaneous analysis runs
