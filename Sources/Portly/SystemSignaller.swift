import Foundation
import PortlyCore

/// Real adapter over `kill(2)`. Not covered by automated tests.
struct SystemSignaller: Signaller {
    func send(_ signal: Signal, to target: SignalTarget) throws {
        let number = signal == .term ? SIGTERM : SIGKILL
        let result: Int32
        switch target {
        case .process(let pid): result = Foundation.kill(pid, number)
        case .group(let pgid): result = Foundation.killpg(pgid, number)
        }
        guard result != 0 else { return }
        throw errno == EPERM ? SignalError.notPermitted : SignalError.noSuchProcess
    }

    func isAlive(_ pid: Int32) -> Bool {
        // EPERM means the process exists but belongs to someone else.
        Foundation.kill(pid, 0) == 0 || errno == EPERM
    }
}
