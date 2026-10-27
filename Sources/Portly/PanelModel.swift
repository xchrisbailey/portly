import Foundation
import Observation
import PortlyCore

@MainActor
@Observable
final class PanelModel {
    private(set) var rows: [Row] = []
    var showAll = false {
        didSet { if showAll != oldValue { refresh() } }
    }
    private(set) var errorMessage: String?
    /// PIDs with a Kill in flight (the row shows a spinner).
    private(set) var killing: Set<Int32> = []
    /// Inline per-row failure text, keyed by PID.
    private(set) var rowErrors: [Int32: String] = [:]

    private let portly = Portly(processSource: SystemProcessSource(), signaller: SystemSignaller())
    /// Counts refresh requests; a scan's result is only shown if no newer request arrived meanwhile.
    private var requested = 0
    /// The running scan loop. Nil when idle, so at most one scan is ever in flight.
    private var scanLoop: Task<Void, Never>?

    /// Requests a fresh Scan. A request that arrives while one is running supersedes it: the
    /// stale result is dropped and a new scan starts once the running one returns.
    func refresh() {
        requested += 1
        guard scanLoop == nil else { return }
        scanLoop = Task { await runScans() }
    }

    /// Called when the panel opens. Joins a scan that is already running instead of starting another.
    func refreshOnOpen() {
        if scanLoop == nil { refresh() }
    }

    private func runScans() async {
        while true {
            let ticket = requested
            let portly = portly
            let showAll = showAll
            let result = await Task.detached { Result { try portly.scan(showAll: showAll) } }.value
            guard ticket == requested else { continue }
            switch result {
            case .success(let scanned):
                rows = scanned
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            scanLoop = nil
            return
        }
    }

    /// Kills a row's Dev Server, then rescans. A failed Kill stays on the row as inline text.
    func kill(_ row: Row) async {
        guard !killing.contains(row.pid) else { return }
        killing.insert(row.pid)
        rowErrors[row.pid] = nil
        let outcome = await portly.kill(row)
        killing.remove(row.pid)
        rowErrors[row.pid] = RowFormat.failureText(outcome)
        refresh()
    }
}
