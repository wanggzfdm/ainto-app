import Foundation
import SwiftUI
import CoreFoundation

public struct JSONFormatterError: Error, Equatable, LocalizedError {
    public let message: String; public let line: Int; public let column: Int
    public var errorDescription: String { "\(message) (line \(line), column \(column))" }
}

public enum JSONSyntaxKind: Equatable { case key, string, number, bool, null, punctuation }
public struct JSONSyntaxToken: Equatable { public let text: String; public let kind: JSONSyntaxKind; public let range: Range<String.Index>; public init(text: String, kind: JSONSyntaxKind, range: Range<String.Index>) { self.text = text; self.kind = kind; self.range = range } }

public final class JSONTreeNode: Identifiable, ObservableObject {
    public let id = UUID(); public let key: String?; public let value: Any; public let type: String; public let path: String
    @Published public var isExpanded: Bool
    @Published public var children: [JSONTreeNode]
    public init(key: String? = nil, value: Any, expanded: Bool = true, path: String = ".") {
        self.key = key; self.value = value; self.path = path; self.isExpanded = expanded
        if value is [String: Any] { type = "object" } else if value is [Any] { type = "array" } else if value is String { type = "string" } else if let number = value as? NSNumber { type = JSONTreeNode.isBoolean(number) ? "bool" : "number" } else if value is NSNull { type = "null" } else { type = "unknown" }
        if let object = value as? [String: Any] { children = object.keys.sorted().compactMap { k in JSONTreeNode(key: k, value: object[k]!, path: path == "." ? ".\(k)" : "\(path).\(k)") } }
        else if let array = value as? [Any] { children = array.enumerated().map { JSONTreeNode(key: "[\($0.offset)]", value: $0.element, path: "\(path)[\($0.offset)]") } }
        else { children = [] }
    }
    public func toggle() { isExpanded.toggle() }
    public func collapse() { isExpanded = false }
    public func expand() { isExpanded = true }
    private static func isBoolean(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}

public enum JSONFormatterCore {
    /// Returns the one-based logical line number for every character position.
    public static func lineNumbers(for text: String) -> [Int] {
        var line = 1
        var result: [Int] = []
        result.reserveCapacity(text.utf16.count)
        for character in text {
            result.append(contentsOf: repeatElement(line, count: character.utf16.count))
            if character == "\n" { line += 1 }
        }
        return result
    }

    /// Returns the number of logical lines, including the final empty line after a newline.
    public static func logicalLineCount(_ text: String) -> Int {
        lineNumbers(for: text).last.map { $0 + (text.last == "\n" ? 1 : 0) } ?? 1
    }

    public static func isValidJSON(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return (try? parse(text)) != nil
    }

