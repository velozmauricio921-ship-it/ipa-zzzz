import Foundation

enum AppSandboxLocation: String, Equatable {
    case documents
    case library
    case caches
}

enum FileDiscoverySource: Equatable {
    case appSandbox(AppSandboxLocation)
    case userSelected(URL)
    case futureProvider(String)
}

enum FileDiscoveryProviderID: Equatable {
    case appSandbox
    case userSelectedDocuments
    case future(String)
}

enum FileDiscoveryAvailability: Equatable {
    case available
    case unavailable
    case notImplemented
}

enum DiscoveryPermissionState: Equatable {
    case notRequired
    case granted
    case notGranted
}

enum DiscoveryStatus: Equatable {
    case available
    case empty
    case notImplemented
    case permissionNotGranted
    case sourceUnavailable
    case enumerationFailed
}

enum DiscoveryError: Equatable {
    case invalidSource
    case sourceUnavailable
    case permissionDenied
    case unsupportedItem
    case enumerationFailed(String)
}

struct DiscoveredFile: Identifiable, Equatable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let sizeBytes: Int64?

    var id: String { url.standardizedFileURL.path }
}

final class SecurityScopedAccessLease {
    private let url: URL
    private let lock = NSLock()
    private var isActive = true

    init(url: URL) {
        self.url = url
    }

    func release() {
        lock.lock()
        let shouldStopAccessing = isActive
        isActive = false
        lock.unlock()

        if shouldStopAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        release()
    }
}

struct DiscoveryResult {
    let selectedProvider: FileDiscoveryProviderID?
    let source: FileDiscoverySource
    let availability: FileDiscoveryAvailability
    let status: DiscoveryStatus
    let permissionState: DiscoveryPermissionState
    let items: [DiscoveredFile]
    let error: DiscoveryError?
    let accessLease: SecurityScopedAccessLease?

    init(
        selectedProvider: FileDiscoveryProviderID?,
        source: FileDiscoverySource,
        availability: FileDiscoveryAvailability,
        status: DiscoveryStatus,
        permissionState: DiscoveryPermissionState,
        items: [DiscoveredFile] = [],
        error: DiscoveryError? = nil,
        accessLease: SecurityScopedAccessLease? = nil
    ) {
        self.selectedProvider = selectedProvider
        self.source = source
        self.availability = availability
        self.status = status
        self.permissionState = permissionState
        self.items = items
        self.error = error
        self.accessLease = accessLease
    }
}