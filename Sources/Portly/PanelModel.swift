import Foundation
import Observation
import PortlyCore

@MainActor
@Observable
final class PanelModel {
    private(set) var rows: [Row] = []
    var showAll = false {
        didSet { if showAll != oldValue { Task { await refresh() } } }
    }
    private(set) var errorMessage: String?
    /// PIDs with a Kill in flight (the row shows a spinner).
    private(set) var killing: Set<Int32> = []
    /// Inline per-row failure text, keyed by PID.
    private(set) var rowErrors: [Int32: String] = [:]

    private let portly = Portly(processSource: SystemProcessSource(), signaller: SystemSignaller())

    /// Runs a fresh Scan off the main thread. Called every time the panel opens.
    func refresh() async {
        let portly = portly
        let showAll = showAll
        do {
            rows = try await Task.detached { try portly.scan(showAll: showAll) }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Kills a row's Dev Server, then rescans. A failed Kill stays on the row as inline text.
    func kill(_ row: Row) async {
        guard !killing.contains(row.pid) else { return }
        killing.insert(row.pid)
        rowErrors[row.pid] = nil
        let portly = portly
        let outcome = await portly.kill(row)
        killing.remove(row.pid)
        rowErrors[row.pid] = RowFormat.failureText(outcome)
        await refresh()
    }
}
