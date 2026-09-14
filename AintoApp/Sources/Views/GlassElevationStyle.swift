import SwiftUI

struct GlassElevationStyle {
    struct Shadow {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    struct RGBColor {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }
    }

    static let coolGrayShadow = RGBColor(red: 0.16, green: 0.19, blue: 0.26)

    let nearShadow: Shadow
    let farShadow: Shadow
    let highlightOpacity: Double

    static let mainPanel = GlassElevationStyle(
        nearShadow: .init(opacity: 0.24, radius: 12, y: 4),
        farShadow: .init(opacity: 0.30, radius: 48, y: 24),
        highlightOpacity: 0.24
    )

    static let card = GlassElevationStyle(
        nearShadow: .init(opacity: 0.12, radius: 5, y: 2),
        farShadow: .init(opacity: 0.16, radius: 18, y: 8),
        highlightOpacity: 0.16
    )
}

extension View {
    func glassElevation(_ style: GlassElevationStyle, shape: RoundedRectangle) -> some View {
        shadow(color: GlassElevationStyle.coolGrayShadow.color.opacity(style.nearShadow.opacity), radius: style.nearShadow.radius, y: style.nearShadow.y)
            .shadow(color: GlassElevationStyle.coolGrayShadow.color.opacity(style.farShadow.opacity), radius: style.farShadow.radius, y: style.farShadow.y)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(style.highlightOpacity), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }
}
