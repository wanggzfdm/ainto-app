import CoreGraphics

enum MainPanelContentState {
    case searchOnly
    case searchResults
    case collapsedApplications
    case expandedApplications
    case jsonFormatter
}

enum MainPanelLayout {
    static func size(for state: MainPanelContentState, itemCount: Int? = nil) -> CGSize {
        if let itemCount, state == .collapsedApplications {
            return CGSize(width: 800, height: itemCount <= 7 ? 170 : 240)
        }
        if let itemCount, state == .searchResults {
            return CGSize(width: 800, height: itemCount <= 7 ? 170 : 240)
        }
        switch state {
        case .searchOnly, .searchResults:
            return CGSize(width: 800, height: 92)
        case .collapsedApplications:
            return CGSize(width: 800, height: 240)
        case .expandedApplications:
            return CGSize(width: 800, height: 520)
        case .jsonFormatter:
            return CGSize(width: 800, height: 590)
        }
    }
}