    public static func parse(_ text: String) throws -> Any {
        do {
            try rejectTrailingCommas(text)
            return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch let e as JSONFormatterError { throw e }
        catch {
            let ns = error as NSError
            let byteOffset = ns.userInfo["NSJSONSerializationErrorIndex"] as? Int ?? text.utf8.count
            throw JSONFormatterError(message: ns.localizedDescription, line: lineColumn(text, byteOffset: byteOffset).0, column: lineColumn(text, byteOffset: byteOffset).1)
        }
    }
    private static func rejectTrailingCommas(_ text: String) throws {
        var inString = false, escaped = false; var lastSignificant: (Character, Int)?
        var index = 0
        for c in text {
            if inString { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }; index += c.utf8.count; continue }
            if c == "\"" { inString = true; index += 1; continue }
            if c == "," { lastSignificant = (c, index) }
            else if !c.isWhitespace { if (c == "}" || c == "]"), lastSignificant?.0 == "," { let p = lineColumn(text, byteOffset: index); throw JSONFormatterError(message: "Trailing comma", line: p.0, column: p.1) }; lastSignificant = (c, index) }
            index += c.utf8.count
        }
    }
    private static func lineColumn(_ text: String, byteOffset: Int) -> (Int, Int) {
        let bytes = Array(text.utf8); let offset = min(max(0, byteOffset), bytes.count); let prefix = String(decoding: bytes.prefix(offset), as: UTF8.self)
        let line = prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }; let last = prefix.lastIndex(of: "\n"); let segment = last.map { String(prefix[prefix.index(after: $0)...]) } ?? prefix
        return (line, max(1, segment.count + 1))
    }
    public static func format(_ text: String) throws -> String { try serialize(try parse(text), options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]) }
    public static func compact(_ text: String) throws -> String { try serialize(try parse(text), options: [.withoutEscapingSlashes, .fragmentsAllowed]) }
    private static func serialize(_ value: Any, options: JSONSerialization.WritingOptions) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self) }
    public static func syntaxTokens(_ text: String) -> [JSONSyntaxToken] {
        var result: [JSONSyntaxToken] = [], i = text.startIndex
        while i < text.endIndex { if text[i].isWhitespace { i = text.index(after: i); continue }; let start = i
            if text[i] == "\"" { i = text.index(after: i); var esc = false; while i < text.endIndex { if esc { esc = false } else if text[i] == "\\" { esc = true } else if text[i] == "\"" { i = text.index(after: i); break }; i = text.index(after: i) }; let after = text[i...].first(where: { !$0.isWhitespace }); let tokenKind: JSONSyntaxKind = (after == ":") ? .key : .string; result.append(JSONSyntaxToken(text: String(text[start..<i]), kind: tokenKind, range: start..<i)) }
            else if ",:{}[]".contains(text[i]) { i = text.index(after: i); result.append(JSONSyntaxToken(text: String(text[start..<i]), kind: .punctuation, range: start..<i)) }
            else { while i < text.endIndex && !text[i].isWhitespace && !",:{}[]".contains(text[i]) { i = text.index(after: i) }; let word = String(text[start..<i]); let kind: JSONSyntaxKind = ["true","false"].contains(word) ? .bool : word == "null" ? .null : Double(word) != nil ? .number : .punctuation; result.append(JSONSyntaxToken(text: word, kind: kind, range: start..<i)) }
            if i < text.endIndex && ",:{}[]".contains(text[i]) { let p = i; i = text.index(after: i); result.append(JSONSyntaxToken(text: String(text[p..<i]), kind: .punctuation, range: p..<i)) }
        }; return result
    }
    public static func tree(_ text: String) throws -> JSONTreeNode { JSONTreeNode(value: try parse(text)) }
    public static func filter(_ text: String, expression: String) throws -> Any {
        var value = try parse(text); let chars = Array(expression); var i = 0
        func error(_ message: String) -> JSONFormatterError { JSONFormatterError(message: message, line: 1, column: max(1, i + 1)) }
        func skip() { while i < chars.count && chars[i].isWhitespace { i += 1 } }
        func key() throws -> String { skip(); guard i < chars.count else { throw error("Expected key") }; if chars[i] == "\"" { return try quotedKey(&i, chars: chars) }; let s = i; while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }; guard s < i else { throw error("Expected object key") }; return String(chars[s..<i]) }
        func quotedKey(_ index: inout Int, chars: [Character]) throws -> String { func fail(_ message: String) -> JSONFormatterError { JSONFormatterError(message: message, line: 1, column: index + 1) }; index += 1; var result = ""; while index < chars.count { let c = chars[index]; index += 1; if c == "\"" { return result }; guard c == "\\" else { result.append(c); continue }; guard index < chars.count else { throw fail("Unterminated escape in quoted key") }; let escaped = chars[index]; index += 1; switch escaped { case "\"", "\\", "/": result.append(escaped); case "b": result.append("\u{8}"); case "f": result.append("\u{c}"); case "n": result.append("\n"); case "r": result.append("\r"); case "t": result.append("\t"); case "u": guard index + 4 <= chars.count else { throw fail("Invalid Unicode escape in quoted key") }; let hex = String(chars[index..<index+4]); guard let first = UInt16(hex, radix: 16) else { throw fail("Invalid Unicode escape in quoted key") }; index += 4; if (0xD800...0xDBFF).contains(first) { guard index + 6 <= chars.count, chars[index] == "\\", chars[index + 1] == "u", let second = UInt16(String(chars[index+2..<index+6]), radix: 16), (0xDC00...0xDFFF).contains(second) else { throw fail("Invalid Unicode surrogate pair in quoted key") }; index += 6; let scalar = UnicodeScalar(0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00))!; result.append(Character(scalar)) } else if (0xDC00...0xDFFF).contains(first) { throw fail("Invalid Unicode surrogate pair in quoted key") } else { result.append(Character(UnicodeScalar(first)!)) }; default: throw fail("Invalid escape in quoted key") } }; throw fail("Unterminated quoted key") }
        skip(); guard i < chars.count, chars[i] == "." || chars[i] == "[" else { throw error("Filter must start with . or [") }
        while i < chars.count { skip(); if chars[i] == "." { i += 1; skip(); if i + 3 <= chars.count && String(chars[i..<i+3]) == "map" { i += 3; skip(); guard i < chars.count, chars[i] == "(" else { throw error("Invalid map expression") }; i += 1; skip(); let mapStart = i; while i < chars.count && (chars[i].isWhitespace || chars[i].isLetter || chars[i] == "=" || chars[i] == ">") { i += 1 }; let mapHead = String(chars[mapStart..<i]).filter { !$0.isWhitespace }; guard mapHead == "x=>x" else { throw error("Only x => x.key is supported") }; skip(); guard i < chars.count, chars[i] == "." else { throw error("map requires x.key") }; i += 1; let k = try key(); skip(); guard i < chars.count, chars[i] == ")" else { throw error("Invalid map expression") }; i += 1; guard let a = value as? [Any] else { throw error("map requires an array") }; value = try a.map { try lookup($0, k, error) } } else { value = try lookup(value, try key(), error) } } else if chars[i] == "[" { i += 1; skip(); if i < chars.count, chars[i] == "\"" { let k = try key(); skip(); guard i < chars.count, chars[i] == "]" else { throw error("Invalid bracket key") }; i += 1; value = try lookup(value, k, error) } else { let s = i; while i < chars.count && chars[i].isNumber { i += 1 }; guard s < i, let n = Int(String(chars[s..<i])) else { throw error("Invalid array index") }; skip(); guard i < chars.count, chars[i] == "]" else { throw error("Invalid array index") }; i += 1; guard let a = value as? [Any], n < a.count else { throw error("Array index out of bounds") }; value = a[n] } } else { throw error("Unexpected filter token") } }; return value
    }
    private static func lookup(_ value: Any, _ key: String, _ error: (String) -> JSONFormatterError) throws -> Any { guard let d = value as? [String: Any], let v = d[key] else { throw error("Missing key: \(key)") }; return v }
}
