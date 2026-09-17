import XCTest
@testable import AintoApp

@MainActor
final class SearchResultIdentityTests: XCTestCase {
    func testRebuiltResultsForTheSameApplicationKeepTheSameStableIdentity() {
        let first = SearchResult(
            title: "Google Chrome",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill"
        ) {}
        let rebuilt = SearchResult(
            title: "Google Chrome",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill"
        ) {}

        XCTAssertEqual(first.stableID, rebuilt.stableID)
    }

    func testResultsWithDifferentKindsKeepDistinctStableIdentities() {
        let application = SearchResult(title: "Open", subtitle: L("search.application"), icon: nil, systemIcon: "app.fill") {}
        let command = SearchResult(title: "Open", subtitle: L("search.command"), icon: nil, systemIcon: "command") {}

        XCTAssertNotEqual(application.stableID, command.stableID)
    }

    func testApplicationsWithTheSameDisplayNameUseTheirPathsAsDistinctStableIdentities() {
        let first = SearchResult(
            title: "Google Chrome",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill",
            stableIdentity: "/Applications/Google Chrome.app"
        ) {}
        let second = SearchResult(
            title: "Google Chrome",
            subtitle: L("search.application"),
            icon: nil,
            systemIcon: "app.fill",
            stableIdentity: "/Applications/Google Chrome Beta.app"
        ) {}

        XCTAssertNotEqual(first.stableID, second.stableID)
    }
}
