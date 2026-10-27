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
    public let runtime: Runtime
    /// Short command such as `vite` or `next dev`.
    public let command: String
    public let commandLine: String

    public var id: Int32 { pid }

    init(pid: Int32, processGroup: Int32, ports: [Int], runtime: Runtime, command: String, commandLine: String) {
        self.pid = pid
        self.processGroup = processGroup
        self.ports = ports
        self.runtime = runtime
        self.command = command
        self.commandLine = commandLine
    }
}
