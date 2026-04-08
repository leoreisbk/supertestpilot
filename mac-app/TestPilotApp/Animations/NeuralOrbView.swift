import SwiftUI

// MARK: - Neural Orb animation
//
// A breathing indigo→cyan sphere with orbiting particle trails, an energy beam
// connecting to a floating phone, and a mint scan line scrolling across the screen.
// All motion is deterministic (sin/cos keyed on `t`) — no random() calls inside
// Canvas, which would cause re-render thrash.

struct NeuralOrbView: View {

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                NeuralOrbPainter.draw(ctx: ctx, size: size, t: t)
            }
        }
        .frame(width: 200, height: 200)
    }
}

// MARK: - Painter (extracted to keep Canvas closure inference happy)

private enum NeuralOrbPainter {

    private struct Particle {
        let speed: Double; let orbitA: Double; let orbitB: Double; let phase: Double
    }

    private static let particles: [Particle] = [
        Particle(speed: 0.70, orbitA: 54, orbitB: 18, phase: 0.00),
        Particle(speed: 0.90, orbitA: 50, orbitB: 22, phase: 1.26),
        Particle(speed: 0.60, orbitA: 58, orbitB: 15, phase: 2.51),
        Particle(speed: 1.05, orbitA: 46, orbitB: 20, phase: 3.77),
        Particle(speed: 0.80, orbitA: 52, orbitB: 17, phase: 5.03),
    ]

    static func draw(ctx: GraphicsContext, size: CGSize, t: Double) {
        let cx       = size.width  / 2
        let cy       = size.height / 2
        let sphereCY = cy - 32          // sphere vertical centre
        let phoneCY  = cy + 58          // phone vertical centre

        drawSphere(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawParticles(ctx: ctx, cx: cx, sphereCY: sphereCY, t: t)
        drawBeam(ctx: ctx, cx: cx, sphereCY: sphereCY, phoneCY: phoneCY, t: t)
        drawPhone(ctx: ctx, cx: cx, phoneCY: phoneCY, t: t)
    }

    // MARK: Sphere

    private static func drawSphere(ctx: GraphicsContext, cx: Double, sphereCY: Double, t: Double) {
        let breathe = 1.0 + sin(t * 1.2) * 0.055
        let r       = 38.0 * breathe

        // Outer halo rings
        for halo in stride(from: 3, through: 1, by: -1) {
            let hr    = r + Double(halo) * 11
            let alpha = 0.045 * Double(4 - halo)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - hr, y: sphereCY - hr,
                                      width: hr * 2, height: hr * 2)),
                with: .color(.cyan.opacity(alpha))
            )
        }

        // Core sphere — three radial gradient layers (outer glow → core)
        let layers: [(scale: Double, opacity: Double)] = [
            (1.20, 0.08), (1.05, 0.18), (1.00, 0.90)
        ]
        let angle = t * 0.4
        for layer in layers {
            let lr   = r * layer.scale
            let dx   = cos(angle) * lr * 0.6
            let dy   = sin(angle) * lr * 0.6
            let rect = CGRect(x: cx - lr, y: sphereCY - lr, width: lr * 2, height: lr * 2)
            ctx.fill(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hue: 0.63, saturation: 0.9,  brightness: 0.95).opacity(layer.opacity),
                        Color(hue: 0.54, saturation: 1.0,  brightness: 1.00).opacity(layer.opacity * 0.55),
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

    // MARK: Particles

    private static func drawParticles(ctx: GraphicsContext, cx: Double, sphereCY: Double, t: Double) {
        for p in particles {
            for ghost in 0...7 {
                let gt    = t * p.speed + p.phase - Double(ghost) * 0.14
                let gx    = cx       + cos(gt) * p.orbitA
                let gy    = sphereCY + sin(gt) * p.orbitB
                let alpha = (1.0 - Double(ghost) / 8.0) * 0.85
                let pr    = max(1.0, 3.0 - Double(ghost) * 0.32)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: gx - pr, y: gy - pr,
                                          width: pr * 2, height: pr * 2)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
    }

    // MARK: Energy beam

    private static func drawBeam(ctx: GraphicsContext,
                                  cx: Double, sphereCY: Double, phoneCY: Double, t: Double) {
        let pulse = (sin(t * 3.4) + 1) / 2
        let breathe = 1.0 + sin(t * 1.2) * 0.055
        let sphereR = 38.0 * breathe
        var beam = Path()
        beam.move(to:    CGPoint(x: cx, y: sphereCY + sphereR))
        beam.addLine(to: CGPoint(x: cx, y: phoneCY - 25))
        ctx.stroke(beam,
                   with: .color(.cyan.opacity(0.12 + pulse * 0.18)),
                   lineWidth: 1.5)
    }

    // MARK: Phone

    private static func drawPhone(ctx: GraphicsContext, cx: Double, phoneCY: Double, t: Double) {
        let float    = sin(t * 0.85) * 3.5
        let phoneW   = 28.0, phoneH = 46.0
        let phoneRect = CGRect(x: cx - phoneW / 2,
                               y: phoneCY - phoneH / 2 + float,
                               width: phoneW, height: phoneH)

        // Body glow halos
        for glow in [8.0, 4.0] {
            let gr = CGRect(x: phoneRect.minX - glow / 2,
                            y: phoneRect.minY - glow / 2,
                            width: phoneRect.width  + glow,
                            height: phoneRect.height + glow)
            ctx.fill(Path(roundedRect: gr, cornerRadius: 7 + glow / 2),
                     with: .color(.cyan.opacity(0.04)))
        }

        // Phone body
        ctx.fill(Path(roundedRect: phoneRect, cornerRadius: 6),
                 with: .color(Color(white: 0.10)))

        // Screen
        let pad        = 3.0
        let screenRect = CGRect(x: phoneRect.minX + pad,
                                y: phoneRect.minY + pad,
                                width:  phoneRect.width  - pad * 2,
                                height: phoneRect.height - pad * 2)
        ctx.fill(Path(roundedRect: screenRect, cornerRadius: 3),
                 with: .color(Color(hue: 0.54, saturation: 0.9, brightness: 0.12)))

        // Scan line with leading glow (all rects stay within screenRect, no clip needed)
        let scanPeriod   = 2.4
        let scanProgress = fmod(t, scanPeriod) / scanPeriod
        let scanY        = screenRect.minY + screenRect.height * scanProgress

        let glowH = 10.0
        let glowTop = max(screenRect.minY, scanY - glowH)
        let glowRect = CGRect(x: screenRect.minX, y: glowTop,
                              width: screenRect.width, height: scanY - glowTop)
        ctx.fill(Path(glowRect),
                 with: .linearGradient(
                    Gradient(colors: [.clear, Color.mint.opacity(0.50)]),
                    startPoint: CGPoint(x: screenRect.midX, y: glowTop),
                    endPoint:   CGPoint(x: screenRect.midX, y: scanY)
                 ))

        ctx.fill(
            Path(CGRect(x: screenRect.minX, y: scanY,
                        width: screenRect.width, height: 1.5)),
            with: .color(.mint.opacity(0.95))
        )
    }
}

#Preview {
    NeuralOrbView()
        .frame(width: 300, height: 300)
        .background(Color(hue: 0.63, saturation: 0.25, brightness: 0.12))
}
