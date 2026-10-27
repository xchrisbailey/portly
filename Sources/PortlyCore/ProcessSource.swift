import Foundation

/// The boundary between Portly's core and the operating system's process table.
/// The real adapter shells out to `lsof` and `ps` and asks libproc; tests inject a fake.
public protocol ProcessSource: Sendable {
    /// `lsof -F` machine-readable output for every TCP listening socket on the machine.
    func listeningSockets() throws -> String

    /// Full command line (executable and arguments) for each of the given PIDs.
    /// PIDs that no longer exist are omitted.
    func commandLines(for pids: [Int32]) throws -> [Int32: String]

    /// Real path of the executable each of the given PIDs is running, as the OS reports it
    /// (not argv[0]). PIDs that no longer exist or cannot be inspected are omitted.
    func executablePaths(for pids: [Int32]) throws -> [Int32: String]

    /// Current working directory for each of the given PIDs.
    /// PIDs that no longer exist or cannot be inspected are omitted.
    func workingDirectories(for pids: [Int32]) throws -> [Int32: String]
}
