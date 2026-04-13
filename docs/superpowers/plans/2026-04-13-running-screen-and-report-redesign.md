# Running Screen & Report Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the running screen with a smooth single-message fade ticker and an upgraded platform-aware animated orb, and redesign the HTML report to use a two-column layout that fully displays observation text.

**Architecture:** NeuralOrbView is rewritten first (adds `platform` parameter), then RunningView is updated to consume it and replace the current status display with a scoped fade-in/fade-out ticker. AnalysisRunner gets a `beautify(_:)` helper that strips paths and raw coordinates before messages reach the UI. HtmlReportWriter's HTML template and CSS are updated independently.

**Tech Stack:** SwiftUI Canvas API, NSRegularExpression, Kotlin string templates, HTML/CSS flexbox

---

## File Map

| File | What changes |
|---|---|
| `mac-app/TestPilotApp/Animations/NeuralOrbView.swift` | Full rewrite — 280×280, platform param, sonar pings, neural net lines, data-stream dots, web monitor |
| `mac-app/TestPilotApp/Views/RunningView.swift` | Scoped fade ticker, `NeuralOrbView(platform:)` call sites |
| `mac-app/TestPilotApp/Services/AnalysisRunner.swift` | `beautify(_:)` applied to step messages; raw lines no longer update displayed status |
| `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt` | Two-column step card layout, responsive CSS, empty-observation placeholder |

---

## Task 1: NeuralOrbView rewrite

**Files:**
- Modify: `mac-app/TestPilotApp/Animations/NeuralOrbView.swift`

**Context:** This is a full replacement of the file. The new version adds a `platform: Platform` parameter and renders a phone for `.ios`/`.android` or a browser monitor for `.web`. Frame grows from 200×200 to 280×280. Internal improvements: 8 particles with neural-network connecting lines, sonar ping rings, 4-stop liquid-metal sphere gradient, traveling data-stream dots replacing the single beam. No tests exist in this repo — verify by building in Xcode and checking the `#Preview`.

- [ ] **Step 1: Replace NeuralOrbView.swift with the new implementation**

Replace the entire file content with:

