import CoreGraphics

enum JSONFormatterLineNumberLayout {
    static func rulerY(documentY: CGFloat, convertedDocumentOriginY: CGFloat) -> CGFloat {
        documentY - convertedDocumentOriginY
    }

    static func lineNumber(in text: String, atUTF16Offset offset: Int) -> Int {
        let clampedOffset = min(max(0, offset), text.utf16.count)
        let index = String.Index(utf16Offset: clampedOffset, in: text)
        return text[..<index].reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
    }
}
