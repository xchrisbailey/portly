import Foundation

/// Core entry point. All OS access goes through the injected `ProcessSource`.
public struct Portly: Sendable {
    private let processSource: any ProcessSource

    private let fileLookup: any FileLookup
    private let homeDirectory: String

    public init(
        processSource: any ProcessSource,
        fileLookup: any FileLookup = DiskFileLookup(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.processSource = processSource
        self.fileLookup = fileLookup
        self.homeDirectory = homeDirectory
    }

    /// Scans for Dev Servers and returns one row per server, sorted by lowest port.
    public func scan() throws -> [Row] {
        let sockets = LsofParser.listeningSockets(from: try processSource.listeningSockets())
        let devServers = sockets.compactMap { socket in
            Runtime(rawValue: socket.executable).map { (socket, $0) }
        }
        let byPid = Dictionary(grouping: devServers, by: { $0.0.pid })
        let pids = byPid.keys.sorted()
        let commandLines = try processSource.commandLines(for: pids)
        let workingDirectories = try processSource.workingDirectories(for: pids)

        return byPid.map { pid, entries in
            let runtime = entries[0].1
            let commandLine = commandLines[pid] ?? runtime.rawValue
            let project = workingDirectories[pid].flatMap(projectInfo(in:))
            return Row(
                pid: pid,
                processGroup: entries[0].0.processGroup,
                ports: Set(entries.map(\.0.port)).sorted(),
                runtime: runtime,
                command: ShortCommand.make(runtime: runtime, commandLine: commandLine),
                commandLine: commandLine,
                exposed: entries.contains { $0.0.binding == .allInterfaces },
                workingDirectory: workingDirectories[pid],
                project: project?.name,
                projectDirectory: project?.directory)
        }
        .sorted { ($0.ports[0], $0.pid) < ($1.ports[0], $1.pid) }
    }

    private func projectInfo(in directory: String) -> (name: String, directory: String)? {
        var path = directory
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard path != "/", path != homeDirectory else { return nil }
        if let found = fileLookup.package(atOrAbove: path), let name = found.name {
            return (name.split(separator: "/").last.map(String.init) ?? name, found.directory)
        }
        guard let folder = path.split(separator: "/").last.map(String.init) else { return nil }
        return (folder, path)
    }
}
