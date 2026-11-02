import Foundation

enum AppSection: String, CaseIterable, Hashable {
    case dashboard
    case xcodes
    case simulator
    case storage
    case signing
    case devices
    case history
    case settings

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .xcodes:
            return "Xcodes"
        case .simulator:
            return "Simulator"
        case .storage:
            return "Storage"
        case .signing:
            return "Signing"
        case .devices:
            return "Devices"
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
        case .xcodes:
            return "hammer"
        case .simulator:
            return "iphone.gen3"
        case .storage:
            return "externaldrive"
        case .signing:
            return "checkmark.shield"
        case .devices:
            return "iphone"
        case .history:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .settings:
            return "gearshape"
        }
    }
}
