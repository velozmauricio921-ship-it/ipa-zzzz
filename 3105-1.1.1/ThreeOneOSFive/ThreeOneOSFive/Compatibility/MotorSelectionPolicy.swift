import Foundation

enum DiscoveryMotor: Equatable {
    case original3105
    case filzaAdapter
}

struct MotorSelectionDecision: Equatable {
    let motor: DiscoveryMotor
    let availability: EngineAvailability
    let compatibility: IOSCompatibilityPolicy.Result
}

enum MotorSelectionPolicy {
    static func select(for version: IOSVersionDetector) -> MotorSelectionDecision {
        let compatibility = IOSCompatibilityPolicy.classify(version)

        switch compatibility {
        case .verifiedOfficial, .verifiedBeta:
            return MotorSelectionDecision(
                motor: .original3105,
                availability: .available,
                compatibility: compatibility
            )
        case .unverified:
            return MotorSelectionDecision(
                motor: .filzaAdapter,
                availability: FilzaAdapter().initializationAvailability,
                compatibility: compatibility
            )
        }
    }
}