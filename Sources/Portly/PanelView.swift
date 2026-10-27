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
                Text(model.showAll ? "No listeners running" : "No dev servers running")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ForEach(model.rows) { row in
                    RowView(row: row, isKilling: model.killing.contains(row.pid), error: model.rowErrors[row.pid]) {
                        Task { await model.kill(row) }
                    }
                    Divider()
                }
            }
            Toggle("Show all listeners", isOn: $model.showAll)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
    let isKilling: Bool
    let error: String?
    let onKill: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.ports.map(String.init).joined(separator: ", "))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if row.exposed {
                        Text("Exposed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(RowFormat.subtitle(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = RowFormat.siblingWarning(row) {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                if let reason = RowFormat.killBlockedReason(row) {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if isKilling {
                ProgressView().controlSize(.small)
            } else {
                Button(action: onKill) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .disabled(RowFormat.killBlockedReason(row) != nil)
                    .help(RowFormat.killBlockedReason(row) ?? "Kill")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { openInBrowser() }
        .help("PID \(row.pid)\n\(row.commandLine)")
        .contextMenu {
            Button("Copy URL") { copy(url) }
            Button("Copy PID") { copy(String(row.pid)) }
            Button("Reveal in Finder") {
                if let project = row.project {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.directory))
                }
            }
            .disabled(row.project == nil)
        }
    }

    private var url: String { "http://localhost:\(row.ports[0])" }

    private func openInBrowser() {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
