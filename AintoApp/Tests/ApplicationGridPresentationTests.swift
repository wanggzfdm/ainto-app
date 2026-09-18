import Testing
@testable import AintoApp

@Test func applicationGridExpansionUsesLaunchpadStyleTiming() {
    #expect(ApplicationGridPresentation.expansionDuration == 0.25)
    #expect(ApplicationGridPresentation.rowStaggerDelay == 0.035)
    #expect(ApplicationGridPresentation.collapsedItemCount == 14)
}

@Test func twoLayerGridKeepsIndependentColumnAndViewportMetrics() {
    #expect(ApplicationGridPresentation.collapsedColumnCount == 7)
    #expect(ApplicationGridPresentation.collapsedViewportHeight == 154)
    #expect(ApplicationGridPresentation.expandedColumnCount == 5)
    #expect(ApplicationGridPresentation.expandedViewportHeight == 420)
}

@Test func compactSearchResultsShowAtMostTwoRows() {
    let visible = ApplicationGridPresentation.visibleItems(
        from: Array(0..<20),
        isExpanded: false,
        columnCount: MainSearchGridMetrics.columnCount
    )
    #expect(visible == Array(0..<14))
}

@Test func expandedApplicationGridUsesLargerLaunchpadMetrics() {
    #expect(ApplicationGridPresentation.expandedColumnCount == 5)
    #expect(ApplicationGridPresentation.expandedIconSize == 64)
    #expect(ApplicationGridPresentation.expandedItemHeight == 104)
    #expect(ApplicationGridPresentation.expandedGridSpacing == 18)
}

@Test func gridItemEntranceAnimationRunsOnlyWhileExpanding() {
    #expect(ApplicationGridPresentation.shouldAnimateItemEntrance(isApplicationGridExpanded: true))
    #expect(!ApplicationGridPresentation.shouldAnimateItemEntrance(isApplicationGridExpanded: false))
}

@Test func launchpadReplacesCompactGridAtTheSameHeaderAnchoredOrigin() {
    #expect(ApplicationGridPresentation.compactViewportHeight == 154)
    #expect(ApplicationGridPresentation.expandedViewportHeight == 420)
}

@Test func collapsingGridDoesNotAnimateItsItems() {
    #expect(!ApplicationGridPresentation.shouldAnimateGridContent(
        isApplicationGridExpanded: false
    ))
}
@Test func gridItemEntranceAnimationUsesNoVerticalOffset() {
    #expect(ApplicationGridPresentation.itemEntranceVerticalOffset == 0)
}

@Test func applicationGridShowsLoadingStateBeforeInitialIndexIsReady() {
    #expect(ApplicationGridPresentation.shouldShowLoadingState(
        queryIsEmpty: true,
        isApplicationIndexReady: false
    ))
    #expect(!ApplicationGridPresentation.shouldShowLoadingState(
        queryIsEmpty: false,
        isApplicationIndexReady: false
    ))
}

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

@Test func panelPresentationDoesNotWaitForApplicationIndex() {
    #expect(!PanelPresentation.shouldDeferPresentationUntilIndexReady())
}
