import CoreGraphics
import SwiftUI

enum MainPanelContentState {
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
        itemCount: Int,
        isApplicationGridExpanded: Bool = false
    ) -> MainPanelContentState {
        if isJSONFormatterExpanded { return .jsonFormatter }
        if !queryIsEmpty { return .searchResults }
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

    static func frame(
        keepingTopEdgeOf currentFrame: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - height,
            width: width,
            height: height
        )
    }

    static func size(for state: MainPanelContentState, itemCount: Int? = nil) -> CGSize {
        switch state {
        case .searchOnly, .collapsedApplications:
            return CGSize(width: 800, height: 240)
        case .searchResults:
            return CGSize(width: 800, height: 506)
        case .expandedApplications:
            return CGSize(width: 800, height: 520)
        case .jsonFormatter:
            return CGSize(width: 800, height: 590)
        }
    }
}
