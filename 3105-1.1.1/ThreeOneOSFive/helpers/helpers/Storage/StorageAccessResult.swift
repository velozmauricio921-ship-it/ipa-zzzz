import Foundation

enum StorageAccessIssue: Error, Equatable, LocalizedError {
    case accessDenied
    case locationUnavailable
    case legacyContainerUnavailable
    case unsafePath
    case publicAppCatalogUnavailable
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to this location was denied."
        case .locationUnavailable:
            return "This location is no longer available."
        case .legacyContainerUnavailable:
            return "Legacy application-container browsing is disabled. Choose an app-owned or user-authorized location."
        case .unsafePath:
            return "The requested path is outside the authorized folder or contains a symbolic link."
        case .publicAppCatalogUnavailable:
            return "iOS does not provide a public API to enumerate all installed applications and their private containers."
        case .readFailed(let detail):
            return detail
        }
    }
}

enum StorageAccessResult<Value> {
    case success(Value)
    case failure(StorageAccessIssue)
}