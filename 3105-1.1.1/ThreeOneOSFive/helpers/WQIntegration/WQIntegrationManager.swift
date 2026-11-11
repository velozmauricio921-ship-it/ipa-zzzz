import Foundation

struct WQIntegrationManager {
    private let accessAdapter: WQAccessAdapter
    private let launchServicesAdapter: WQLaunchServicesAdapter

    init(
        accessAdapter: WQAccessAdapter = WQAccessAdapter(),
        launchServicesAdapter: WQLaunchServicesAdapter = WQLaunchServicesAdapter()
    ) {
        self.accessAdapter = accessAdapter
        self.launchServicesAdapter = launchServicesAdapter
    }

    var currentStatuses: [WQIntegrationStatus] {
        [accessAdapter.currentStatus, launchServicesAdapter.currentStatus]
    }
}