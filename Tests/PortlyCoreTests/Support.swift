import Testing
import Foundation
import PortlyCore

struct FakeProcessSource: ProcessSource {
    var lsof: String
    var commandLines: [Int32: String] = [:]
    var workingDirectories: [Int32: String] = [:]
    var executablePaths: [Int32: String] = [:]

    func listeningSockets() throws -> String { lsof }
    func workingDirectories(for pids: [Int32]) throws -> [Int32: String] {
        workingDirectories.filter { pids.contains($0.key) }
    }
    func executablePaths(for pids: [Int32]) throws -> [Int32: String] {
        executablePaths.filter { pids.contains($0.key) }
    }
    func commandLines(for pids: [Int32]) throws -> [Int32: String] {
        commandLines.filter { pids.contains($0.key) }
    }
}

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

/// Fake File lookup: `packages` maps a directory to the `name` in its package.json.
struct FakeFileLookup: FileLookup {
    var packages: [String: String?] = [:]

    func package(atOrAbove directory: String) -> PackageJSON? {
        var dir = directory
        while true {
            if let name = packages[dir] { return PackageJSON(directory: dir, name: name) }
            if dir == "/" || dir.isEmpty { return nil }
            dir = dir.split(separator: "/").dropLast().map { "/" + $0 }.joined()
            if dir.isEmpty { dir = "/" }
        }
    }
}

/// Builds a Row for Kill tests; only what a test cares about needs naming.
func makeRow(
    pid: Int32 = 100, processGroup: Int32 = 90, runtime: Runtime? = .node, command: String = "vite",
    executablePath: String? = nil, owner: String? = "chris"
) -> Row {
    Row(
        pid: pid, processGroup: processGroup, ports: [3000], runtime: runtime, command: command,
        commandLine: command, owner: owner, executablePath: executablePath, exposed: false, project: nil, siblingPorts: [])
}
