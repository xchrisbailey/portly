import Foundation
import PortlyCore

/// All user-facing wording for a Row. The core exposes data; this decides how to say it.
enum RowFormat {
    /// Second part of the row text: `web · vite`, or `node server.js` without a Project name.
    static func subtitle(_ row: Row) -> String {
        guard let runtime = row.runtime else { return row.command }
        guard let name = row.project?.name else { return "\(runtime.rawValue) \(row.command)" }
        return "\(name) · \(row.command)"
    }

    /// Warning shown before a Kill, e.g. `also kills :4000, :5000`; nil without Siblings.
    static func siblingWarning(_ row: Row) -> String? {
        row.siblingPorts.isEmpty ? nil : "also kills " + row.siblingPorts.map { ":\($0)" }.joined(separator: ", ")
    }

    /// Why Kill is unavailable for this row, or nil when it is allowed.
    static func killBlockedReason(_ row: Row) -> String? {
        KillPolicy.isBlocked(row) ? "macOS system process, can't kill" : nil
    }

    /// Inline text for a Kill that failed, or nil when the row simply goes away.
    static func failureText(_ outcome: KillOutcome) -> String? {
        switch outcome {
        case .notPermitted(let owner): "Owned by \(owner ?? "another user"), can't kill"
        case .failed(let code): "Kill failed: \(String(cString: strerror(code)))"
        case .exitedAfterTerm, .requiredKill, .alreadyGone, .blockedSystemBinary: nil
        }
    }
}
