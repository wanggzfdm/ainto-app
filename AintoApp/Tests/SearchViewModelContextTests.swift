import XCTest
@testable import AintoApp

@MainActor
final class SearchViewModelContextTests: XCTestCase {
    func testValidClipboardJSONAddsContextCommandAndPrefillsEditor() {
        let viewModel = SearchViewModel()
        let json = "  {\n  \"name\": \"Ainto\"\n}  "

        viewModel.updateClipboardContext(json)
        viewModel.applyApplicationRefresh(
            allApplications: [],
            recentApplications: viewModel.results
        )
        let result = viewModel.results.first { $0.title == L("search.openJSON") }
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.subtitle, L("search.detectedJSON"))

        result?.action()
        XCTAssertEqual(viewModel.page, .main)
        XCTAssertTrue(viewModel.isJSONFormatterExpanded)
        XCTAssertEqual(viewModel.jsonFormatterInput, try JSONFormatterCore.format(json))
        XCTAssertTrue(viewModel.hasClipboardJSON)
    }

    func testEscapedJSONClipboardIsDecodedOnceBeforeFormatting() throws {
        let viewModel = SearchViewModel()
        let escapedJSON = "\"{\\\"name\\\":\\\"Ainto\\\"}\""

        viewModel.updateClipboardContext(escapedJSON)
        viewModel.applyApplicationRefresh(
            allApplications: [],
            recentApplications: viewModel.results
        )
        viewModel.results.first?.action()

        XCTAssertEqual(viewModel.jsonFormatterInput, try JSONFormatterCore.format("{\"name\":\"Ainto\"}"))
    }

    func testPlainJSONStringClipboardIsNotDecodedAsJSONDocument() {
        let viewModel = SearchViewModel()
        viewModel.updateClipboardContext("\"hello\"")

        XCTAssertFalse(viewModel.results.contains { $0.title == L("search.openJSON") })
    }
    func testDetachingFormatterCollapsesInlineWithoutLosingContent() {
        let viewModel = SearchViewModel()
        viewModel.openJSONFormatter(with: "{\"value\":1}")

        viewModel.requestJSONFormatterWindow()

        XCTAssertFalse(viewModel.isJSONFormatterExpanded)
        XCTAssertTrue(viewModel.shouldOpenJSONFormatterWindow)
        XCTAssertEqual(viewModel.jsonFormatterInput, "{\"value\":1}")
    }

    func testClosingDetachedFormatterKeepsContent() {
        let viewModel = SearchViewModel()
        viewModel.openJSONFormatter(with: "[1,2]")
        viewModel.requestJSONFormatterWindow()

        viewModel.didCloseJSONFormatterWindow()

        XCTAssertFalse(viewModel.shouldOpenJSONFormatterWindow)
        XCTAssertEqual(viewModel.jsonFormatterInput, "[1,2]")
    }

    func testUpdatingQueryPublishesMatchingResultsImmediately() {
        let viewModel = SearchViewModel()

        viewModel.updateQuery("json")

        XCTAssertEqual(viewModel.query, "json")
        XCTAssertTrue(viewModel.results.contains { $0.title == L("json.title") })
    }

    func testPlainClipboardTextSearchesWithoutFillingQuery() {
        let viewModel = SearchViewModel()
        viewModel.updateClipboardContext("json formatter")

        XCTAssertTrue(viewModel.hasClipboardText)
        XCTAssertEqual(viewModel.clipboardText, "json formatter")
        XCTAssertEqual(viewModel.query, "")
        XCTAssertFalse(viewModel.results.isEmpty)
    }

    func testActivatingClipboardTextMovesFullTextIntoQuery() {
        let viewModel = SearchViewModel()
        viewModel.updateClipboardContext("terminal")

        viewModel.useClipboardTextAsQuery()

        XCTAssertEqual(viewModel.query, "terminal")
        XCTAssertFalse(viewModel.hasClipboardText)
    }

    func testWhitespaceClipboardClearsTextAndJSONContexts() {
        let viewModel = SearchViewModel()
        viewModel.updateClipboardContext("terminal")
        viewModel.updateClipboardContext("  \n ")

        XCTAssertFalse(viewModel.hasClipboardText)
        XCTAssertFalse(viewModel.hasClipboardJSON)
    }

    func testNonJSONClipboardDoesNotAddContextCommand() {
        let viewModel = SearchViewModel()

        viewModel.updateClipboardContext("ordinary clipboard text")

        XCTAssertFalse(viewModel.results.contains { $0.title == L("search.openJSON") })
    }
}
