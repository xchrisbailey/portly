import Foundation

/// The boundary between Portly's core and the operating system's process table.
/// The real adapter shells out to `lsof` and `ps`; tests inject a fake.
public protocol ProcessSource: Sendable {
    /// `lsof -F` machine-readable output for every TCP listening socket on the machine.
    func listeningSockets() throws -> String

    /// Full command line (executable and arguments) for each of the given PIDs.
    /// PIDs that no longer exist are omitted.
    func commandLines(for pids: [Int32]) throws -> [Int32: String]
}
