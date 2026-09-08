import XCTest
@testable import AintoApp

final class JSONFormatterCoreTests: XCTestCase {
    func testPrettyObject() throws { XCTAssertEqual(try JSONFormatterCore.format("{\"b\":2,\"a\":1}"), "{\n  \"b\" : 2,\n  \"a\" : 1\n}") }
    func testCompactPreservesStringWhitespaceAndPunctuation() throws { let input = "{\"s\":\" a,}\"}"; XCTAssertEqual(try JSONFormatterCore.compact(input), input) }
    func testEscapedCompactWrapsCompactJSONInAJSONString() throws {
        XCTAssertEqual(
            try JSONFormatterCore.escapedCompact("{\"name\":\"Ainto\",\"enabled\":true}"),
            "\"{\\\"name\\\":\\\"Ainto\\\",\\\"enabled\\\":true}\""
        )
    }
    func testRecursivelyExpandsAndCollapsesTree() throws {
        let root = try JSONFormatterCore.tree("{\"object\":{\"array\":[1]}}")
        JSONFormatterCore.setExpansion(of: root, expanded: false)
        XCTAssertFalse(root.isExpanded)
        XCTAssertFalse(root.children[0].isExpanded)
        XCTAssertFalse(root.children[0].children[0].isExpanded)
        JSONFormatterCore.setExpansion(of: root, expanded: true)
        XCTAssertTrue(root.isExpanded)
        XCTAssertTrue(root.children[0].isExpanded)
        XCTAssertTrue(root.children[0].children[0].isExpanded)
    }
    func testScalarString() throws { XCTAssertEqual(try JSONFormatterCore.compact("\"hello\""), "\"hello\"") }
    func testScalarNumber() throws { XCTAssertEqual(try JSONFormatterCore.compact("-1.25e2"), "-125") }
    func testScalarBool() throws { XCTAssertEqual(try JSONFormatterCore.compact("true"), "true") }
    func testScalarNull() throws { XCTAssertEqual(try JSONFormatterCore.compact("null"), "null") }
    func testUnicode() throws { XCTAssertEqual(try JSONFormatterCore.compact("{\"雪\":\"☃️\"}"), "{\"雪\":\"☃️\"}") }
    func testTrailingCommaLineColumnObject() { assertLocation("{\n  \"a\": 1,\n}", line: 3, column: 1) }
    func testTrailingCommaLineColumnArray() { assertLocation("[\n  1,\n]", line: 3, column: 1) }
    func testNestedMalformedHasReasonableLocation() { assertLocation("{\n  \"a\": {\n    \"b\": ]\n  }\n}", line: 3, column: 10) }
    func testMalformedJSONAfterUnicodeReportsLineAndColumn() { assertLocation("{\n  \"雪\": 1,\n  \"bad\": ]\n}", line: 3, column: 10) }
    func testSyntaxTokensKinds() { let ts = JSONFormatterCore.syntaxTokens("{\"k\":\"v\",\"n\":12,true:false,null:null}"); XCTAssertTrue(ts.contains { $0.text == "\"k\"" && $0.kind == .key }); XCTAssertTrue(ts.contains { $0.text == "\"v\"" && $0.kind == .string }); XCTAssertTrue(ts.contains { $0.text == "12" && $0.kind == .number }); XCTAssertTrue(ts.contains { $0.text == "true" && $0.kind == .bool }); XCTAssertTrue(ts.contains { $0.text == "null" && $0.kind == .null }); XCTAssertTrue(ts.contains { $0.text == ":" && $0.kind == .punctuation }) }
    func testLogicalLineCountEmptyAndSingleLine() { XCTAssertEqual(JSONFormatterCore.logicalLineCount(""), 1); XCTAssertEqual(JSONFormatterCore.logicalLineCount("hello"), 1) }
    func testLogicalLineCountMultilineIncludesTrailingLine() { XCTAssertEqual(JSONFormatterCore.logicalLineCount("one\ntwo\n"), 3); XCTAssertEqual(JSONFormatterCore.lineNumbers(for: "one\ntwo"), [1, 1, 1, 1, 2, 2, 2]) }
    func testFilterDotPath() throws { XCTAssertEqual(try JSONFormatterCore.filter("{\"key\":{\"subkey\":1}}", expression: ".key.subkey") as? Int, 1) }
    func testFilterArrayPath() throws { XCTAssertEqual(try JSONFormatterCore.filter("[[10,20]]", expression: "[0][1]") as? Int, 20) }
    func testFilterMapNoSpaces() throws { XCTAssertEqual(try JSONFormatterCore.filter("{\"items\":[{\"v\":1},{\"v\":2}]}", expression: ".items.map(x=>x.v)[1]") as? Int, 2) }
    func testFilterMapSpaces() throws { XCTAssertEqual(try JSONFormatterCore.filter("{\"items\":[{\"v\":1},{\"v\":2}]}", expression: ".items.map( x => x.v )[0]") as? Int, 1) }
    func testFilterChain() throws { XCTAssertEqual(try JSONFormatterCore.filter("{\"items\":[{\"v\":{\"ok\":true}}]}", expression: ".items.map(x => x.v)[0].ok") as? Bool, true) }
    func testFilterQuotedKeyJSONEscapesAndUnicode() throws {
        let json = "{\"a\\\"b\":1,\"a\\\\b\":2,\"雪😀\":3}"
        XCTAssertEqual(try JSONFormatterCore.filter(json, expression: "[\"a\\\"b\"]") as? Int, 1)
        XCTAssertEqual(try JSONFormatterCore.filter(json, expression: "[\"a" + "\\\\" + "b\"]") as? Int, 2)
        XCTAssertEqual(try JSONFormatterCore.filter(json, expression: "[\"\\u96ea\\uD83D\\uDE00\"]") as? Int, 3)
    }
    func testFilterQuotedKeyRejectsSingleQuoteAndMalformedEscapes() {
        for expression in ["['不允许单引号']", "[\"unterminated]", "[\"bad\\q\"]", "[\"bad\\u12\"]", "[\"bad\\uD800\"]"] { XCTAssertThrowsError(try JSONFormatterCore.filter("{\"x\":1}", expression: expression)) }
    }
    func testFilterMissingOutOfRangeWrongReceiverAndMapType() { for expression in [".missing", ".items[9]", ".key.foo", ".items.map(x => x.v)"] { XCTAssertThrowsError(try JSONFormatterCore.filter("{\"items\":[1],\"key\":2}", expression: expression)) } }
    func testFilterRejectsUnsafeAndNegativeAndEmpty() { for expression in [".items.filter(x)", "x=>evil()", ".items[-1]", ""] { XCTAssertThrowsError(try JSONFormatterCore.filter("{\"items\":[]}", expression: expression)) } }
    func testTreeChildrenPathsToggleAndLeafDisplay() throws {
        let root = try JSONFormatterCore.tree("{\"data\":{\"items\":[1],\"yes\":true,\"none\":null,\"word\":\"x\"}}")
        XCTAssertEqual(root.path, "."); XCTAssertEqual(root.children.first?.path, ".data")
        let old = root.isExpanded; root.toggle(); XCTAssertEqual(root.isExpanded, !old); root.collapse(); XCTAssertFalse(root.isExpanded); root.expand(); XCTAssertTrue(root.isExpanded)
        let leaves = root.children[0].children.reduce(into: [:]) { $0[$1.key ?? ""] = ($1.type, JSONEditorViewHelpers.displayValue($1.value)) }
        XCTAssertEqual(leaves["yes"]?.0, "bool"); XCTAssertEqual(leaves["yes"]?.1, "true"); XCTAssertEqual(leaves["none"]?.1, "null")
    }
    func testClipboardContextRecognizesOnlyValidJSON() {
        XCTAssertTrue(JSONFormatterCore.isValidJSON("{\"ok\":true}"))
        XCTAssertTrue(JSONFormatterCore.isValidJSON("[1,2,3]"))
        XCTAssertFalse(JSONFormatterCore.isValidJSON("plain text"))
        XCTAssertFalse(JSONFormatterCore.isValidJSON("{\"broken\":}"))
        XCTAssertFalse(JSONFormatterCore.isValidJSON("   \n  "))
    }
    func testFormatsReadableJSONErrorMessage() {
        let error = JSONFormatterError(message: "Unexpected token", line: 3, column: 8)
        XCTAssertEqual(JSONEditorViewHelpers.errorMessage(error), "Line 3, column 8: Unexpected token")
    }
    func testLineNumberLabelUsesActualNumber() { XCTAssertEqual(JSONEditorViewHelpers.lineNumberLabel(12), "12"); XCTAssertNotEqual(JSONEditorViewHelpers.lineNumberLabel(12), "\\(line)") }
    private func assertLocation(_ text: String, line: Int, column: Int) { do { _ = try JSONFormatterCore.parse(text); XCTFail("expected error") } catch let e as JSONFormatterError { XCTAssertEqual(e.line, line); XCTAssertEqual(e.column, column) } catch { XCTFail("wrong error: \(error)") } }
}
