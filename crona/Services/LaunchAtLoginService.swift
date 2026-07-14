import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published var isEnabled = false
    @Published var lastError: String?

    func refresh() {
        // `SMAppService.mainApp.status` is the supported way to inspect the main app registration.
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
            refresh()
        } catch {
            lastError = error.localizedDescription
            refresh()
        }
    }
}