```swift
// mac-app/TestPilotApp/Animations/NeuralOrbView.swift
import SwiftUI

// MARK: - Neural Orb animation (v2)
//
// 280×280 frame. Breathing indigo→cyan sphere with 8 orbiting particles
// connected by thin neural-net lines, sonar ping rings, and a platform-aware
// device (phone for iOS/Android, monitor for web) with traveling data-stream
// dots. All motion is deterministic (sin/cos keyed on `t`).

struct NeuralOrbView: View {
    let platform: Platform

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                NeuralOrbPainter.draw(ctx: ctx, size: size, t: t, platform: platform)
            }
        }
        .frame(width: 280, height: 280)
    }
}

// MARK: - Painter

private enum NeuralOrbPainter {

    private struct Particle {
        let speed: Double; let orbitA: Double; let orbitB: Double; let phase: Double
    }

    private static let particles: [Particle] = {
        let orbitA: [Double] = [74, 70, 81, 65, 77, 68, 82, 72]
        let orbitB: [Double] = [25, 29, 21, 27, 23, 31, 22, 28]
        let speeds: [Double] = [0.70, 0.90, 0.60, 1.05, 0.80, 0.95, 0.65, 0.85]
        return (0..<8).map { i in
            Particle(speed: speeds[i], orbitA: orbitA[i], orbitB: orbitB[i],
                     phase: Double(i) * (.pi * 2 / 8))
        }
    }()

    static func draw(ctx: GraphicsContext, size: CGSize, t: Double, platform: Platform) {
        let cx       = size.width  / 2
        let cy       = size.height / 2
        let sphereCY = cy - 45
        let deviceCY = cy + 81
        let deviceH: Double = platform == .web ? 44.0 : 64.0

        drawSphere(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawSonarPing(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawParticleConnections(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawParticles(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawDataStream(ctx: ctx, cx: cx, sphereCY: sphereCY,
                       deviceCY: deviceCY, deviceH: deviceH, t: t)
        switch platform {
        case .ios, .android:
            drawPhone(ctx: ctx, cx: cx, phoneCY: deviceCY, t: t)
        case .web:
            drawMonitor(ctx: ctx, cx: cx, monitorCY: deviceCY, t: t)
        }
    }

    // MARK: Sphere

    private static func drawSphere(ctx: GraphicsContext, cx: Double, sphereCY: Double, t: Double) {
        let breathe = 1.0 + sin(t * 1.2) * 0.055
        let r = 53.0 * breathe

        // Outer halo rings
        for halo in stride(from: 3, through: 1, by: -1) {
            let hr    = r + Double(halo) * 15
            let alpha = 0.045 * Double(4 - halo)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - hr, y: sphereCY - hr,
                                      width: hr * 2, height: hr * 2)),
                with: .color(.cyan.opacity(alpha))
            )
        }

        // Core — 4 gradient layers (outer shimmer → indigo core)
        let angle = t * 0.3
        let layers: [(scale: Double, opacity: Double, hue: Double)] = [
            (1.35, 0.05, 0.75),  // purple shimmer
            (1.20, 0.08, 0.67),  // violet
            (1.05, 0.18, 0.63),  // indigo
            (1.00, 0.90, 0.63),  // indigo core
        ]
        for layer in layers {
            let lr = r * layer.scale
            let dx = cos(angle) * lr * 0.6
            let dy = sin(angle) * lr * 0.6
            let rect = CGRect(x: cx - lr, y: sphereCY - lr, width: lr * 2, height: lr * 2)
            ctx.fill(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hue: layer.hue, saturation: 0.9, brightness: 0.95).opacity(layer.opacity),
                        Color(hue: 0.54,      saturation: 1.0, brightness: 1.00).opacity(layer.opacity * 0.55),
                    ]),
                    startPoint: CGPoint(x: cx - dx, y: sphereCY - dy),
                    endPoint:   CGPoint(x: cx + dx, y: sphereCY + dy)
                )
            )
        }

        // Specular highlight
        let hr = r * 0.28
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - r * 0.38 - hr, y: sphereCY - r * 0.42 - hr,
                                  width: hr * 2, height: hr * 2)),
            with: .color(.white.opacity(0.35))
        )
    }

    // MARK: Sonar ping

    private static func drawSonarPing(ctx: GraphicsContext, cx: Double, sphereCY: Double, t: Double) {
        let pingPhase = fmod(t, 3.0) / 3.0
        let pingR     = 53.0 + pingPhase * 70
        let alpha     = (1.0 - pingPhase) * 0.30
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx - pingR, y: sphereCY - pingR,
                                  width: pingR * 2, height: pingR * 2)),
            with: .color(.cyan.opacity(alpha)),
            lineWidth: 1.0
        )
    }

    // MARK: Particle connections

    private static func drawParticleConnections(ctx: GraphicsContext,
                                                 cx: Double, sphereCY: Double, t: Double) {
        let positions: [CGPoint] = particles.map { p in
            let gt = t * p.speed + p.phase
            return CGPoint(x: cx + cos(gt) * p.orbitA,
                           y: sphereCY + sin(gt) * p.orbitB)
        }
        for i in positions.indices {
            let a = positions[i]
            let b = positions[(i + 1) % positions.count]
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            ctx.stroke(line, with: .color(.white.opacity(0.18)), lineWidth: 0.5)
        }
    }

    // MARK: Particles

    private static func drawParticles(ctx: GraphicsContext, cx: Double, sphereCY: Double, t: Double) {
        for p in particles {
            for ghost in 0...9 {
                let gt    = t * p.speed + p.phase - Double(ghost) * 0.12
                let gx    = cx       + cos(gt) * p.orbitA
                let gy    = sphereCY + sin(gt) * p.orbitB
                let alpha = (1.0 - Double(ghost) / 10.0) * 0.85
                let pr    = max(1.0, 3.5 - Double(ghost) * 0.30)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: gx - pr, y: gy - pr,
                                          width: pr * 2, height: pr * 2)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
    }

    // MARK: Data stream (3 dots traveling orb → device)

    private static func drawDataStream(ctx: GraphicsContext,
                                        cx: Double, sphereCY: Double,
                                        deviceCY: Double, deviceH: Double, t: Double) {
        let startY = sphereCY + 53.0
        let endY   = deviceCY - deviceH / 2
        for i in 0..<3 {
            let dotPhase = fmod(t * 0.8 + Double(i) * 0.33, 1.0)
            let dotY     = startY + (endY - startY) * dotPhase
            let alpha    = sin(dotPhase * .pi) * 0.7
            let r        = 2.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: dotY - r, width: r * 2, height: r * 2)),
                with: .color(.cyan.opacity(alpha))
            )
        }
    }

    // MARK: Phone (iOS / Android)

    private static func drawPhone(ctx: GraphicsContext, cx: Double, phoneCY: Double, t: Double) {
        let float     = sin(t * 0.85) * 4.0
        let phoneW    = 39.0, phoneH = 64.0
        let phoneRect = CGRect(x: cx - phoneW / 2,
                               y: phoneCY - phoneH / 2 + float,
                               width: phoneW, height: phoneH)

        for glow in [11.0, 5.5] {
            let gr = CGRect(x: phoneRect.minX - glow / 2, y: phoneRect.minY - glow / 2,
                            width: phoneRect.width + glow, height: phoneRect.height + glow)
            ctx.fill(Path(roundedRect: gr, cornerRadius: 10 + glow / 2),
                     with: .color(.cyan.opacity(0.04)))
        }

        ctx.fill(Path(roundedRect: phoneRect, cornerRadius: 8),
                 with: .color(Color(white: 0.10)))

        let pad        = 4.0
        let screenRect = CGRect(x: phoneRect.minX + pad, y: phoneRect.minY + pad,
                                width: phoneRect.width - pad * 2, height: phoneRect.height - pad * 2)
        ctx.fill(Path(roundedRect: screenRect, cornerRadius: 4),
                 with: .color(Color(hue: 0.54, saturation: 0.9, brightness: 0.12)))

        let scanPeriod   = 2.4
        let scanProgress = fmod(t, scanPeriod) / scanPeriod
        let scanY        = screenRect.minY + screenRect.height * scanProgress
        let glowH        = 14.0
        let glowTop      = max(screenRect.minY, scanY - glowH)
        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: glowTop,
                        width: screenRect.width, height: scanY - glowTop)),
            with: .linearGradient(
                Gradient(colors: [.clear, Color.mint.opacity(0.50)]),
                startPoint: CGPoint(x: screenRect.midX, y: glowTop),
                endPoint:   CGPoint(x: screenRect.midX, y: scanY)
            )
        )
        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: scanY,
                        width: screenRect.width, height: 1.5)),
            with: .color(.mint.opacity(0.95))
        )
    }

    // MARK: Monitor (Web)

    private static func drawMonitor(ctx: GraphicsContext, cx: Double, monitorCY: Double, t: Double) {
        let float   = sin(t * 0.85) * 4.0
        let monW    = 64.0, monH = 44.0
        let monRect = CGRect(x: cx - monW / 2,
                             y: monitorCY - monH / 2 + float,
                             width: monW, height: monH)

        for glow in [11.0, 5.5] {
            let gr = CGRect(x: monRect.minX - glow / 2, y: monRect.minY - glow / 2,
                            width: monRect.width + glow, height: monRect.height + glow)
            ctx.fill(Path(roundedRect: gr, cornerRadius: 7 + glow / 2),
                     with: .color(.cyan.opacity(0.04)))
        }

        ctx.fill(Path(roundedRect: monRect, cornerRadius: 5),
                 with: .color(Color(white: 0.10)))

        let pad        = 4.0
        let screenRect = CGRect(x: monRect.minX + pad, y: monRect.minY + pad,
                                width: monRect.width - pad * 2, height: monRect.height - pad * 2)
        ctx.fill(Path(roundedRect: screenRect, cornerRadius: 3),
                 with: .color(Color(hue: 0.54, saturation: 0.9, brightness: 0.12)))

        // Browser chrome bar (top 8pt of screen)
        let chromeH = 8.0
        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: screenRect.minY,
                        width: screenRect.width, height: chromeH)),
            with: .color(Color(white: 0.18))
        )

        // Three window-control dots (red / yellow / green)
        let dotColors: [Color] = [.red.opacity(0.7), .yellow.opacity(0.7), .green.opacity(0.7)]
        for i in 0..<3 {
            let dotX = screenRect.minX + 5.0 + Double(i) * 5.0
            let dotY = screenRect.minY + chromeH / 2
            let dr   = 1.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: dotX - dr, y: dotY - dr, width: dr * 2, height: dr * 2)),
                with: .color(dotColors[i])
            )
        }

        // Scan line below chrome
        let contentMinY = screenRect.minY + chromeH
        let contentH    = screenRect.height - chromeH
        let scanPeriod  = 2.4
        let scanProgress = fmod(t, scanPeriod) / scanPeriod
        let scanY       = contentMinY + contentH * scanProgress
        let glowH       = 14.0
        let glowTop     = max(contentMinY, scanY - glowH)
        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: glowTop,
                        width: screenRect.width, height: scanY - glowTop)),
            with: .linearGradient(
                Gradient(colors: [.clear, Color.mint.opacity(0.50)]),
                startPoint: CGPoint(x: screenRect.midX, y: glowTop),
                endPoint:   CGPoint(x: screenRect.midX, y: scanY)
            )
        )
        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: scanY,
                        width: screenRect.width, height: 1.5)),
            with: .color(.mint.opacity(0.95))
        )

        // Stand
        let standW = 8.0, standH = 8.0
        ctx.fill(
            Path(roundedRect: CGRect(x: cx - standW / 2, y: monRect.maxY + float,
                                     width: standW, height: standH), cornerRadius: 1),
            with: .color(Color(white: 0.15))
        )
    }
}

#Preview {
    HStack(spacing: 20) {
        NeuralOrbView(platform: .ios)
        NeuralOrbView(platform: .web)
    }
    .frame(width: 640, height: 320)
    .background(Color(hue: 0.63, saturation: 0.25, brightness: 0.12))
}
```

