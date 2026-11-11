import Foundation

enum WQIntegrationComponent: String, CaseIterable, Identifiable {
    case access = "WQAccess"
    case launchServices = "WQLaunchServices"

    var id: String { rawValue }
}

enum WQIntegrationState: Equatable {
    case componentAbsent
    case dependenciesIncomplete([String])
    case initializationFailed(String)
    case permissionNotGranted
    case functionalityUnavailable(String)
    case preparedAndVerified
}

struct WQIntegrationStatus: Equatable, Identifiable {
    let component: WQIntegrationComponent
    let state: WQIntegrationState

    var id: WQIntegrationComponent { component }

    var isPreparedAndVerified: Bool {
        state == .preparedAndVerified
    }

    var diagnosticText: String {
        switch state {
        case .componentAbsent:
            return "\(component.rawValue): source is not linked into this target."
        case .dependenciesIncomplete(let dependencies):
            return "\(component.rawValue): missing dependencies: \(dependencies.joined(separator: ", "))."
        case .initializationFailed(let detail):
            return "\(component.rawValue): initialization failed: \(detail)"
        case .permissionNotGranted:
            return "\(component.rawValue): required permission has not been granted."
        case .functionalityUnavailable(let detail):
            return "\(component.rawValue): functionality unavailable: \(detail)"
        case .preparedAndVerified:
            return "\(component.rawValue): prepared and verified."
        }
    }

    static func assess(
        component: WQIntegrationComponent,
        componentLinked: Bool,
        missingDependencies: [String] = [],
        initializationError: String? = nil,
        permissionGranted: Bool? = nil,
        capabilityVerified: Bool = false,
        functionalityEnabled: Bool = false
    ) -> WQIntegrationStatus {
        let state: WQIntegrationState
        if !componentLinked {
            state = .componentAbsent
        } else if !missingDependencies.isEmpty {
            state = .dependenciesIncomplete(missingDependencies)
        } else if let initializationError {
            state = .initializationFailed(initializationError)
        } else if permissionGranted == false {
            state = .permissionNotGranted
        } else if !functionalityEnabled {
            state = .functionalityUnavailable("private or privileged WQ functionality is disabled")
        } else if permissionGranted == nil {
            state = .functionalityUnavailable("permission state has not been checked")
        } else if !capabilityVerified {
            state = .functionalityUnavailable("no capability verification has been performed")
        } else {
            state = .preparedAndVerified
        }
        return WQIntegrationStatus(component: component, state: state)
    }
}