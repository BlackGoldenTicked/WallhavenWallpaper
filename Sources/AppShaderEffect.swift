import SwiftUI

struct AppShaderEffectModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                AppShaderBackdrop(reduceMotion: reduceMotion)
                    .ignoresSafeArea()
            }
            .overlay {
                AppShaderVeil(reduceMotion: reduceMotion)
                    .blendMode(colorScheme == .dark ? .screen : .softLight)
                    .opacity(colorScheme == .dark ? 0.22 : 0.14)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func appShaderEffect() -> some View {
        modifier(AppShaderEffectModifier())
    }
}

private struct AppShaderBackdrop: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(reduceMotion ? .periodic(from: .now, by: 60) : .periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color.accentColor.opacity(0.10),
                            Color(nsColor: .controlBackgroundColor)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                context.addFilter(.blur(radius: 42))
                drawOrb(
                    in: &context,
                    size: size,
                    center: CGPoint(
                        x: size.width * (0.18 + 0.05 * sin(t * 0.22)),
                        y: size.height * (0.18 + 0.04 * cos(t * 0.18))
                    ),
                    radius: max(size.width, size.height) * 0.42,
                    color: .blue
                )
                drawOrb(
                    in: &context,
                    size: size,
                    center: CGPoint(
                        x: size.width * (0.82 + 0.04 * cos(t * 0.16)),
                        y: size.height * (0.68 + 0.05 * sin(t * 0.20))
                    ),
                    radius: max(size.width, size.height) * 0.46,
                    color: .purple
                )
                drawOrb(
                    in: &context,
                    size: size,
                    center: CGPoint(
                        x: size.width * (0.50 + 0.03 * sin(t * 0.14)),
                        y: size.height * (0.94 + 0.04 * cos(t * 0.19))
                    ),
                    radius: max(size.width, size.height) * 0.38,
                    color: .cyan
                )
            }
        }
    }

    private func drawOrb(in context: inout GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    color.opacity(0.20),
                    color.opacity(0.05),
                    .clear
                ]),
                center: center,
                startRadius: radius * 0.10,
                endRadius: radius
            )
        )
    }
}

private struct AppShaderVeil: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(reduceMotion ? .periodic(from: .now, by: 60) : .periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                var path = Path()
                let rows = 18
                let stepY = size.height / CGFloat(rows)

                for row in 0...rows {
                    let y = CGFloat(row) * stepY
                    path.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: CGFloat(0), through: size.width, by: 18) {
                        let wave = sin((x * 0.014) + CGFloat(t * 0.45) + CGFloat(row) * 0.55) * 6
                        path.addLine(to: CGPoint(x: x, y: y + wave))
                    }
                }

                context.stroke(
                    path,
                    with: .color(.white.opacity(0.24)),
                    lineWidth: 0.7
                )
            }
        }
    }
}
