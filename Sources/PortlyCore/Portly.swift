import Foundation

/// Core entry point. All OS access goes through the injected `ProcessSource`.
public struct Portly: Sendable {
    private let processSource: any ProcessSource
    private let signaller: any Signaller
    private let escalationDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private let fileLookup: any FileLookup
    private let homeDirectory: String

    /// `escalationDelay` is how long a Kill waits after SIGTERM before sending SIGKILL;
    /// `sleep` is injectable so tests don't wait.
    public init(
        processSource: any ProcessSource,
        signaller: any Signaller,
        fileLookup: any FileLookup = DiskFileLookup(),
        homeDirectory: String = NSHomeDirectory(),
        escalationDelay: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.processSource = processSource
        self.fileLookup = fileLookup
        self.homeDirectory = homeDirectory
        self.signaller = signaller
        self.escalationDelay = escalationDelay
        self.sleep = sleep
    }

    /// Kills a Dev Server and its whole process group (ADR 0001): SIGTERM, then SIGKILL
    /// if the server is still alive after the escalation delay.
    public func kill(_ row: Row) async -> KillOutcome {
        let group = SignalTarget.group(row.processGroup)
        do {
            try signaller.send(.term, to: group)
        } catch SignalError.noSuchProcess {
            return .alreadyGone
        } catch {
            return .notPermitted
        }

        // Poll so a prompt exit doesn't hold the spinner for the full delay.
        let steps = 20
        let interval = escalationDelay / steps
        for _ in 0..<steps {
            if !signaller.isAlive(row.pid) { return .exitedAfterTerm }
            try? await sleep(interval)
        }
        if !signaller.isAlive(row.pid) { return .exitedAfterTerm }

        do {
            try signaller.send(.kill, to: group)
        } catch SignalError.noSuchProcess {
            return .exitedAfterTerm
        } catch {
            return .notPermitted
        }
        return .requiredKill
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
