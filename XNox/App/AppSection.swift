import Foundation

enum AppSection: String, CaseIterable, Hashable {
    case dashboard
    case simulator
    case storage
    case history
    case settings

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .simulator:
            return "Simulator"
        case .storage:
            return "Storage"
        case .history:
            return "History"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "rectangle.3.group.bubble.left"
        case .simulator:
            return "iphone.gen3"
        case .storage:
            return "externaldrive"
        case .history:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .settings:
            return "gearshape"
        }
    }
}
