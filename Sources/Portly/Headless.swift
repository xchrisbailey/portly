import Foundation
import PortlyCore

/// Command-line mode for checking the real adapters without the panel:
///   Portly --scan [--all]   print rows as JSON
///   Portly --kill <pid>     Kill the row with that PID and print the outcome
/// Returns nil when the arguments don't ask for headless mode, so the menu bar app starts.
enum Headless {
    static func run(_ arguments: [String]) -> Int32? {
        let portly = Portly(processSource: SystemProcessSource(), signaller: SystemSignaller())
        switch arguments.first {
        case "--scan":
            return scan(portly, showAll: arguments.contains("--all"))
        case "--kill":
            guard arguments.count == 2, let pid = Int32(arguments[1]) else {
                return fail("usage: Portly --kill <pid>")
            }
            return kill(portly, pid: pid)
        default:
            return nil
        }
    }

    private static func scan(_ portly: Portly, showAll: Bool) -> Int32 {
        do {
            let rows = try portly.scan(showAll: showAll).map(json)
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            return fail("scan failed: \(error)")
        }
    }

    private static func kill(_ portly: Portly, pid: Int32) -> Int32 {
        let rows: [Row]
        do {
            rows = try portly.scan(showAll: true)
        } catch {
            return fail("scan failed: \(error)")
        }
        guard let row = rows.first(where: { $0.pid == pid }) else {
            return fail("no Listener with pid \(pid)")
        }
        // Kill is async; block the main thread on it, since headless mode has no run loop to keep.
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: KillOutcome?
        Task.detached {
            outcome = await portly.kill(row)
            done.signal()
        }
        done.wait()
        print(String(describing: outcome!))
        return outcome == .exitedAfterTerm || outcome == .requiredKill || outcome == .alreadyGone ? 0 : 1
    }

    private static func json(_ row: Row) -> [String: Any] {
        [
            "pid": row.pid,
            "processGroup": row.processGroup,
            "ports": row.ports,
            "runtime": row.runtime?.rawValue ?? NSNull(),
            "command": row.command,
            "commandLine": row.commandLine,
            "owner": row.owner ?? NSNull(),
            "executablePath": row.executablePath ?? NSNull(),
            "exposed": row.exposed,
            "project": row.project?.name ?? NSNull(),
            "projectDirectory": row.project?.directory ?? NSNull(),
            "siblingPorts": row.siblingPorts,
            "killBlocked": KillPolicy.isBlocked(row),
        ]
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}

@main
enum Entry {
    static func main() {
        if let status = Headless.run(Array(CommandLine.arguments.dropFirst())) {
            exit(status)
        }
        PortlyApp.main()
    }
}
