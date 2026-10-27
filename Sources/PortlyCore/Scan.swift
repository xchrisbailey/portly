/// Everything Scan learns about one listening process, computed once per PID.
private struct ListeningProcess {
    let pid: Int32
    let processGroup: Int32
    let executable: String
    let owner: String?
    let runtime: Runtime?
    /// Deduplicated across IPv4/IPv6 and ascending.
    let ports: [Int]
    let exposed: Bool

    init(sockets: [ListeningSocket]) {
        let first = sockets[0]
        pid = first.pid
        processGroup = first.processGroup
        executable = first.executable
        owner = first.owner
        runtime = Runtime(rawValue: first.executable)
        ports = Set(sockets.map(\.port)).sorted()
        exposed = sockets.contains { $0.binding == .allInterfaces }
    }
}

extension Portly {
    /// Scans for Dev Servers (or, with `showAll`, every Listener) and returns one row
    /// per process, sorted by lowest port.
    public func scan(showAll: Bool = false) throws -> [Row] {
        let sockets = LsofParser.listeningSockets(from: try processSource.listeningSockets())
        let processes = Dictionary(grouping: sockets, by: \.pid).values
            .map(ListeningProcess.init(sockets:))
            .filter { showAll || $0.runtime != nil }
            .sorted { $0.pid < $1.pid }
        let commandLines = try processSource.commandLines(for: processes.map(\.pid))
        let executablePaths = try processSource.executablePaths(for: processes.map(\.pid))
        let workingDirectories = try processSource.workingDirectories(
            for: processes.filter { $0.runtime != nil }.map(\.pid))

        // Siblings are other Dev Servers in the same process group (0 means unknown).
        let devServersByGroup = Dictionary(
            grouping: processes.filter { $0.runtime != nil && $0.processGroup != 0 }, by: \.processGroup)

        return processes.map { process in
            let siblingPorts =
                devServersByGroup[process.processGroup]?
                .filter { $0.pid != process.pid }.flatMap(\.ports) ?? []
            let commandLine = commandLines[process.pid] ?? process.executable
            return Row(
                pid: process.pid,
                processGroup: process.processGroup,
                ports: process.ports,
                runtime: process.runtime,
                command: process.runtime.map { ShortCommand.make(runtime: $0, commandLine: commandLine) }
                    ?? process.executable,
                commandLine: commandLine,
                owner: process.owner,
                executablePath: executablePaths[process.pid],
                exposed: process.exposed,
                project: workingDirectories[process.pid].map(projectNaming.project(workingDirectory:)),
                siblingPorts: Set(siblingPorts).sorted())
        }
        .sorted { ($0.ports[0], $0.pid) < ($1.ports[0], $1.pid) }
    }
}
