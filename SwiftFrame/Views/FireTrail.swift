import SwiftUI

/// Fire streaks off the back of the playhead while it plays forward: sparks
/// shed at the line drift back and up, stretching into streaks and cooling
/// from white-hot yellow through orange to red before they fade, over a short
/// glow trailing the line.
///
/// Draw it inside a `TimelineView(.animation)`, passing that frame's date and
/// the playhead's place; it keeps its sparks in `FireTrail.Sparks`.
/// `FireTrail.reach` points behind the playhead are drawn.
struct FireTrail: View {
    /// How far behind the playhead (and ahead of it) the fire is drawn.
    static let reach: CGFloat = 380
    static let lead: CGFloat = 30

    let sparks: Sparks
    let date: Date
    /// The playhead's place along the strip.
    let x: CGFloat
    /// Where along the strip this view's left edge is. The view covers just
    /// the stretch behind the playhead; sparks keep strip positions, so they
    /// stay where they were shed as the playhead moves on.
    let origin: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            sparks.update(date: date, x: x, height: size.height)
            let additive = colorScheme == .dark
            context.translateBy(x: -origin, y: 0)
            draw(in: &context, size: size, additive: additive)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, additive: Bool) {
        // The heat glow just behind the line, as long as it's moving.
        let glowLength = min(140, 24 + sparks.speed * 0.08)
        if sparks.speed > 1 {
            let glow = CGRect(x: x - glowLength, y: 3, width: glowLength, height: size.height - 6)
            var layer = context
            layer.addFilter(.blur(radius: 4))
            if additive { layer.blendMode = .plusLighter }
            layer.fill(
                Path(roundedRect: glow, cornerRadius: 4),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.6, green: 0, blue: 0).opacity(0), location: 0),
                        .init(color: Color(red: 0.9, green: 0.1, blue: 0).opacity(additive ? 0.35 : 0.3), location: 0.45),
                        .init(color: Color(red: 1, green: 0.45, blue: 0).opacity(additive ? 0.6 : 0.55), location: 0.8),
                        .init(color: Color(red: 1, green: 0.85, blue: 0.3).opacity(additive ? 0.85 : 0.8), location: 1),
                    ]),
                    startPoint: CGPoint(x: glow.minX, y: 0), endPoint: CGPoint(x: glow.maxX, y: 0)))
        }

        // Sparks: a soft blurred layer for the glow, then sharp cores.
        context.drawLayer { layer in
            if additive { layer.blendMode = .plusLighter }
            layer.addFilter(.blur(radius: 4))
            for spark in sparks.all {
                layer.fill(spark.path(stretch: 1.8), with: .color(spark.color(dark: additive).opacity(spark.alpha * 0.9)))
            }
        }
        context.drawLayer { layer in
            if additive { layer.blendMode = .plusLighter }
            for spark in sparks.all {
                layer.fill(spark.path(stretch: 1), with: .color(spark.core(dark: additive).opacity(spark.alpha)))
            }
        }
    }

    /// The live sparks, kept between frames.
    final class Sparks {
        struct Spark {
            var x: CGFloat
            var y: CGFloat
            var vx: CGFloat
            var vy: CGFloat
            var age: Double = 0
            var life: Double
            var size: CGFloat

            /// 0 when shed, 1 when it dies.
            var progress: Double { min(1, age / life) }
            var alpha: Double { (1 - progress) * (1 - progress) }

            /// Yellow, cooling quickly through orange to deep red. On a light
            /// background it's darker, so the embers still show.
            func color(dark: Bool) -> Color {
                let p = pow(progress, 0.6)
                return Color(hue: 0.12 * (1 - p), saturation: 0.85 + 0.15 * p,
                             brightness: dark ? 1 - 0.25 * p : 0.95 - 0.35 * p)
            }

            /// The streak's hotter middle: near white when shed.
            func core(dark: Bool) -> Color {
                let p = pow(progress, 0.7)
                return Color(hue: 0.14 * (1 - p), saturation: (dark ? 0.2 : 0.55) + 0.8 * p,
                             brightness: dark ? 1 : 1 - 0.3 * p)
            }

            /// A streak stretched along the way it's moving.
            func path(stretch: CGFloat) -> Path {
                let speed = max(1, (vx * vx + vy * vy).squareRoot())
                let length = (size * 2.5 + speed * 0.06) * stretch * (1 - 0.5 * progress)
                let thickness = size * stretch * (1 - 0.4 * progress)
                let angle = atan2(vy, vx)
                let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
                return Path(roundedRect: rect, cornerRadius: thickness / 2)
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: x, y: y))
            }
        }

        private(set) var all: [Spark] = []
        /// How fast the playhead is moving, in points per second.
        private(set) var speed: CGFloat = 0
        private var lastDate: Date?
        private var lastX: CGFloat?
        private var debt: Double = 0

        func update(date: Date, x: CGFloat, height: CGFloat) {
            let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 1.0 / 20) } ?? 0
            // Starting again, or jumping back (a loop): start a fresh fire.
            if let lastDate, date.timeIntervalSince(lastDate) > 0.5 { reset() }
            if let lastX, x < lastX - 2 { reset() }
            defer {
                lastDate = date
                lastX = x
            }
            guard let lastX, dt > 0 else { return }

            let moved = max(0, x - lastX)
            speed = speed * 0.8 + (moved / CGFloat(dt)) * 0.2

            // Age and move the sparks: they slow down and rise as they cool.
            for i in all.indices {
                all[i].age += dt
                all[i].x += all[i].vx * CGFloat(dt)
                all[i].y += all[i].vy * CGFloat(dt)
                all[i].vx *= CGFloat(pow(0.12, dt))
                all[i].vy -= 40 * CGFloat(dt)
            }
            all.removeAll { $0.age >= $0.life || $0.y < -10 }

            // Shed more sparks the faster it goes, along the line's height.
            guard moved > 0 else { return }
            debt += dt * Double(min(520, 120 + speed * 0.4))
            while debt >= 1, all.count < 400 {
                debt -= 1
                let along = CGFloat.random(in: 0...1)
                all.append(Spark(
                    x: x - CGFloat.random(in: 0...moved + 2),
                    y: 6 + along * max(1, height - 12),
                    vx: -CGFloat.random(in: 40...140) - speed * 0.15,
                    vy: CGFloat.random(in: -45...15),
                    life: .random(in: 0.18...0.42),
                    size: .random(in: 1.3...3)))
            }
            if all.count >= 400 { debt = 0 }
        }

        func reset() {
            all.removeAll()
            speed = 0
            debt = 0
            lastX = nil
        }
    }
}
