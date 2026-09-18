import CoreGraphics
import SwiftUI

enum MainPanelContentState {
    case inputOnly
    case searchOnly
    case searchResults
    case compactSearchResults
    case expandedSearchResults
    case collapsedApplications
    case expandedApplications
    case jsonFormatter
}

enum MainPanelLayout {
    static func contentState(
        isJSONFormatterExpanded: Bool,
        queryIsEmpty: Bool,
        hasClipboardJSON: Bool = false,
        hasClipboardText: Bool = false,
        itemCount: Int,
        isApplicationGridExpanded: Bool = false,
        isSearchResultsExpanded: Bool = false
    ) -> MainPanelContentState {
        if isJSONFormatterExpanded { return .jsonFormatter }
        if !queryIsEmpty {
            return isSearchResultsExpanded ? .expandedSearchResults : .compactSearchResults
        }
        if queryIsEmpty && isApplicationGridExpanded { return .expandedApplications }
        if queryIsEmpty && !hasClipboardJSON && !hasClipboardText { return .inputOnly }
        if queryIsEmpty && hasClipboardText { return .compactSearchResults }
        if queryIsEmpty && hasClipboardJSON { return .compactSearchResults }
        if itemCount == 0 { return .searchOnly }
        return isApplicationGridExpanded ? .expandedApplications : .collapsedApplications
    }
    static let shouldUseNativeWindowShadow = true
    static let contentAlignment: Alignment = .top
    static let searchBarCenterHeightRatio: CGFloat = 1 / 3

    static func shouldAnimateResize(for state: MainPanelContentState) -> Bool {
        state != .jsonFormatter
    }

    static func shouldAnimatePanelFrame(for state: MainPanelContentState) -> Bool {
        true
    }

    static func centeredFrame(in visibleFrame: CGRect, requestedSize: CGSize, margin: CGFloat = 12) -> CGRect {
        let width = min(requestedSize.width, max(0, visibleFrame.width - margin * 2))
        let height = min(requestedSize.height, max(0, visibleFrame.height - margin * 2))
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func frame(
        for state: MainPanelContentState,
        in visibleFrame: CGRect,
        requestedSize: CGSize,
        margin: CGFloat = 12
    ) -> CGRect {
        let centered = centeredFrame(in: visibleFrame, requestedSize: requestedSize, margin: margin)
        guard state == .inputOnly || state == .compactSearchResults else { return centered }
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - margin - centered.height
        let searchBarTop = visibleFrame.maxY - visibleFrame.height * searchBarCenterHeightRatio - 29
        let anchoredY = state == .compactSearchResults
            ? searchBarTop - (centered.height - 58)
            : searchBarTop
        let y = min(max(anchoredY, minY), maxY)
        return CGRect(
            x: centered.minX,
            y: y,
            width: centered.width,
            height: centered.height
        )
    }

    static func size(for state: MainPanelContentState, itemCount: Int? = nil) -> CGSize {
        switch state {
        case .inputOnly:
            return CGSize(width: 800, height: 58)
        case .searchOnly, .collapsedApplications:
            return CGSize(width: 800, height: 600)
        case .searchResults, .expandedSearchResults:
            return CGSize(width: 800, height: 600)
        case .compactSearchResults:
            return CGSize(width: 800, height: 240)
        case .expandedApplications:
            return CGSize(width: 800, height: 600)
        case .jsonFormatter:
            return CGSize(width: 800, height: 600)
        }
    }
}
