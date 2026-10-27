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
}

/// The boundary between Portly's core and signal delivery. The real adapter calls
/// `kill(2)`; tests inject a recording fake.
public protocol Signaller: Sendable {
    func send(_ signal: Signal, to target: SignalTarget) throws
    func isAlive(_ pid: Int32) -> Bool
}

/// How a Kill ended.
public enum KillOutcome: Sendable, Equatable {
    case exitedAfterTerm
    case requiredKill
    case notPermitted
    case alreadyGone
}
