import Foundation

struct WQAccessAdapter {
    static let requiredSourceFiles = [
        "WQAccess.h",
        "WQAccess.m",
        "WQAccessSafety.h",
        "WQCore.h",
        "WQCore.m",
        "WQLocalization.h",
        "WQLocalization.m",
        "WQLaunchServices.h",
        "WQLaunchServices.m"
    ]

    var currentStatus: WQIntegrationStatus {
    #if WQ_ACCESS_COMPONENT_LINKED
        status(componentLinked: true)
    #else
        status(componentLinked: false)
    #endif
    }

    func status(
        componentLinked: Bool,
        missingDependencies: [String] = [],
        initializationError: String? = nil,
        permissionGranted: Bool? = nil,
        capabilityVerified: Bool = false
    ) -> WQIntegrationStatus {
        WQIntegrationStatus.assess(
            component: .access,
            componentLinked: componentLinked,
            missingDependencies: missingDependencies,
            initializationError: initializationError,
            permissionGranted: permissionGranted,
            capabilityVerified: capabilityVerified,
            functionalityEnabled: false
        )
    }
}