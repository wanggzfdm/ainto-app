import Testing
@testable import AintoApp

@Test func mainApplicationGridUsesSevenColumns() {
    #expect(MainSearchGridMetrics.columnCount == 7)
}

@Test func collapsedApplicationGridShowsAtMostTwoRows() {
    let apps = Array(0..<25)

    let visible = ApplicationGridPresentation.visibleItems(
        from: apps,
        isExpanded: false,
        columnCount: 7
    )

    #expect(visible == Array(0..<14))
}

@Test func expandedApplicationGridShowsEveryApplication() {
    let apps = Array(0..<25)

    let visible = ApplicationGridPresentation.visibleItems(
        from: apps,
        isExpanded: true,
        columnCount: 9
    )

    #expect(visible == apps)
}

@Test func invalidColumnCountProducesAnEmptyCollapsedGrid() {
    #expect(ApplicationGridPresentation.visibleItems(from: [1, 2], isExpanded: false, columnCount: 0).isEmpty)
}

@Test func collapsedGridBackfillsMissingRecentItemsFromAllApplications() {
    let visible = ApplicationGridPresentation.collapsedItems(
        recent: ["Safari", "Terminal"],
        all: ["Arc", "Finder", "Safari", "Terminal", "Xcode"],
        maximumCount: 4,
        id: { $0 }
    )

    #expect(visible == ["Safari", "Terminal", "Arc", "Finder"])
}

@Test func collapsedGridDoesNotDuplicateRecentApplications() {
    let visible = ApplicationGridPresentation.collapsedItems(
        recent: ["Safari"],
        all: ["Safari", "Xcode"],
        maximumCount: 4,
        id: { $0 }
    )

    #expect(visible == ["Safari", "Xcode"])
}
