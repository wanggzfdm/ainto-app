import CoreGraphics
import SwiftUI

enum MainPanelContentState {
    case inputOnly
    case searchOnly
    case searchResults
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
        isApplicationGridExpanded: Bool = false
    ) -> MainPanelContentState {
        if isJSONFormatterExpanded { return .jsonFormatter }
        if !queryIsEmpty { return .searchResults }
        if queryIsEmpty && !hasClipboardJSON && !hasClipboardText { return .inputOnly }
        if queryIsEmpty && hasClipboardText { return .searchResults }
        if itemCount == 0 { return .searchOnly }
        return isApplicationGridExpanded ? .expandedApplications : .collapsedApplications
    }
    static let shouldUseNativeWindowShadow = true
    static let contentAlignment: Alignment = .top
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

    static func size(for state: MainPanelContentState, itemCount: Int? = nil) -> CGSize {
        switch state {
        case .inputOnly:
            return CGSize(width: 800, height: 58)
        case .searchOnly, .collapsedApplications:
            return CGSize(width: 800, height: 600)
        case .searchResults:
            return CGSize(width: 800, height: 600)
        case .expandedApplications:
            return CGSize(width: 800, height: 600)
        case .jsonFormatter:
            return CGSize(width: 800, height: 600)
        }
    }
}
