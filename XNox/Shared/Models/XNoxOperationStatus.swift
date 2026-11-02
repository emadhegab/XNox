import Foundation

enum XNoxOperationStatus: String, CaseIterable {
    case pending
    case success
    case failed

    var title: String {
        rawValue.capitalized
    }
}
