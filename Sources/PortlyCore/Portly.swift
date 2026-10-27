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
    /// Listeners that aren't Dev Servers are signalled by PID only, and system binaries are refused.
    public func kill(_ row: Row) async -> KillOutcome {
        if row.isSystemBinary { return .blockedSystemBinary }
        let group = row.isDevServer ? SignalTarget.group(row.processGroup) : SignalTarget.process(row.pid)
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

    /// Scans for Dev Servers (or, with `showAll`, every Listener) and returns one row
    /// per process, sorted by lowest port.
    public func scan(showAll: Bool = false) throws -> [Row] {
        let sockets = LsofParser.listeningSockets(from: try processSource.listeningSockets())
        let kept = sockets.filter { showAll || Runtime(rawValue: $0.executable) != nil }
        let byPid = Dictionary(grouping: kept, by: \.pid)
        let pids = byPid.keys.sorted()
        let commandLines = try processSource.commandLines(for: pids)
        let devPids = pids.filter { Runtime(rawValue: byPid[$0]![0].executable) != nil }
        let workingDirectories = try processSource.workingDirectories(for: devPids)

        // Siblings are other Dev Servers in the same process group (0 means unknown).
        var portsByGroup: [Int32: [Int32: [Int]]] = [:]
        for (pid, entries) in byPid where Runtime(rawValue: entries[0].executable) != nil {
            portsByGroup[entries[0].processGroup, default: [:]][pid] = entries.map(\.port)
        }

        return byPid.map { pid, entries in
            let group = entries[0].processGroup
            let siblingPorts = group == 0 || Runtime(rawValue: entries[0].executable) == nil ? [] : Set(
                (portsByGroup[group] ?? [:]).filter { $0.key != pid }.values.flatMap { $0 }
            ).sorted()
            let executable = entries[0].executable
            let runtime = Runtime(rawValue: executable)
            let commandLine = commandLines[pid] ?? executable
            let project = workingDirectories[pid].flatMap(projectInfo(in:))
            let systemBinary = ["/System/", "/usr/"].contains { commandLine.hasPrefix($0) }
            return Row(
                pid: pid,
                processGroup: entries[0].processGroup,
                ports: Set(entries.map(\.port)).sorted(),
                runtime: runtime,
                command: runtime.map { ShortCommand.make(runtime: $0, commandLine: commandLine) } ?? executable,
                commandLine: commandLine,
                executable: executable,
                isSystemBinary: systemBinary,
                exposed: entries.contains { $0.binding == .allInterfaces },
                workingDirectory: workingDirectories[pid],
                project: project?.name,
                projectDirectory: project?.directory,
                siblingPorts: siblingPorts)
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
