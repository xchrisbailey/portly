/// The JavaScript engine executable a Dev Server runs under.
public enum Runtime: String, Sendable, Equatable {
    case node, bun, deno
}

/// One line of the panel: a single Listener and everything Portly knows about it.
/// Rows carry data only; the app decides how to word it.
public struct Row: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let processGroup: Int32
    /// Listening TCP ports, deduplicated across IPv4/IPv6 and ascending.
    public let ports: [Int]
    /// Nil for a Listener that isn't a Dev Server.
    public let runtime: Runtime?
    /// Short command such as `vite` or `next dev`.
    public let command: String
    public let commandLine: String
    /// Login name of the user running the process, as lsof reports it.
    public let owner: String?
    /// Real path of the process's executable, when the OS would tell us. Kill policy reads it.
    public let executablePath: String?
    /// True when any port is bound to all interfaces (Exposed).
    public let exposed: Bool
    /// Nil when the working directory couldn't be read.
    public let project: Project?
    /// Ports of the other Dev Servers in the same process group, ascending. A Kill of this
    /// row kills them too (ADR 0001).
    public let siblingPorts: [Int]

    public var id: Int32 { pid }

    public var isDevServer: Bool { runtime != nil }

    public init(
        pid: Int32, processGroup: Int32, ports: [Int], runtime: Runtime?, command: String, commandLine: String,
        owner: String?, executablePath: String?, exposed: Bool, project: Project?, siblingPorts: [Int]
    ) {
        self.pid = pid
        self.processGroup = processGroup
        self.ports = ports
        self.runtime = runtime
        self.command = command
        self.commandLine = commandLine
        self.owner = owner
        self.executablePath = executablePath
        self.exposed = exposed
        self.project = project
        self.siblingPorts = siblingPorts
    }
}