- [ ] **Step 2: Build in Xcode**

Open `mac-app/TestPilot.xcodeproj` and press ⌘B.

Expected: build succeeds with no errors. If you get "cannot find type 'Platform' in scope", ensure `Platform` is defined in `RunConfig.swift` or a file in the same target — it should already be there.

- [ ] **Step 3: Check #Preview**

In Xcode, open `NeuralOrbView.swift` and click the Preview canvas (⌥⌘P). You should see two orbs side by side — the left one with a floating phone, the right with a floating monitor showing 3 colored window dots.

- [ ] **Step 4: Commit**

```bash
git add mac-app/TestPilotApp/Animations/NeuralOrbView.swift
git commit -m "feat(mac): redesign NeuralOrbView — 280×280, platform-aware device, sonar pings, neural net particles"
```

---

## Task 2: RunningView — scoped fade ticker

**Files:**
- Modify: `mac-app/TestPilotApp/Views/RunningView.swift`

**Context:** Two changes: (1) update both `NeuralOrbView()` call sites to `NeuralOrbView(platform: config.platform)`, (2) wrap the status/step text in a `ZStack` with a scoped `.animation` so only the message fades, not the whole layout. Font upgrades from `.footnote` to `.callout` for better readability.

The current file is at `mac-app/TestPilotApp/Views/RunningView.swift`. Read it before editing.

