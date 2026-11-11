import Foundation

enum WQIntegrationDiagnostics {
    static func emit(_ statuses: [WQIntegrationStatus] = WQIntegrationManager().currentStatuses) {
        for status in statuses {
            log("wq-integration: \(status.diagnosticText)")
        }
    }
}