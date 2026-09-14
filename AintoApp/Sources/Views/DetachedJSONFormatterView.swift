import SwiftUI

struct DetachedJSONFormatterView: View {
    @Binding var text: String
    let onEmbed: () -> Void
    let onClose: () -> Void

    var body: some View {
        JSONFormatterView(
            text: $text,
            onEmbed: onEmbed,
            onClose: onClose,
            showTopActions: false
        )
        .frame(minWidth: 800, minHeight: 600)
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}
