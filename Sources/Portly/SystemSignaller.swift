import Foundation
import PortlyCore

/// Real adapter over `kill(2)` and libproc. Not covered by automated tests.
struct SystemSignaller: Signaller {
    func send(_ signal: Signal, to target: SignalTarget) throws(SignalError) {
        let number = signal == .term ? SIGTERM : SIGKILL
        let result: Int32
        switch target {
        case .process(let pid):
            result = Foundation.kill(pid, number)
        case .group(let pgid):
            // Last line of defence: group 0 is our own, group 1 is launchd's.
            guard pgid > 1 else { throw .failed(EINVAL) }
            result = Foundation.killpg(pgid, number)
        }
        guard result != 0 else { return }
        switch errno {
        case ESRCH: throw .noSuchProcess
        case EPERM: throw .notPermitted
        case let code: throw .failed(code)
        }
    }

    func isAlive(_ target: SignalTarget) -> Bool {
        switch target {
        case .process(let pid):
            return isLive(pid)
        case .group(let pgid):
            let members = groupMembers(pgid)
            if members.isEmpty { return Foundation.kill(-pgid, 0) == 0 || errno == EPERM }
            return members.contains(where: isLive)
        }
    }

    /// Exists (EPERM means it belongs to someone else) and has not already exited as a zombie.
    private func isLive(_ pid: Int32) -> Bool {
        guard Foundation.kill(pid, 0) == 0 || errno == EPERM else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return true }
        return info.pbi_status != UInt32(SZOMB)
    }

    private func groupMembers(_ pgid: Int32) -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(pgid), nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 8)
        let written = proc_listpids(
            UInt32(PROC_PGRP_ONLY), UInt32(pgid), &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard written > 0 else { return [] }
        return pids.prefix(Int(written) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }
}
