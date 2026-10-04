import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemController: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
