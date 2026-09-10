import SwiftUI

struct AppShaderEffectModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                AppShaderBackdrop(reduceTransparency: reduceTransparency)
                    .ignoresSafeArea()
            }
            .overlay {
                AppShaderVeil()
                    .blendMode(colorScheme == .dark ? .screen : .softLight)
                    .opacity(reduceTransparency ? 0 : colorScheme == .dark ? 0.10 : 0.06)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
    let reduceTransparency: Bool

    var body: some View {
        LinearGradient(
            colors: reduceTransparency ? [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor)
            ] : [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.055),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct AppShaderVeil: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var path = Path()
            let rows = 14
            let stepY = size.height / CGFloat(rows)

            for row in 0...rows {
                let y = CGFloat(row) * stepY
                path.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                    let wave = sin((x * 0.012) + CGFloat(row) * 0.48) * 3
                    path.addLine(to: CGPoint(x: x, y: y + wave))
                }
            }

            context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.5)
        }
    }
}
