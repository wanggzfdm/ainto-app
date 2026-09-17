import SwiftUI

/// Claude Code icon using SF Symbol (no Anthropic logo — trademark restriction).
struct ClaudeIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.7))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
