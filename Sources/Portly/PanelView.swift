import AppKit
import SwiftUI
import PortlyCore

struct PanelView: View {
    @State var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).padding(12)
            } else if model.rows.isEmpty {
                Text("No dev servers running")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ForEach(model.rows) { row in
                    RowView(row: row)
                    Divider()
                }
            }
            LaunchAtLoginToggle()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.plain)
                .padding(12)
        }
        .frame(width: 320)
        .task { await model.refresh() }
        // The window style keeps its content alive between openings, so rescan whenever
        // the panel window becomes key rather than relying on view appearance alone.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}

struct RowView: View {
    let row: Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.ports.map { ":\($0)" }.joined(separator: " "))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(row.command)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("PID \(row.pid)\n\(row.commandLine)")
    }
}
