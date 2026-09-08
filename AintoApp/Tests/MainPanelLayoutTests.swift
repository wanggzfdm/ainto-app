import Testing
@testable import AintoApp

@Test func collapsedApplicationPanelUsesSingleRowHeightForSevenOrFewerItems() {
    let size = MainPanelLayout.size(for: .collapsedApplications, itemCount: 7)

    #expect(size.width == 800)
    #expect(size.height == 170)
}

@Test func collapsedApplicationPanelUsesTwoRowsForEightToFourteenItems() {
    let size = MainPanelLayout.size(for: .collapsedApplications, itemCount: 14)

    #expect(size.width == 800)
    #expect(size.height == 240)
}

@Test func searchResultsOverFourteenUseTwoRowViewport() {
    let size = MainPanelLayout.size(for: .searchResults, itemCount: 20)

    #expect(size.width == 800)
    #expect(size.height == 240)
}

@Test func expandedApplicationPanelUsesFullGridWidthAndExpandedHeight() {
    let size = MainPanelLayout.size(for: .expandedApplications)

    #expect(size.width == 800)
    #expect(size.height == 520)
}

@Test func searchOnlyPanelRemainsCompact() {
    let size = MainPanelLayout.size(for: .searchOnly)

    #expect(size.width == 800)
    #expect(size.height == 92)
}
