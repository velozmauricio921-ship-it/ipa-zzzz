import Foundation

enum DiscoverySourceCapability: String, CaseIterable, Hashable {
    case appSandbox
    case userSelectedFiles
}

struct EngineCapabilities: Equatable {
    let supportedSources: Set<DiscoverySourceCapability>

    static let none = EngineCapabilities(supportedSources: [])
}