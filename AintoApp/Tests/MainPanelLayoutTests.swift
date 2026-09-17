import CoreGraphics
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
    #expect(size.height == 506)
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

@Test func emptyQueryWithExpandedGridUsesExpandedApplicationLayout() {
    #expect(
        MainPanelLayout.contentState(
            isJSONFormatterExpanded: false,
            queryIsEmpty: true,
            itemCount: 20,
            isApplicationGridExpanded: true
        ) == .expandedApplications
    )
}

@Test func emptyQueryWithCollapsedGridUsesCollapsedApplicationLayout() {
    #expect(
        MainPanelLayout.contentState(
            isJSONFormatterExpanded: false,
            queryIsEmpty: true,
            itemCount: 20,
            isApplicationGridExpanded: false
        ) == .collapsedApplications
    )
}

@Test func mainPanelElevationUsesLargerAndLowerFarShadow() {
    #expect(GlassElevationStyle.mainPanel.farShadow.radius > GlassElevationStyle.mainPanel.nearShadow.radius)
    #expect(GlassElevationStyle.mainPanel.farShadow.y > GlassElevationStyle.mainPanel.nearShadow.y)
}

@Test func elevationShadowUsesNonBlackCoolGrayColor() {
    let color = GlassElevationStyle.coolGrayShadow

    #expect(color.red > 0)
    #expect(color.green > 0)
    #expect(color.blue > 0)
    #expect(color.blue > color.red)
    #expect(color.blue > color.green)
}

@Test func mainPanelUsesNativeWindowShadow() {
    #expect(MainPanelLayout.shouldUseNativeWindowShadow)
}

@Test func cardElevationIsMoreSubtleThanMainPanelElevation() {
    #expect(GlassElevationStyle.card.farShadow.radius < GlassElevationStyle.mainPanel.farShadow.radius)
    #expect(GlassElevationStyle.card.farShadow.opacity < GlassElevationStyle.mainPanel.farShadow.opacity)
    #expect(GlassElevationStyle.card.highlightOpacity > 0)
}

@Test func tunedElevationKeepsCardsSubtleButClearlyVisible() {
    #expect(GlassElevationStyle.mainPanel.nearShadow.opacity >= 0.22)
    #expect(GlassElevationStyle.mainPanel.farShadow.opacity >= 0.28)
    #expect(GlassElevationStyle.mainPanel.farShadow.radius >= 44)
    #expect(GlassElevationStyle.mainPanel.farShadow.y >= 22)
    #expect(GlassElevationStyle.card.farShadow.opacity >= 0.14)
    #expect(GlassElevationStyle.card.farShadow.opacity < GlassElevationStyle.mainPanel.farShadow.opacity)
    #expect(GlassElevationStyle.card.farShadow.radius < GlassElevationStyle.mainPanel.farShadow.radius)
    #expect(GlassElevationStyle.card.farShadow.y < GlassElevationStyle.mainPanel.farShadow.y)
}

@Test func cardElevationIncludesTwoShadowsAndHighlight() {
    #expect(GlassElevationStyle.card.nearShadow.opacity > 0)
    #expect(GlassElevationStyle.card.farShadow.opacity > 0)
    #expect(GlassElevationStyle.card.highlightOpacity > 0)
    #expect(MainPanelLayout.shouldAnimateResize(for: .jsonFormatter) == false)
}

@Test func applicationGridAnimatesItsPanelFrameFromTheFixedTopEdge() {
    #expect(MainPanelLayout.shouldAnimatePanelFrame(for: .collapsedApplications))
    #expect(MainPanelLayout.shouldAnimatePanelFrame(for: .expandedApplications))
    #expect(MainPanelLayout.shouldAnimatePanelFrame(for: .searchResults))
}

@Test func resizingPanelKeepsItsTopEdgeFixed() {
    let current = CGRect(x: 240, y: 400, width: 800, height: 240)
    let resized = MainPanelLayout.frame(
        keepingTopEdgeOf: current,
        width: 800,
        height: 520
    )

    #expect(resized.maxY == current.maxY)
    #expect(resized.minY == 120)
    #expect(resized.height == 520)
}

@Test func panelContentUsesTopAlignmentForSearchFieldAnchoring() {
    #expect(MainPanelLayout.contentAlignment == .top)
}

@Test func JSONFormatterWorkspaceUsesTheSameLayoutInInlineAndDetachedModes() {
    #expect(JSONFormatterWorkspaceStyle.usesBottomActionBar)
}

@Test func detachedJSONFormatterUsesNativeResizableWindowStyle() {
    #expect(JSONFormatterWindowStyle.styleMask.contains(.titled))
    #expect(JSONFormatterWindowStyle.styleMask.contains(.closable))
    #expect(JSONFormatterWindowStyle.styleMask.contains(.miniaturizable))
    #expect(JSONFormatterWindowStyle.styleMask.contains(.resizable))
    #expect(JSONFormatterWindowStyle.styleMask == [.titled, .closable, .miniaturizable, .resizable])
    #expect(JSONFormatterWindowStyle.usesNativeWindowShadow)
}

@Test func JSONFormatterPanelResizeDoesNotAnimate() {
    #expect(MainPanelLayout.shouldAnimateResize(for: .jsonFormatter) == false)
}

@Test func expandedApplicationPanelUsesFullGridWidthAndExpandedHeight() {
    let size = MainPanelLayout.size(for: .expandedApplications)

    #expect(size.width == 800)
    #expect(size.height == 520)
}
