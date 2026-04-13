# Running Screen & Report Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the running screen for a smoother, more user-friendly experience with a polished animated orb, and improve the HTML report layout to use desktop screen real estate.

**Architecture:** Three areas of change — `NeuralOrbView.swift` (visual upgrade + platform-awareness), `RunningView.swift` (live step ticker + layout), `AnalysisRunner.swift` (message cleanup), and `HtmlReportWriter.kt` (two-column report layout).

**Tech Stack:** SwiftUI Canvas API (orb), SwiftUI animation system (transitions), Kotlin/HTML+CSS (report)

---

## 1. Running Screen Layout

### 1.1 Step ticker (during run)

While the analysis or test is running, a single step message is shown **below the orb**, one at a time. Each new step replaces the previous with a smooth fade-in/fade-out transition:

- Transition: `.opacity` combined with `.easeInOut(duration: 0.4)`
- Driven by `.id(steps.count)` so SwiftUI treats each new message as a new view identity, triggering the transition automatically
- Message is displayed in `.body` weight, `.primary` color, centered, `maxWidth: 400`
- No history visible during the run — just the current step

Layout (top to bottom):
```
NeuralOrbView(platform: config.platform)   // 280×280
[current step message — fades in/out]
[Cancel button]
```

### 1.2 Completion state

When the run finishes:
- Orb + message fade out (`withAnimation(.easeInOut(duration: 0.4))`)
- Checkmark icon + "Analysis complete" / verdict banner fades in
- Full step list fades in below, expanding to fill available space with `.layoutPriority(1)`
- "Open Report" / "Run Again" buttons appear at the bottom

### 1.3 Message cleanup

In `AnalysisRunner.swift`, before storing a step message, apply a `beautify(_:)` helper that transforms raw SDK output into readable text:

| Raw message pattern | Cleaned output |
|---|---|
| `touch(0.45, 0.72)` | `Tap` |
| `Tap at (0.45, 0.72)` | `Tap` |
| `scroll(direction: down)` | `Scroll down` |
| `type("hello@example.com")` | `Type "hello@example.com"` |
| Any substring matching `/[A-Za-z0-9/_\-.]+\.[a-z]{2,5}(\/[^\s]*)?/` (file path) | stripped |
| Leading/trailing whitespace | trimmed |

The `beautify(_:)` function uses `NSRegularExpression` and is a private method on `AnalysisRunner`. It is applied to the `clean` variable before constructing `TestStep`.

---

## 2. NeuralOrbView

### 2.1 Component size

`NeuralOrbView` frame increases from `200×200` to `280×280`. All internal coordinates scale proportionally (multiply existing constants by `1.4`).

### 2.2 Platform parameter

```swift
struct NeuralOrbView: View {
    let platform: Platform  // .ios, .android, .web
    ...
}
```

All call sites pass `config.platform`. The `drawDevice` method branches on `platform`.

### 2.3 Sphere improvements

- **Base radius:** 53px (up from 38px × 1.4)
- **Gradient:** 4-stop rotation: indigo → blue → cyan → purple, with the gradient angle driven by `t * 0.3` for slow liquid-metal shimmer
- **Layers:** 3 gradient layers as before, plus a 4th thin outer shimmer layer at `scale: 1.35, opacity: 0.05`
- **Specular:** keep existing highlight, scale proportionally

### 2.4 Particles

- **Count:** 8 (up from 5), evenly phased at `2π/8` apart
- **Connecting lines:** after drawing all particle heads, draw thin lines (`lineWidth: 0.5, opacity: 0.2`) between each adjacent particle head (i → i+1, wrapping), creating a neural-network polygon
- **Trail length:** 10 ghost steps (up from 8)

### 2.5 Sonar pings

A periodic outward ring emits from the sphere center every ~3 seconds:

- `pingPhase = fmod(t, 3.0) / 3.0` → 0…1
- Ring radius: `sphereR + pingPhase * 60`
- Opacity: `(1 - pingPhase) * 0.3`
- Stroke lineWidth: `1.0`
- Color: `.cyan`

### 2.6 Device (platform-aware)

**iOS / Android — phone** (current design, scaled up ×1.4):
- Size: `39×64` (up from `28×46`)
- Floating bob: `sin(t * 0.85) * 4`
- Scan line: unchanged behavior, scaled

**Web — monitor:**
- Size: `64×44` (landscape rectangle)
- Corner radius: `5`
- Screen inset: `4px` all sides
- Top bar: `8px` tall solid strip inside screen (browser chrome), with 3 small circles (●●●) at `y + 4, x + 8/12/16`
- Scan line: same horizontal sweep across screen area below the top bar
- Body color: `Color(white: 0.10)`
- Screen color: `Color(hue: 0.54, saturation: 0.9, brightness: 0.12)`
- Stand: thin rectangle `4×8` below body, centered

### 2.7 Data stream (orb → device)

Replace the single beam line with 3 traveling dots:

- 3 dots, each offset by `1/3` of the cycle: `dotPhase = fmod(t * 0.8 + i * 0.33, 1.0)`
- Position: lerp from `(cx, sphereCY + sphereR)` to `(cx, deviceCY - deviceH/2)` using `dotPhase`
- Dot radius: `2.5`
- Opacity: `sin(dotPhase * π) * 0.7` (fades in, travels, fades out)
- Color: `.cyan`

---

## 3. HTML Report Layout

### 3.1 Two-column step card

Each `.step` card changes from a stacked (image above, text below) layout to a side-by-side layout:

```
┌────────────────────────────────────────────────────┐
│ Step N   [Action badge]   (x, y)                   │
├──────────────────┬─────────────────────────────────┤
│                  │                                  │
│   screenshot     │   observation text               │
│   (40% width)    │   (60% width, full sentences)   │
│                  │                                  │
└──────────────────┴─────────────────────────────────┘
```

CSS changes:
- `.step-body` wrapper: `display: flex; flex-direction: row; align-items: flex-start;`
- `.step-img-col`: `flex: 0 0 40%; padding: 12px;`
- `.step-img-col img`: `width: 100%; height: auto; border-radius: 8px;`
- `.step-obs-col`: `flex: 1; padding: 16px 16px 16px 8px; font-size: 14px; line-height: 1.6; color: #3a3a3c;`
- Remove `max-width: 390px` from image — let the column constrain it
- Remove any `overflow: hidden` on `.step`

### 3.2 Responsive fallback

```css
@media (max-width: 600px) {
  .step-body { flex-direction: column; }
  .step-img-col { flex: none; width: 100%; }
}
```

### 3.3 Empty observation

If `step.observation` is null/empty, the right column shows a placeholder in muted color:
```html
<div class="step-obs-col step-obs-empty">—</div>
```
```css
.step-obs-empty { color: #aeaeb2; font-style: italic; }
```

---

## 4. Files Changed

| File | Change |
|---|---|
| `mac-app/TestPilotApp/Animations/NeuralOrbView.swift` | Full rewrite: larger, platform-aware, sonar pings, neural connections, data stream dots |
| `mac-app/TestPilotApp/Views/RunningView.swift` | Step ticker (single message fade), layout adjustments |
| `mac-app/TestPilotApp/Services/AnalysisRunner.swift` | `beautify(_:)` message cleanup applied before `TestStep` construction |
| `sdk/testpilot/src/commonMain/…/analyst/HtmlReportWriter.kt` | Two-column step layout, responsive CSS, empty observation handling |

---

## 5. Out of Scope

- Android support (already noted as "coming soon" in the app)
- Localization of beautified message strings (English only for now)
- Report navigation / table of contents
- Per-step timing data
