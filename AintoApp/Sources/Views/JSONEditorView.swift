import SwiftUI
import AppKit

public enum JSONEditorMode: String, CaseIterable, Identifiable {
    case code = "Code"
    case tree = "Tree"
    public var id: String { rawValue }
}

public struct JSONEditorView: View {
    @Binding var text: String
    @State private var root: JSONTreeNode?
    @State private var message: String?
    @State private var mode: JSONEditorMode = .code
    public init(text: Binding<String>) { _text = text }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(JSONEditorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                if mode == .tree {
                    Button(L("json.collapseAll")) {
                        root.map { JSONFormatterCore.setExpansion(of: $0, expanded: false) }
                    }
                    .controlSize(.small)
                    Button(L("json.expandAll")) {
                        root.map { JSONFormatterCore.setExpansion(of: $0, expanded: true) }
                    }
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            switch mode {
            case .code:
                SyntaxJSONTextView(text: $text)
                    .frame(height: 340)
            case .tree:
                if let root {
                    ScrollView([.vertical, .horizontal]) {
                        JSONTreeRow(node: root, depth: 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(height: 340)
                } else {
                    ContentUnavailableView("Invalid JSON", systemImage: "exclamationmark.triangle")
                        .frame(height: 340)
                }
            }

            if let message {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .onAppear { refreshTree() }
        .onChange(of: text) { _, _ in refreshTree() }
    }
    private func refreshTree() {
        do {
            root = try JSONFormatterCore.tree(text)
            message = nil
        } catch {
            root = nil
            message = JSONEditorViewHelpers.errorMessage(error)
        }
    }
}

private final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    private let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let visible = textView.enclosingScrollView?.contentView.bounds ?? rect
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let lineCharacterRange = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let line = JSONFormatterLineNumberLayout.lineNumber(
                in: textView.string,
                atUTF16Offset: lineCharacterRange.location
            )
            let documentY = usedRect.minY + textView.textContainerInset.height
            let y = JSONFormatterLineNumberLayout.rulerY(
                documentY: documentY,
                convertedDocumentOriginY: visible.origin.y
            )
            let baseline = y + (usedRect.height - self.numberFont.ascender + self.numberFont.descender) / 2
            let label = NSAttributedString(string: JSONEditorViewHelpers.lineNumberLabel(line), attributes: [.font: self.numberFont, .foregroundColor: NSColor.secondaryLabelColor])
            label.draw(at: NSPoint(x: self.bounds.width - label.size().width - 8, y: baseline))
        }
    }
}

private struct SyntaxJSONTextView: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.borderType = .bezelBorder
        scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        let ruler = LineNumberRulerView(scrollView: scroll, orientation: .verticalRuler); ruler.ruleThickness = 42; scroll.verticalRulerView = ruler
        let editor = NSTextView(); editor.delegate = context.coordinator; editor.isRichText = true; editor.allowsUndo = true; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular); editor.backgroundColor = .clear; editor.drawsBackground = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = true; editor.autoresizingMask = [.height]; editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor; context.coordinator.editor = editor
        (scroll.verticalRulerView as? LineNumberRulerView)?.textView = editor
        context.coordinator.update(text); context.coordinator.invalidateRuler()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.parent = self; context.coordinator.update(text); context.coordinator.invalidateRuler() }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxJSONTextView; weak var editor: NSTextView?; private var updating = false
        init(_ parent: SyntaxJSONTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) { guard !updating, let editor else { return }; parent.text = editor.string; update(editor.string); invalidateRuler() }
        func invalidateRuler() { editor?.enclosingScrollView?.verticalRulerView?.needsDisplay = true }
        func update(_ value: String) {
            guard let editor, !updating, editor.string != value || editor.textStorage?.length == 0 else { return }
            updating = true
            defer { updating = false }
            let selectedRange = editor.selectedRange()
            let storage = editor.textStorage!
            storage.beginEditing()
            editor.undoManager?.disableUndoRegistration()
            storage.setAttributedString(NSAttributedString(string: value, attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular), .foregroundColor: NSColor.labelColor]))
            let colors: [JSONSyntaxKind: NSColor] = [.key: .systemBlue, .string: .systemGreen, .number: .systemOrange, .bool: .systemPurple, .null: .systemPurple, .punctuation: .secondaryLabelColor]
            for token in JSONFormatterCore.syntaxTokens(value) { storage.addAttribute(.foregroundColor, value: colors[token.kind] ?? NSColor.labelColor, range: NSRange(token.range, in: value)) }
            storage.endEditing()
            editor.undoManager?.enableUndoRegistration()
            let location = min(selectedRange.location, value.utf16.count)
            let length = min(selectedRange.length, value.utf16.count - location)
            editor.setSelectedRange(NSRange(location: location, length: length))
        }
    }
}

