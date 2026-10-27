/// Which Listeners Kill may touch and what it signals.
public enum KillPolicy {
    /// macOS system binaries (under `/System/` or `/usr/`, but not `/usr/local/`) can't be killed.
    /// Decided from the real executable path, never from argv.
    public static func isBlocked(_ row: Row) -> Bool {
        guard let path = row.executablePath, !path.hasPrefix("/usr/local/") else { return false }
        return ["/System/", "/usr/"].contains { path.hasPrefix($0) }
    }

    /// Dev Servers are signalled as a group (ADR 0001); other Listeners by PID only.
    /// Groups 0 and 1, and Portly's own group, are never signalled; the PID is signalled instead.
    static func target(for row: Row, ownProcessGroup: Int32) -> SignalTarget {
        let usable = row.processGroup > 1 && row.processGroup != ownProcessGroup
        return row.isDevServer && usable ? .group(row.processGroup) : .process(row.pid)
    }
}

extension Portly {
    /// Kills a Dev Server and its whole process group (ADR 0001): SIGTERM, then SIGKILL
    /// if the server is still alive after the escalation delay.
    /// Listeners that aren't Dev Servers are signalled by PID only, and system binaries are refused.
    public func kill(_ row: Row) async -> KillOutcome {
        if KillPolicy.isBlocked(row) { return .blockedSystemBinary }
        let target = KillPolicy.target(for: row, ownProcessGroup: ownProcessGroup)
        if let outcome = send(.term, to: target, row: row, gone: .alreadyGone) { return outcome }

        // Poll so a prompt exit doesn't hold the spinner for the full delay.
        let steps = 20
        let interval = escalationDelay / steps
        for _ in 0..<steps {
            if !signaller.isAlive(target) { return .exitedAfterTerm }
            try? await sleep(interval)
        }
        if !signaller.isAlive(target) { return .exitedAfterTerm }

        return send(.kill, to: target, row: row, gone: .exitedAfterTerm) ?? .requiredKill
    }

    /// Sends a signal; returns the outcome that ends the Kill when it fails, nil on success.
    /// `gone` is the outcome when the target no longer exists.
    private func send(_ signal: Signal, to target: SignalTarget, row: Row, gone: KillOutcome) -> KillOutcome? {
        do {
            try signaller.send(signal, to: target)
            return nil
        } catch {
            switch error {
            case .noSuchProcess: return gone
            case .notPermitted: return .notPermitted(owner: row.owner)
            case .failed(let code): return .failed(errno: code)
            }
        }
    }
}
