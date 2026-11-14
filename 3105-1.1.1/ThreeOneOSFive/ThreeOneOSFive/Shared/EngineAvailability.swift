import Foundation

enum EngineAvailability: Equatable {
    case available
    case notImplemented(pendingDependencies: [String])
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}