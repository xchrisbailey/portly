import Testing
import Foundation
import PortlyCore

/// Records every call and replays scripted behaviour.
final class FakeSignaller: Signaller, @unchecked Sendable {
    enum Call: Equatable {
        case signal(Signal, SignalTarget)
        case isAlive(Int32)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    /// Errors thrown per signal; absent means success.
    var errors: [Signal: SignalError] = [:]
    /// Successive answers to `isAlive`; the last one repeats.
    var aliveAnswers: [Bool] = [false]

    var calls: [Call] { lock.withLock { _calls } }

    func send(_ signal: Signal, to target: SignalTarget) throws {
        lock.withLock { _calls.append(.signal(signal, target)) }
        if let error = errors[signal] { throw error }
    }

    func isAlive(_ pid: Int32) -> Bool {
        lock.withLock {
            _calls.append(.isAlive(pid))
            return aliveAnswers.count > 1 ? aliveAnswers.removeFirst() : aliveAnswers[0]
        }
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _total: Duration = .zero
    var total: Duration { lock.withLock { _total } }
    func sleep(_ d: Duration) { lock.withLock { _total += d } }
}

@Suite struct KillTests {
    let row = Row(pid: 100, processGroup: 90, ports: [3000], runtime: .node, command: "vite", commandLine: "node vite")

    func kill(_ signaller: FakeSignaller, sleeper: SleepRecorder = SleepRecorder()) async -> KillOutcome {
        let portly = Portly(
            processSource: FakeProcessSource(lsof: ""),
            signaller: signaller,
            escalationDelay: .seconds(2),
            sleep: { sleeper.sleep($0) })
        return await portly.kill(row)
    }

    @Test func exitingAfterSigtermSendsOnlySigtermToTheGroup() async {
        let s = FakeSignaller()
        s.aliveAnswers = [true, false]
        #expect(await kill(s) == .exitedAfterTerm)
        #expect(s.calls.first == .signal(.term, .group(90)))
        #expect(!s.calls.contains(.signal(.kill, .group(90))))
    }

    @Test func survivingSigtermIsEscalatedToSigkillOnTheGroupAfterTheDelay() async {
        let s = FakeSignaller()
        s.aliveAnswers = [true]
        let sleeper = SleepRecorder()
        #expect(await kill(s, sleeper: sleeper) == .requiredKill)
        let signals = s.calls.filter { if case .signal = $0 { true } else { false } }
        #expect(signals == [.signal(.term, .group(90)), .signal(.kill, .group(90))])
        #expect(sleeper.total == .seconds(2))
    }

    @Test func permissionFailureOnSigtermIsReportedAndNothingElseIsSent() async {
        let s = FakeSignaller()
        s.errors[.term] = .notPermitted
        #expect(await kill(s) == .notPermitted)
        #expect(s.calls == [.signal(.term, .group(90))])
    }

    @Test func permissionFailureOnSigkillIsReported() async {
        let s = FakeSignaller()
        s.aliveAnswers = [true]
        s.errors[.kill] = .notPermitted
        #expect(await kill(s) == .notPermitted)
    }

    @Test func serverThatAlreadyExitedIsAlreadyGone() async {
        let s = FakeSignaller()
        s.errors[.term] = .noSuchProcess
        #expect(await kill(s) == .alreadyGone)
        #expect(s.calls == [.signal(.term, .group(90))])
    }

    @Test func serverThatVanishesBetweenTermAndKillCountsAsExited() async {
        let s = FakeSignaller()
        s.aliveAnswers = [true]
        s.errors[.kill] = .noSuchProcess
        #expect(await kill(s) == .exitedAfterTerm)
    }
}
