import SwiftUI

struct RobotAnimationView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2

                // Body
                let body = CGRect(x: cx - 35, y: cy - 20, width: 70, height: 55)
                context.fill(Path(roundedRect: body, cornerRadius: 10),
                             with: .color(.blue.opacity(0.85)))

                // Head
                let head = CGRect(x: cx - 25, y: cy - 68, width: 50, height: 48)
                context.fill(Path(roundedRect: head, cornerRadius: 8),
                             with: .color(.blue.opacity(0.9)))

                // Eyes (blink)
                let blink = sin(t * 1.8) > 0.93 ? 2.0 : 9.0
                context.fill(Path(ellipseIn: CGRect(x: cx - 17, y: cy - 58, width: 11, height: blink)),
                             with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: cx + 6,  y: cy - 58, width: 11, height: blink)),
                             with: .color(.white))

                // Antenna
                var antenna = Path()
                antenna.move(to: CGPoint(x: cx, y: cy - 68))
                antenna.addLine(to: CGPoint(x: cx, y: cy - 84))
                context.stroke(antenna, with: .color(.blue.opacity(0.9)), lineWidth: 3)
                let glow = (sin(t * 3.2) + 1) / 2
                context.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 91, width: 10, height: 10)),
                             with: .color(.cyan.opacity(0.5 + glow * 0.5)))

                // Left arm (holding phone) — slight swing
                let swing = sin(t * 1.4) * 4
                var leftArm = Path()
                leftArm.move(to: CGPoint(x: cx - 35, y: cy - 8))
                leftArm.addLine(to: CGPoint(x: cx - 62, y: cy + 14 + swing))
                context.stroke(leftArm, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Phone in left hand
                let phone = CGRect(x: cx - 82, y: cy + 9 + swing, width: 24, height: 38)
                context.fill(Path(roundedRect: phone, cornerRadius: 4),
                             with: .color(Color(white: 0.25)))
                let screenGlow = (sin(t * 4.5) + 1) / 2
                let screen = CGRect(x: cx - 80, y: cy + 13 + swing, width: 20, height: 26)
                context.fill(Path(roundedRect: screen, cornerRadius: 2),
                             with: .color(.cyan.opacity(0.25 + screenGlow * 0.75)))

                // Right arm
                var rightArm = Path()
                rightArm.move(to: CGPoint(x: cx + 35, y: cy - 8))
                rightArm.addLine(to: CGPoint(x: cx + 55, y: cy + 5 - swing))
                context.stroke(rightArm, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Legs
                var leftLeg = Path()
                leftLeg.move(to: CGPoint(x: cx - 14, y: cy + 35))
                leftLeg.addLine(to: CGPoint(x: cx - 17, y: cy + 62))
                context.stroke(leftLeg, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                var rightLeg = Path()
                rightLeg.move(to: CGPoint(x: cx + 14, y: cy + 35))
                rightLeg.addLine(to: CGPoint(x: cx + 17, y: cy + 62))
                context.stroke(rightLeg, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Thinking dots above head
                for i in 0..<3 {
                    let phase = sin(t * 2.8 + Double(i) * 0.9)
                    let alpha = (phase + 1) / 2
                    let dotY = cy - 104 - phase * 4
                    let dot = CGRect(x: cx - 9 + Double(i) * 9, y: dotY, width: 7, height: 7)
                    context.fill(Path(ellipseIn: dot), with: .color(.cyan.opacity(alpha)))
                }
            }
        }
        .frame(width: 200, height: 200)
    }
}

#Preview {
    RobotAnimationView()
        .frame(width: 300, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