- [ ] **Step 1: Update `.running` case**

Replace:

```swift
            case .running(let statusLine):
                NeuralOrbView()
                Text(statusLine)
                    .id(statusLine)
                    .transition(.opacity)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)
```

With:

```swift
            case .running(let statusLine):
                NeuralOrbView(platform: config.platform)
                ZStack {
                    Text(statusLine)
                        .id(statusLine)
                        .transition(.opacity)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .animation(.easeInOut(duration: 0.4), value: statusLine)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)
```

- [ ] **Step 2: Update `.testRunning` case**

Replace:

```swift
            case .testRunning(let steps):
                NeuralOrbView()
                if let current = steps.last {
                    Text(current.message)
                        .id(steps.count)
                        .transition(.opacity)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)
```

With:

```swift
            case .testRunning(let steps):
                NeuralOrbView(platform: config.platform)
                ZStack {
                    if let current = steps.last {
                        Text(current.message)
                            .id(steps.count)
                            .transition(.opacity)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: steps.count)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)
```

- [ ] **Step 3: Build in Xcode**

Press ⌘B. Expected: no errors. If you get "extra argument 'platform' in call", Task 1 wasn't completed — go back and finish it.

- [ ] **Step 4: Run the app and trigger an analysis**

Press ⌘R. Start an analysis or test run. Verify:
- Orb is larger (280×280)
- Each step message fades in smoothly below the orb
- Previous message fades out as new one fades in
- For web platform: orb shows monitor instead of phone

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Views/RunningView.swift
git commit -m "feat(mac): scoped fade ticker for step messages, larger orb"
```

---

## Task 3: AnalysisRunner — message beautify

**Files:**
- Modify: `mac-app/TestPilotApp/Services/AnalysisRunner.swift`

**Context:** Add a private `beautify(_:)` method that strips raw paths and coordinate patterns. Apply it when extracting the step message from `TESTPILOT_STEP:` output. Also stop updating the displayed status from raw (non-marker) stdout lines — those are noisy xcodebuild output that shouldn't appear in the ticker.

- [ ] **Step 1: Add `beautify(_:)` method**

At the bottom of `AnalysisRunner`, before the closing `}`, add:

```swift
    // MARK: - Message cleanup

    private func beautify(_ message: String) -> String {
        var s = message

        func replace(_ pattern: String, with replacement: String) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        }

        replace(#"(?i)\btouch\s*\([^)]*\)"#,              with: "Tap")   // touch(...) → Tap
        replace(#"\(\s*\d+\.?\d*\s*,\s*\d+\.?\d*\s*\)"#, with: "")      // (x, y) coordinates
        replace(#"~?/[\w\-._/]+"#,                         with: "")      // file paths

        s = s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return s.isEmpty ? message : s
    }
```

- [ ] **Step 2: Apply `beautify` to step messages**

Find this block in `startProcess(_:outputPath:)`:

```swift
                    if let r = line.range(of: "TESTPILOT_STEP: ") {
                        let msg = String(line[r.upperBound...])
                        let cached = msg.hasPrefix("(cached)")
                        let clean = cached ? String(msg.dropFirst("(cached) ".count)) : msg
                        let step = TestStep(message: clean, cached: cached)
```

Replace with:

```swift
                    if let r = line.range(of: "TESTPILOT_STEP: ") {
                        let msg = String(line[r.upperBound...])
                        let cached = msg.hasPrefix("(cached)")
                        let raw   = cached ? String(msg.dropFirst("(cached) ".count)) : msg
                        let clean = self.beautify(raw)
                        let step = TestStep(message: clean, cached: cached)
```

- [ ] **Step 3: Suppress raw-line status updates**

Find the `else` block that updates the status from raw lines:

```swift
                    } else {
                        if case .running = self.state {
                            self.state = .running(statusLine: line)
                        }
                    }
```

Replace with (raw lines no longer pollute the ticker):

```swift
                    } else {
                        // Raw xcodebuild output — do not update the displayed message
                        break
                    }
```

- [ ] **Step 4: Build in Xcode**

Press ⌘B. Expected: no errors.

- [ ] **Step 5: Run and verify messages are clean**

Press ⌘R. Start an iOS analysis. Step messages in the ticker should show readable text like "Tap", "Scroll down", "Typing credentials" — no raw coordinates or file paths.

- [ ] **Step 6: Commit**

```bash
git add mac-app/TestPilotApp/Services/AnalysisRunner.swift
git commit -m "feat(mac): beautify step messages — strip paths and raw coordinates"
```

---

## Task 4: HtmlReportWriter — two-column layout

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt`

**Context:** Each step card currently stacks screenshot above observation text. Replace with a flexbox two-column layout: screenshot on the left (40%), observation text on the right (60%). This fixes the clipping issue and uses desktop screen real estate. The change is CSS + HTML template only — no Kotlin logic changes.

- [ ] **Step 1: Replace the CSS block inside `generate()`**

Find the `<style>` block in the `return """..."""` string (lines 69–108 approx). Replace the existing `.step img` and `.obs` rules, and add the new two-column rules.

The full new `<style>` block to use (replace from `<style>` to `</style>` inclusive):

```css
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                 background: #f5f5f7; color: #1d1d1f; line-height: 1.5; }
          .header { background: #fff; padding: 32px 40px; border-bottom: 1px solid #e5e5ea; }
          .header h1 { font-size: 22px; font-weight: 600; margin-bottom: 8px; }
          .header .objective { color: #6e6e73; font-size: 15px; }
          .meta { margin-top: 12px; font-size: 13px; color: #8e8e93; }
          .summary-box { margin: 24px 40px; background: #fff; border-radius: 12px;
                         padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
          .summary-box p { font-size: 14px; color: #3a3a3c; }
          .steps { padding: 0 40px 40px; }
          .steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
          .step { background: #fff; border-radius: 12px; margin-bottom: 16px;
                  box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .step-header { display: flex; align-items: center; gap: 10px;
                         padding: 12px 16px; background: #f2f2f7;
                         border-radius: 12px 12px 0 0; }
          .step-num { font-size: 12px; color: #8e8e93; }
          .action { font-size: 13px; font-weight: 600; background: #007aff;
                    color: #fff; padding: 2px 8px; border-radius: 4px; }
          .coord { font-size: 12px; color: #8e8e93; font-family: monospace; }
          .step-body { display: flex; flex-direction: row; align-items: flex-start; }
          .step-img-col { flex: 0 0 40%; padding: 12px; }
          .step-img-col img { display: block; width: 100%; height: auto; border-radius: 8px; }
          .step-obs-col { flex: 1; padding: 16px 16px 16px 8px;
                          font-size: 14px; line-height: 1.6; color: #3a3a3c; }
          .step-obs-empty { color: #aeaeb2; font-style: italic; }
          @media (max-width: 600px) {
            .step-body { flex-direction: column; }
            .step-img-col { flex: none; width: 100%; }
          }
          @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
            .header { background: #2c2c2e; border-bottom-color: #3a3a3c; }
            .header .objective { color: #aeaeb2; }
            .meta { color: #636366; }
            .summary-box { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
            .summary-box p { color: #ebebf0; }
            .step { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
            .step-header { background: #3a3a3c; }
            .step-num { color: #636366; }
            .coord { color: #636366; }
            .step-obs-col { color: #ebebf0; }
          }
        </style>
```

- [ ] **Step 2: Replace the step HTML template inside `stepsHtml`**

Find the existing `val obsHtml = ...` and the `"""..."""` step template block. Replace both with:

```kotlin
            val obsContent = step.observation
                ?.takeIf { it.isNotBlank() }
                ?.let { "<p>${it.htmlEscape()}</p>" }
                ?: "<p class=\"step-obs-empty\">—</p>"
            val coordHtml = step.coordinates
                ?.let { (x, y) -> "<span class=\"coord\">(${fmtCoord(x)}, ${fmtCoord(y)})</span>" }
                ?: ""
            """
            <div class="step">
              <div class="step-header">
                <span class="step-num">${lbl.step} ${index + 1}</span>
                <span class="action">${step.action.htmlEscape()}</span>
                $coordHtml
              </div>
              <div class="step-body">
                <div class="step-img-col">
                  <img src="data:${step.screenshotData.imageMimeType()};base64,$base64" alt="${lbl.step} ${index + 1}" loading="lazy" />
                </div>
                <div class="step-obs-col">
                  $obsContent
                </div>
              </div>
            </div>
            """.trimIndent()
```

- [ ] **Step 3: Build the SDK**

```bash
cd sdk && ./gradlew testpilot:compileKotlinJvm
```

Expected output ends with `BUILD SUCCESSFUL`.

- [ ] **Step 4: Generate a test report and verify in browser**

Run a short analysis (2–3 steps) using the CLI or the Mac app. Open the resulting `.html` file in Safari or Chrome.

Verify:
- Each step card shows screenshot on the left (~40%) and observation text on the right (~60%)
- Observation text is fully visible, not clipped
- Steps with no observation show `—` in muted italic
- Resize the window below 600px wide — columns should stack vertically

- [ ] **Step 5: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt
git commit -m "feat(report): two-column step layout — screenshot left, full observation text right"
```
