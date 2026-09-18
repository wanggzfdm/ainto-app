import CoreGraphics
import Testing
@testable import AintoApp

@Test(arguments: [0, 1, 7, 8, 20])
func collapsedApplicationPanelKeepsStableTwoRowHeight(itemCount: Int) {
    let size = MainPanelLayout.size(for: .collapsedApplications, itemCount: itemCount)

    #expect(size.width == 800)
    #expect(size.height == 600)
}

@Test(arguments: [0, 1, 7, 8, 20])
func searchResultsKeepStableTwoRowHeight(itemCount: Int) {
    let size = MainPanelLayout.size(for: .searchResults, itemCount: itemCount)

    #expect(size.width == 800)
    #expect(size.height == 600)
}

@Test func searchOnlyPanelKeepsTheResultsAreaReserved() {
    let size = MainPanelLayout.size(for: .searchOnly)

    #expect(size.width == 800)
    #expect(size.height == 600)
}

@Test func emptyQueryWithoutClipboardJSONUsesInputOnlyLayout() {
    let state = MainPanelLayout.contentState(
        isJSONFormatterExpanded: false,
        queryIsEmpty: true,
        hasClipboardJSON: false,
        itemCount: 8
    )

    #expect(state == .inputOnly)
    #expect(MainPanelLayout.size(for: state) == CGSize(width: 800, height: 58))
}

@Test func emptyQueryWithClipboardTextUsesExpandedSearchResultsLayout() {
    let state = MainPanelLayout.contentState(
        isJSONFormatterExpanded: false,
        queryIsEmpty: true,
        hasClipboardJSON: false,
        hasClipboardText: true,
        itemCount: 1
    )

    #expect(state == .searchResults)
    #expect(MainPanelLayout.size(for: state) == CGSize(width: 800, height: 600))
}

@Test func emptyQueryWithClipboardJSONKeepsExpandedMainPanel() {
    let state = MainPanelLayout.contentState(
        isJSONFormatterExpanded: false,
        queryIsEmpty: true,
        hasClipboardJSON: true,
        itemCount: 8
    )

    #expect(state == .collapsedApplications)
    #expect(MainPanelLayout.size(for: state) == CGSize(width: 800, height: 600))
}

@Test func nonEmptyQueryUsesSearchResultsInsteadOfInputOnly() {
    let state = MainPanelLayout.contentState(
        isJSONFormatterExpanded: false,
        queryIsEmpty: false,
        hasClipboardJSON: false,
        itemCount: 0
    )

    #expect(state == .searchResults)
    #expect(MainPanelLayout.size(for: state) == CGSize(width: 800, height: 600))
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
            hasClipboardJSON: true,
            itemCount: 0
        ) == .searchOnly
    )
}

@Test func emptyQueryWithExpandedGridUsesExpandedApplicationLayout() {
    #expect(
        MainPanelLayout.contentState(
            isJSONFormatterExpanded: false,
            queryIsEmpty: true,
            hasClipboardJSON: true,
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
            hasClipboardJSON: true,
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

@Test func inputOnlyFrameUsesUtoolsUpperCenterAnchor() {
    let visibleFrame = CGRect(x: 100, y: 50, width: 1440, height: 860)
    let frame = MainPanelLayout.frame(
        for: .inputOnly,
        in: visibleFrame,
        requestedSize: CGSize(width: 800, height: 58)
    )

    #expect(frame.midX == visibleFrame.midX)
    #expect(abs(frame.midY - (visibleFrame.maxY - visibleFrame.height / 3)) < 0.001)
}

@Test func expandedPanelFrameRemainsFullyCentered() {
    let visibleFrame = CGRect(x: 0, y: 24, width: 1440, height: 876)
    let frame = MainPanelLayout.frame(
        for: .searchResults,
        in: visibleFrame,
        requestedSize: CGSize(width: 800, height: 600)
    )

    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.midY == visibleFrame.midY)
}

@Test func inputOnlyFrameClampsUpperAnchorInsideMargins() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 500, height: 70)
    let frame = MainPanelLayout.frame(
        for: .inputOnly,
        in: visibleFrame,
        requestedSize: CGSize(width: 800, height: 58)
    )

    #expect(frame.minY >= visibleFrame.minY + 12)
    #expect(frame.maxY <= visibleFrame.maxY - 12)
}

@Test func expandedPanelClampsInsideTwelvePointMarginsOnSmallScreens() {
    let visibleFrame = CGRect(x: 0, y: 24, width: 500, height: 400)
    let frame = MainPanelLayout.frame(
        for: .searchResults,
        in: visibleFrame,
        requestedSize: CGSize(width: 800, height: 600)
    )

    #expect(frame.size == CGSize(width: 476, height: 376))
    #expect(frame.minX == visibleFrame.minX + 12)
    #expect(frame.minY == visibleFrame.minY + 12)
    #expect(frame.maxY == visibleFrame.maxY - 12)
}

@Test func panelFrameCentersRequestedSizeInVisibleFrame() {
    let visibleFrame = CGRect(x: 100, y: 50, width: 1440, height: 860)
    let frame = MainPanelLayout.centeredFrame(
        in: visibleFrame,
        requestedSize: CGSize(width: 800, height: 240)
    )

    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.midY == visibleFrame.midY)
    #expect(frame.size == CGSize(width: 800, height: 240))
}

@Test func panelFrameStaysCenteredWhenContentHeightChanges() {
    let visibleFrame = CGRect(x: 0, y: 24, width: 1440, height: 876)
    let shortFrame = MainPanelLayout.centeredFrame(in: visibleFrame, requestedSize: CGSize(width: 800, height: 240))
    let tallFrame = MainPanelLayout.centeredFrame(in: visibleFrame, requestedSize: CGSize(width: 800, height: 520))

    #expect(shortFrame.midX == visibleFrame.midX)
    #expect(shortFrame.midY == visibleFrame.midY)
    #expect(tallFrame.midX == visibleFrame.midX)
    #expect(tallFrame.midY == visibleFrame.midY)
}

@Test func panelFrameClampsOversizedDimensionsInsideTwelvePointMargins() {
    let visibleFrame = CGRect(x: 0, y: 24, width: 500, height: 400)
    let frame = MainPanelLayout.centeredFrame(in: visibleFrame, requestedSize: CGSize(width: 800, height: 590))

    #expect(frame.size == CGSize(width: 476, height: 376))
    #expect(frame.minX == visibleFrame.minX + 12)
    #expect(frame.minY == visibleFrame.minY + 12)
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
@Test func jsonFormatterPanelUsesTheSameFixedHeightAsOtherMainPanelStates() {
    #expect(MainPanelLayout.size(for: .jsonFormatter).height == 600)
}

@Test func expandedApplicationPanelUsesFullGridWidthAndExpandedHeight() {
    let size = MainPanelLayout.size(for: .expandedApplications)

    #expect(size.width == 800)
    #expect(size.height == 600)
}
