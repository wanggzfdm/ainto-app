import CoreGraphics

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
        itemCount: Int
    ) -> MainPanelContentState {
        if isJSONFormatterExpanded { return .jsonFormatter }
        if !queryIsEmpty { return .searchResults }
        if itemCount == 0 { return .searchOnly }
        return .collapsedApplications
    }
    static let shouldUseNativeWindowShadow = true

    static func shouldAnimateResize(for state: MainPanelContentState) -> Bool {
        state != .jsonFormatter
    }

    static func size(for state: MainPanelContentState, itemCount: Int? = nil) -> CGSize {
        switch state {
        case .searchOnly, .searchResults, .collapsedApplications:
            return CGSize(width: 800, height: 240)
        case .expandedApplications:
            return CGSize(width: 800, height: 520)
        case .jsonFormatter:
            return CGSize(width: 800, height: 590)
        }
    }
}
