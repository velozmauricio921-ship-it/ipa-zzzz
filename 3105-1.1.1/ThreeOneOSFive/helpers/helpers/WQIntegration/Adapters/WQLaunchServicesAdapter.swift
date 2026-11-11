import Foundation

struct WQLaunchServicesAdapter {
    static let requiredSourceFiles = [
        "WQLaunchServices.h",
        "WQLaunchServices.m",
        "WQAccess.h",
        "WQAccess.m",
        "WQAccessSafety.h",
        "WQCore.h",
        "WQCore.m",
        "WQLocalization.h",
        "WQLocalization.m"
    ]

    var currentStatus: WQIntegrationStatus {
    #if WQ_LAUNCH_SERVICES_COMPONENT_LINKED
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
            component: .launchServices,
            componentLinked: componentLinked,
            missingDependencies: missingDependencies,
            initializationError: initializationError,
            permissionGranted: permissionGranted,
            capabilityVerified: capabilityVerified,
            functionalityEnabled: false
        )
    }
}