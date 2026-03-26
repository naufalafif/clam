import Foundation
import ServiceManagement

// MARK: - Launch at login via SMAppService (macOS 13+)

@MainActor
class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool = false

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    func enable() {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
        } catch {
            isEnabled = false
        }
    }

    func disable() {
        do {
            try SMAppService.mainApp.unregister()
            isEnabled = false
        } catch {
            // status may already be disabled
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
