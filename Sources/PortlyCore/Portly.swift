import Foundation

/// Core entry point. All OS access goes through the injected boundaries.
/// Scan lives in `Scan.swift`, Kill in `Kill.swift`.
public struct Portly: Sendable {
    let processSource: any ProcessSource
    let signaller: any Signaller
    let projectNaming: ProjectNaming
    let escalationDelay: Duration
    let sleep: @Sendable (Duration) async throws -> Void

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
        self.signaller = signaller
        self.projectNaming = ProjectNaming(fileLookup: fileLookup, homeDirectory: homeDirectory)
        self.escalationDelay = escalationDelay
        self.sleep = sleep
    }
}
