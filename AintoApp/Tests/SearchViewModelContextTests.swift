import XCTest
@testable import AintoApp

@MainActor
final class SearchViewModelContextTests: XCTestCase {
    func testValidClipboardJSONAddsContextCommandAndPrefillsEditor() {
        let viewModel = SearchViewModel()
        let json = "  {\n  \"name\": \"Ainto\"\n}  "

        viewModel.updateClipboardContext(json)

        let result = viewModel.results.first { $0.title == L("search.openJSON") }
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.subtitle, L("search.detectedJSON"))

        result?.action()
        XCTAssertEqual(viewModel.page, .main)
        XCTAssertTrue(viewModel.isJSONFormatterExpanded)
        XCTAssertEqual(viewModel.jsonFormatterInput, json)
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

    func testNonJSONClipboardDoesNotAddContextCommand() {
        let viewModel = SearchViewModel()

        viewModel.updateClipboardContext("ordinary clipboard text")

        XCTAssertFalse(viewModel.results.contains { $0.title == L("search.openJSON") })
    }
}
