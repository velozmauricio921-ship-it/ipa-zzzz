import Darwin
import Foundation

struct IOSVersionDetector: Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let build: String

    init(major: Int, minor: Int, patch: Int, build: String) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var current: IOSVersionDetector {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return IOSVersionDetector(
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion,
            build: currentBuild
        )
    }

    private static var currentBuild: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }

        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: value)
    }
}