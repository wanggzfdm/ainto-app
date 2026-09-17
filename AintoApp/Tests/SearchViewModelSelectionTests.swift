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

    func testValidDirectoryQueryProducesFinderResultFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = SearchViewModel()
        viewModel.updateQuery(directory.path)

        XCTAssertEqual(viewModel.results.first?.subtitle, "在访达中打开")
        XCTAssertEqual(viewModel.results.first?.title, directory.lastPathComponent)
        XCTAssertEqual(viewModel.selectedIndex, 0)
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
