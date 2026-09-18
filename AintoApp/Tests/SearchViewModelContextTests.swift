import XCTest
@testable import AintoApp

@MainActor
final class SearchViewModelContextTests: XCTestCase {
    func testAppsCommandShowsOnlyLaunchpadAction() {
        let viewModel = SearchViewModel()

        viewModel.updateQuery("/apps")

        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.title, "打开启动台")
    }

    func testAppsCommandActionExpandsLaunchpadAndClearsQueryAndClipboardContext() {
        let viewModel = SearchViewModel()
        viewModel.updateClipboardContext("clipboard text")
        viewModel.updateQuery("/apps")

        viewModel.results.first?.action()

        XCTAssertEqual(viewModel.query, "")
        XCTAssertTrue(viewModel.isApplicationGridExpanded)
        XCTAssertFalse(viewModel.hasClipboardText)
        XCTAssertFalse(viewModel.hasClipboardJSON)
    }

    func testAppsCommandRequiresExactQuery() {
        let viewModel = SearchViewModel()

        viewModel.updateQuery("/apps Terminal")

        XCTAssertFalse(viewModel.results.contains { $0.title == "打开启动台" })
    }

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

    func testClipboardContextIsConsumedOnlyOncePerChangeCount() {
        let viewModel = SearchViewModel()

        XCTAssertTrue(viewModel.consumeClipboardContextIfNeeded("terminal", changeCount: 10))
        XCTAssertTrue(viewModel.hasClipboardText)
        XCTAssertFalse(viewModel.consumeClipboardContextIfNeeded("terminal", changeCount: 10))
        XCTAssertFalse(viewModel.hasClipboardText)
    }

    func testNewChangeCountReactivatesIdenticalClipboardText() {
        let viewModel = SearchViewModel()

        XCTAssertTrue(viewModel.consumeClipboardContextIfNeeded("terminal", changeCount: 10))
        XCTAssertTrue(viewModel.consumeClipboardContextIfNeeded("terminal", changeCount: 11))
        XCTAssertTrue(viewModel.hasClipboardText)
    }

    func testClearingClipboardContextRemovesTextAndJSONContext() {
        let viewModel = SearchViewModel()
        _ = viewModel.consumeClipboardContextIfNeeded("terminal", changeCount: 10)

        viewModel.clearClipboardContext()

        XCTAssertFalse(viewModel.hasClipboardText)
        XCTAssertFalse(viewModel.hasClipboardJSON)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testClosingApplicationLaunchpadReturnsToDefaultInputState() {
        let viewModel = SearchViewModel()
        viewModel.openApplicationLaunchpad()

        viewModel.closeApplicationLaunchpad()

        XCTAssertFalse(viewModel.isApplicationGridExpanded)
        XCTAssertEqual(viewModel.query, "")
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
