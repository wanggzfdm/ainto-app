import AppKit

enum JSONFormatterWindowStyle {
    static let usesNativeWindowShadow = true

    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable
    ]
}
