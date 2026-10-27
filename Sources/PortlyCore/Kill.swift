/// Which Listeners Kill may touch and what it signals.
public enum KillPolicy {
    /// macOS system binaries (under `/System/` or `/usr/`, but not `/usr/local/`) can't be killed.
    /// Decided from the real executable path, never from argv.
    public static func isBlocked(_ row: Row) -> Bool {
        guard let path = row.executablePath, !path.hasPrefix("/usr/local/") else { return false }
        return ["/System/", "/usr/"].contains { path.hasPrefix($0) }
    }

    /// Dev Servers are signalled as a group (ADR 0001); other Listeners by PID only.
    static func target(for row: Row) -> SignalTarget {
        row.isDevServer ? .group(row.processGroup) : .process(row.pid)
    }
}

extension Portly {
    /// Kills a Dev Server and its whole process group (ADR 0001): SIGTERM, then SIGKILL
    /// if the server is still alive after the escalation delay.
    /// Listeners that aren't Dev Servers are signalled by PID only, and system binaries are refused.
    public func kill(_ row: Row) async -> KillOutcome {
        if KillPolicy.isBlocked(row) { return .blockedSystemBinary }
        let target = KillPolicy.target(for: row)
        if let outcome = send(.term, to: target, gone: .alreadyGone) { return outcome }

        // Poll so a prompt exit doesn't hold the spinner for the full delay.
        let steps = 20
        let interval = escalationDelay / steps
        for _ in 0..<steps {
            if !signaller.isAlive(row.pid) { return .exitedAfterTerm }
            try? await sleep(interval)
        }
        if !signaller.isAlive(row.pid) { return .exitedAfterTerm }

        return send(.kill, to: target, gone: .exitedAfterTerm) ?? .requiredKill
    }

    /// Sends a signal; returns the outcome that ends the Kill when it fails, nil on success.
    /// `gone` is the outcome when the target no longer exists.
    private func send(_ signal: Signal, to target: SignalTarget, gone: KillOutcome) -> KillOutcome? {
        do {
            try signaller.send(signal, to: target)
            return nil
        } catch SignalError.noSuchProcess {
            return gone
        } catch {
            return .notPermitted
        }
    }
}
