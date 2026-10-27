import Foundation

public enum Signal: Sendable, Equatable { case term, kill }

/// Who a signal is addressed to: one process, or every process in a group.
public enum SignalTarget: Sendable, Equatable {
    case process(Int32)
    case group(Int32)
}

public enum SignalError: Error, Sendable, Equatable {
    case notPermitted
    case noSuchProcess
    /// Any other errno from the signal call.
    case failed(Int32)
}

/// The boundary between Portly's core and signal delivery. The real adapter calls
/// `kill(2)`; tests inject a recording fake.
public protocol Signaller: Sendable {
    /// Maps ESRCH to `.noSuchProcess` and EPERM to `.notPermitted`; any other errno is `.failed`.
    func send(_ signal: Signal, to target: SignalTarget) throws(SignalError)

    /// True while any live process remains in the target: the PID itself, or any member of the
    /// group. Zombies count as dead.
    func isAlive(_ target: SignalTarget) -> Bool
}

/// How a Kill ended.
public enum KillOutcome: Sendable, Equatable {
    case exitedAfterTerm
    case requiredKill
    /// Another user owns the process (`owner` is their login name, when known).
    case notPermitted(owner: String?)
    case alreadyGone
    /// The signal failed for a reason other than permission or the process being gone.
    case failed(errno: Int32)
    /// Refused without signalling: the row is a macOS system binary.
    case blockedSystemBinary
}
