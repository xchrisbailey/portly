import AppKit
import SwiftUI
import PortlyCore

@main
struct PortlyApp: App {
    private let menuBarIcon: NSImage = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing menu bar icon")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: PanelModel())
        } label: {
            Image(nsImage: menuBarIcon)
                .accessibilityLabel("Portly")
        }
        .menuBarExtraStyle(.window)
    }
}
