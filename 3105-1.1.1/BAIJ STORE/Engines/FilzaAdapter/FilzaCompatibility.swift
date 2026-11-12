enum FilzaAdapterAvailability: Equatable {
    case notIntegrated
    case unavailable
    case available
}

struct FilzaCompatibility {
    let availability: FilzaAdapterAvailability
    let supportedIOSVersions: [IOSVersionRange]

    var isAvailable: Bool {
        availability == .available
    }

    func supports(_ version: IOSVersion) -> Bool {
        isAvailable && supportedIOSVersions.contains { $0.contains(version) }
    }

    static let notIntegrated = FilzaCompatibility(
        availability: .notIntegrated,
        supportedIOSVersions: []
    )
}
