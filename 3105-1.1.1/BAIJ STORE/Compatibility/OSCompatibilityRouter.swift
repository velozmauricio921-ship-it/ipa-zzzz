struct IOSVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: IOSVersion, rhs: IOSVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct IOSVersionRange: Equatable {
    let minimum: IOSVersion
    let maximum: IOSVersion

    func contains(_ version: IOSVersion) -> Bool {
        minimum <= version && version <= maximum
    }
}

enum EngineRoute: Equatable {
    case original3105
    case filzaAdapter
    case noCompatibleEngine
}

struct OSCompatibilityRouter {
    let originalEngineSupports: (IOSVersion) -> Bool

    func route(
        for version: IOSVersion,
        filzaAdapter: FilzaEngineAdapter?
    ) -> EngineRoute {
        if originalEngineSupports(version) {
            return .original3105
        }
        guard let filzaAdapter,
              filzaAdapter.isInitialized,
              filzaAdapter.compatibility.supports(version) else {
            return .noCompatibleEngine
        }
        return .filzaAdapter
    }
}
