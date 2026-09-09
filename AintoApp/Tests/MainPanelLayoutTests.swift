import Testing
@testable import AintoApp

@Test(arguments: [0, 1, 7, 8, 20])
func collapsedApplicationPanelKeepsStableTwoRowHeight(itemCount: Int) {
    let size = MainPanelLayout.size(for: .collapsedApplications, itemCount: itemCount)

    #expect(size.width == 800)
    #expect(size.height == 240)
}

@Test(arguments: [0, 1, 7, 8, 20])
func searchResultsKeepStableTwoRowHeight(itemCount: Int) {
    let size = MainPanelLayout.size(for: .searchResults, itemCount: itemCount)

    #expect(size.width == 800)
    #expect(size.height == 240)
}

@Test func searchOnlyPanelKeepsTheResultsAreaReserved() {
    let size = MainPanelLayout.size(for: .searchOnly)

    #expect(size.width == 800)
    #expect(size.height == 240)
}

@Test func noMatchQueryUsesSearchResultsLayout() {
    #expect(
        MainPanelLayout.contentState(
            isJSONFormatterExpanded: false,
            queryIsEmpty: false,
            itemCount: 0
        ) == .searchResults
    )
}

@Test func emptyQueryWithoutItemsUsesSearchOnlyLayout() {
    #expect(
        MainPanelLayout.contentState(
            isJSONFormatterExpanded: false,
            queryIsEmpty: true,
            itemCount: 0
        ) == .searchOnly
    )
}

@Test func expandedApplicationPanelUsesFullGridWidthAndExpandedHeight() {
    let size = MainPanelLayout.size(for: .expandedApplications)

    #expect(size.width == 800)
    #expect(size.height == 520)
}
