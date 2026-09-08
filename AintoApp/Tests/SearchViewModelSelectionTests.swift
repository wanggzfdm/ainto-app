import XCTest
@testable import AintoApp

@MainActor
final class SearchViewModelSelectionTests: XCTestCase {
    func testSelectAllKeepsReadyApplicationResultsVisible() {
        let viewModel = SearchViewModel()
        let app = SearchResult(
            title: "Calculator",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill"
        ) {}
        viewModel.results = [app]
        viewModel.allApplications = [app]
        viewModel.isApplicationIndexReady = true

        viewModel.selectAll()

        XCTAssertTrue(viewModel.isApplicationIndexReady)
        XCTAssertEqual(viewModel.displayedApplicationResults.map(\.title), ["Calculator"])
        XCTAssertTrue(viewModel.shouldSelectAll)
    }

    func testApplyingApplicationRefreshPopulatesDefaultGrid() {
        let viewModel = SearchViewModel()
        let app = SearchResult(
            title: "Calculator",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill"
        ) {}

        viewModel.applyApplicationRefresh(allApplications: [app], recentApplications: [app])

        XCTAssertTrue(viewModel.isApplicationIndexReady)
        XCTAssertEqual(viewModel.allApplications.map(\.title), ["Calculator"])
        XCTAssertEqual(viewModel.displayedApplicationResults.map(\.title), ["Calculator"])
    }
}
