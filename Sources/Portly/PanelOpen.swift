import AppKit
import SwiftUI

extension View {
    /// Runs `action` each time the panel window becomes key. The window style keeps its content
    /// alive between openings, so view appearance alone doesn't signal a reopen.
    func onPanelOpen(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in action() }
    }
}
