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
        let contentMinY  = screenRect.minY + chromeH
        let contentH     = screenRect.height - chromeH
        let scanPeriod   = 2.4
        let scanProgress = fmod(t, scanPeriod) / scanPeriod
        let scanY        = contentMinY + contentH * scanProgress
        let glowH        = 14.0
        let glowTop      = max(contentMinY, scanY - glowH)
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
