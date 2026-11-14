import Foundation

enum IOSCompatibilityPolicy {
    enum Result: Equatable {
        case verifiedOfficial
        case verifiedBeta(betaNumber: Int, publicBetaNumber: Int?)
        case unverified

        var isVerifiedFor3105App: Bool {
            switch self {
            case .verifiedOfficial, .verifiedBeta:
                return true
            case .unverified:
                return false
            }
        }
    }

    private struct Version: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }

    static func classify(_ detected: IOSVersionDetector) -> Result {
        guard detected.major >= 0, detected.minor >= 0, detected.patch >= 0 else {
            return .unverified
        }

        let version = Version(
            major: detected.major,
            minor: detected.minor,
            patch: detected.patch
        )

        if isWithin(version, from: Version(major: 17, minor: 0, patch: 0),
                    through: Version(major: 17, minor: 7, patch: Int.max)) ||
            isWithin(version, from: Version(major: 18, minor: 0, patch: 0),
                     through: Version(major: 18, minor: 7, patch: 1)) ||
            isWithin(version, from: Version(major: 26, minor: 0, patch: 0),
                     through: Version(major: 26, minor: 6, patch: 2)) {
            return .verifiedOfficial
        }

        guard detected.major == 27, detected.minor == 0, detected.patch == 0 else {
            return .unverified
        }

        switch detected.build {
        case "24A5355q":
            return .verifiedBeta(betaNumber: 1, publicBetaNumber: nil)
        case "24A5370h":
            return .verifiedBeta(betaNumber: 2, publicBetaNumber: nil)
        case "24A5380h":
            return .verifiedBeta(betaNumber: 3, publicBetaNumber: 1)
        case "24A5390f":
            return .verifiedBeta(betaNumber: 4, publicBetaNumber: 2)
        default:
            return .unverified
        }
    }

    private static func isWithin(_ version: Version, from lowerBound: Version, through upperBound: Version) -> Bool {
        version >= lowerBound && version <= upperBound
    }
}