import Foundation

struct FileDiscoveryRouter {
    private let engines: [FileDiscoveryEngine]

    init(engines: [FileDiscoveryEngine] = [
        AppSandboxFileDiscoveryEngine(),
        UserSelectedFileDiscoveryEngine()
    ]) {
        self.engines = engines
    }

    func discover(from source: FileDiscoverySource) -> DiscoveryResult {
        guard let engine = engines.first(where: { $0.canHandle(source) }) else {
            let provider: FileDiscoveryProviderID?
            if case .futureProvider(let identifier) = source {
                provider = .future(identifier)
            } else {
                provider = nil
            }
            return DiscoveryResult(
                selectedProvider: provider,
                source: source,
                availability: .notImplemented,
                status: .notImplemented,
                permissionState: .notRequired
            )
        }

        let availability = engine.availability(for: source)
        guard availability == .available else {
            return DiscoveryResult(
                selectedProvider: engine.providerID,
                source: source,
                availability: availability,
                status: .sourceUnavailable,
                permissionState: .notRequired,
                error: .sourceUnavailable
            )
        }

        return engine.discover(from: source)
    }
}