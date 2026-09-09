import XCTest
@testable import AintoApp

final class FilterResultsLayoutTests: XCTestCase {
    func testSnippetResultsKeepTheListHeightWhenFilterHasNoMatches() {
        XCTAssertEqual(FilterResultsLayout.snippetContentHeight, FilterResultsLayout.listContentHeight)
    }

    func testAICommandResultsKeepTheListHeightWhenFilterHasNoMatches() {
        XCTAssertEqual(FilterResultsLayout.aiCommandContentHeight, FilterResultsLayout.listContentHeight)
    }
}
