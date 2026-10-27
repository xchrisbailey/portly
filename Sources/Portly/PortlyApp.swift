import SwiftUI
import PortlyCore

@main
struct PortlyApp: App {
    var body: some Scene {
        MenuBarExtra("Portly", systemImage: "network") {
            PanelView(model: PanelModel())
        }
        .menuBarExtraStyle(.window)
    }
}
