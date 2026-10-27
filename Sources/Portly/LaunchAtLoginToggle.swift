import ServiceManagement
import SwiftUI

/// Toggle backed directly by the system login-item service; Portly stores no setting of its own.
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Portly: login item change failed: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Re-read when the panel reopens; the user may have changed it in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            enabled = SMAppService.mainApp.status == .enabled
        }
    }
}
