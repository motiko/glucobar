import os
import ServiceManagement

enum LaunchAtLogin {
    /// Registers or unregisters GlucoBar as a login item. Skipped in Debug builds so
    /// Xcode's DerivedData copy never becomes a login item.
    static func apply(_ enabled: Bool) {
        #if !DEBUG
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            Logger(subsystem: "dev.moti.glucobar", category: "login").error("Launch at login: \(error.localizedDescription)")
        }
        #endif
    }
}
