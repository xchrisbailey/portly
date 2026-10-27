/// The JavaScript engine executable a Dev Server runs under.
public enum Runtime: String, Sendable, Equatable, CaseIterable {
    case node, bun, deno
}

/// One line of the panel: a single Dev Server and everything Portly knows about it.
public struct Row: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let processGroup: Int32
    /// Listening TCP ports, deduplicated across IPv4/IPv6 and ascending.
    public let ports: [Int]
    /// Nil for a Listener that isn't a Dev Server.
    public let runtime: Runtime?
    /// Executable name as reported by lsof (`postgres`, `node`).
    public let executable: String
    /// True when the executable lives under `/System` or `/usr`; Kill refuses these.
    public let isSystemBinary: Bool
    /// Short command such as `vite` or `next dev`.
    public let command: String
    public let commandLine: String
    /// True when any port is bound to all interfaces (Exposed).
    public let exposed: Bool
    /// The directory the Dev Server was started from, when it could be read.
    public let workingDirectory: String?
    /// Project name, or nil when the working directory is unknown, `/` or the home folder.
    public let project: String?
    /// Directory of the package.json that named the Project, else the working directory.
    public let projectDirectory: String?
    /// Ports of the other Dev Servers in the same process group, ascending. A Kill of this
    /// row kills them too (ADR 0001).
    public let siblingPorts: [Int]

    public var id: Int32 { pid }

    /// Warning shown before a Kill, e.g. `also kills :4000, :5000`; nil without Siblings.
    public var siblingWarning: String? {
        siblingPorts.isEmpty ? nil : "also kills " + siblingPorts.map { ":\($0)" }.joined(separator: ", ")
    }

    public var isDevServer: Bool { runtime != nil }

    /// Why Kill is unavailable for this row, or nil when it is allowed.
    public var killBlockedReason: String? {
        isSystemBinary ? "macOS system process, can't kill" : nil
    }

    /// Second part of the row text: `web · vite`, or `node server.js` without a Project.
    public var subtitle: String {
        guard let runtime else { return command }
        guard let project else { return "\(runtime.rawValue) \(command)" }
        return "\(project) · \(command)"
    }

    /// Full row text, e.g. `3000, 24678 · web · vite`.
    public var title: String {
        "\(ports.map(String.init).joined(separator: ", ")) · \(subtitle)"
    }

    public init(
        pid: Int32, processGroup: Int32, ports: [Int], runtime: Runtime?, command: String, commandLine: String,
        executable: String = "", isSystemBinary: Bool = false, exposed: Bool = false,
        workingDirectory: String? = nil, project: String? = nil,
        projectDirectory: String? = nil, siblingPorts: [Int] = []
    ) {
        self.pid = pid
        self.processGroup = processGroup
        self.ports = ports
        self.runtime = runtime
        self.executable = executable
        self.isSystemBinary = isSystemBinary
        self.command = command
        self.commandLine = commandLine
        self.exposed = exposed
        self.workingDirectory = workingDirectory
        self.project = project
        self.projectDirectory = projectDirectory
        self.siblingPorts = siblingPorts
    }
}
