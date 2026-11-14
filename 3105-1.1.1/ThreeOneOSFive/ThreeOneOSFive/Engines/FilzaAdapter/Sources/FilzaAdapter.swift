import Foundation

struct FilzaAdapter: FileDiscoveryEngine {
    static let identifier = "filzaAdapter"

    let providerID: FileDiscoveryProviderID = .future(identifier)
    let capabilities = EngineCapabilities.none

    var initializationAvailability: EngineAvailability {
        .notImplemented(pendingDependencies: Self.pendingDependencies)
    }

    static let pendingDependencies = [
        "A permission-based, standalone discovery implementation",
        "A component-level provenance and license review",
        "An API contract independent of the Filza host process",
        "Build and authorized-device tests for each approved component"
    ]

    func canHandle(_ source: FileDiscoverySource) -> Bool {
        guard case .futureProvider(let identifier) = source else { return false }
        return identifier == Self.identifier
    }

    func availability(for source: FileDiscoverySource) -> FileDiscoveryAvailability {
        canHandle(source) ? .notImplemented : .unavailable
    }

    func discover(from source: FileDiscoverySource) -> DiscoveryResult {
        DiscoveryResult(
            selectedProvider: providerID,
            source: source,
            availability: .notImplemented,
            status: .notImplemented,
            permissionState: .notRequired
        )
    }
}