private struct JSONTreeRow: View {
    @ObservedObject var node: JSONTreeNode
    let depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { node.toggle() } label: {
                HStack(spacing: 4) { Image(systemName: node.children.isEmpty ? "circle.fill" : (node.isExpanded ? "chevron.down" : "chevron.right")).font(.caption2); Text(node.key ?? "root").foregroundStyle(.secondary); Text(node.type).foregroundStyle(color); if node.children.isEmpty { Text(JSONEditorViewHelpers.displayValue(node.value)).foregroundStyle(.primary) } }
            }.buttonStyle(.plain).padding(.leading, CGFloat(depth * 16))
            if node.isExpanded { ForEach(node.children) { JSONTreeRow(node: $0, depth: depth + 1) } }
        }.font(.system(.caption, design: .monospaced))
    }
    private var color: Color { switch node.type { case "string": return .green; case "number": return .orange; case "bool": return .blue; case "null": return .purple; default: return .teal } }
}
public enum JSONEditorViewHelpers {
    public static func lineNumberLabel(_ line: Int) -> String { String(line) }
    public static func errorMessage(_ error: Error) -> String {
        if let jsonError = error as? JSONFormatterError {
            return "Line \(jsonError.line), column \(jsonError.column): \(jsonError.message)"
        }
        return (error as NSError).localizedDescription
    }
    public static func displayValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let s = value as? String { return "\"\(s)\"" }
        return String(describing: value)
    }
}

public struct JSONFormatterView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @Binding private var text: String
    private let onDetach: (() -> Void)?
    private let onEmbed: (() -> Void)?
    private let onClose: (() -> Void)?
    @State private var filter = ""
    @State private var message: String?
    public init(
        text: Binding<String>,
        onDetach: (() -> Void)? = nil,
        onEmbed: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        showTopActions: Bool = true
    ) {
        _text = text
        self.onDetach = onDetach
        self.onEmbed = onEmbed
        self.onClose = onClose
        self.showTopActions = showTopActions
    }
    private let showTopActions: Bool
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "curlybraces")
                Text(L("json.title")).font(.headline)
                Spacer()
                if let onDetach {
                    Button(action: onDetach) { Image(systemName: "arrow.up.right.and.arrow.down.left") }
                        .buttonStyle(.plain)
                        .help(L("json.openWindow"))
                }
                if let onEmbed {
                    Button(action: onEmbed) { Image(systemName: "arrow.down.left.and.arrow.up.right") }
                        .buttonStyle(.plain)
                        .help(L("json.openWindow"))
                }
                if let onClose { Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).help(L("json.close")) }
            }
            .padding(12)
            Divider()
            JSONEditorView(text: $text)
            Divider()
            HStack {
                Text(L("json.filter")).foregroundStyle(.secondary)
                TextField(".items.map(x => x.val)[0]", text: $filter)
                Button(L("json.apply")) { applyFilter() }
            }
            .padding(10)
            if let message { Text(message).foregroundStyle(.red).font(.caption).padding(.bottom, 8) }
            if JSONFormatterWorkspaceStyle.usesBottomActionBar {
                Divider()
                HStack(spacing: 8) {
                    Button(L("json.format")) { run { try JSONFormatterCore.format(text) } }
                        .buttonStyle(.borderedProminent)
                    Button(L("json.minify")) { run { try JSONFormatterCore.compact(text) } }
                    Divider().frame(height: 18)
                    Button(L("json.copy")) { copy(text) }
                    Button(L("json.compactCopy")) {
                        run {
                            let compact = try JSONFormatterCore.compact(text)
                            copy(compact)
                            return text
                        }
                    }
                    Button(L("json.escapedCompactCopy")) {
                        run {
                            let escaped = try JSONFormatterCore.escapedCompact(text)
                            copy(escaped)
                            return text
                        }
                    }
                    Spacer()
                    Button(L("json.clear"), role: .destructive) { text = ""; message = nil }
                }
                .controlSize(.small)
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .glassElevation(.card, shape: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
    private func run(_ operation: () throws -> String) {
        do { text = try operation(); message = nil }
        catch { message = JSONEditorViewHelpers.errorMessage(error) }
    }
    private func applyFilter() {
        guard !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = L("json.emptyFilter"); return }
        do {
            let value = try JSONFormatterCore.filter(text, expression: filter)
            text = try JSONFormatterCore.compact(String(data: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), encoding: .utf8) ?? "")
            message = nil
        } catch {
            message = JSONEditorViewHelpers.errorMessage(error)
        }
    }
}
