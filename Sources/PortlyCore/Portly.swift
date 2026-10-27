/// Core entry point. All OS access goes through the injected `ProcessSource`.
public struct Portly: Sendable {
    private let processSource: any ProcessSource

    public init(processSource: any ProcessSource) {
        self.processSource = processSource
    }

    /// Scans for Dev Servers and returns one row per server, sorted by lowest port.
    public func scan() throws -> [Row] {
        let sockets = LsofParser.listeningSockets(from: try processSource.listeningSockets())
        let devServers = sockets.compactMap { socket in
            Runtime(rawValue: socket.executable).map { (socket, $0) }
        }
        let byPid = Dictionary(grouping: devServers, by: { $0.0.pid })
        let commandLines = try processSource.commandLines(for: byPid.keys.sorted())
        let workingDirectories = try processSource.workingDirectories(for: byPid.keys.sorted())

        return byPid.map { pid, entries in
            let runtime = entries[0].1
            let commandLine = commandLines[pid] ?? runtime.rawValue
            return Row(
                pid: pid,
                processGroup: entries[0].0.processGroup,
                ports: Set(entries.map(\.0.port)).sorted(),
                runtime: runtime,
                command: ShortCommand.make(runtime: runtime, commandLine: commandLine),
                commandLine: commandLine,
                exposed: entries.contains { $0.0.binding == .allInterfaces },
                workingDirectory: workingDirectories[pid])
        }
        .sorted { ($0.ports[0], $0.pid) < ($1.ports[0], $1.pid) }
    }
}
