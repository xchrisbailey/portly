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
    let row = makeRow()

    func kill(_ signaller: FakeSignaller, row: Row? = nil, sleeper: SleepRecorder = SleepRecorder()) async -> KillOutcome {
        let portly = Portly(
            processSource: FakeProcessSource(lsof: ""),
            signaller: signaller,
            escalationDelay: .seconds(2),
            sleep: { sleeper.sleep($0) })
        return await portly.kill(row ?? self.row)
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

    @Test func nonDevServerListenerIsSignalledByPidOnlyWithSameEscalation() async {
        let listener = makeRow(pid: 200, processGroup: 190, runtime: nil, command: "postgres")
        let s = FakeSignaller()
        s.aliveAnswers = [true]
        #expect(await kill(s, row: listener) == .requiredKill)
        let signals = s.calls.filter { if case .signal = $0 { true } else { false } }
        #expect(signals == [.signal(.term, .process(200)), .signal(.kill, .process(200))])
    }

    @Test(arguments: ["/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", "/usr/libexec/rapportd"])
    func systemBinaryIsRefusedWithoutSignalling(path: String) async {
        let system = makeRow(pid: 300, processGroup: 300, runtime: nil, command: "ControlCenter", executablePath: path)
        let s = FakeSignaller()
        #expect(await kill(s, row: system) == .blockedSystemBinary)
        #expect(s.calls.isEmpty)
    }

    @Test(arguments: ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/Users/chris/.bun/bin/bun"])
    func devServersFromNonSystemPathsAreKilled(path: String) async {
        let s = FakeSignaller()
        #expect(await kill(s, row: makeRow(executablePath: path)) == .exitedAfterTerm)
        #expect(s.calls.first == .signal(.term, .group(90)))
    }
}
