import Foundation
import PortlyCore

/// Real adapter: shells out to `lsof` and `ps`. Not covered by automated tests.
struct SystemProcessSource: ProcessSource {
    func listeningSockets() throws -> String {
        // -F fields: pid, process group, command name, login name, fd, type, protocol, name.
        try run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pgcLftPn"])
    }

    func workingDirectories(for pids: [Int32]) throws -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let output = try run("/usr/sbin/lsof", ["-nP", "-a", "-d", "cwd", "-F", "pn", "-p", list])
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in output.split(separator: "\n") {
            switch line.first {
            case "p": pid = Int32(line.dropFirst())
            case "n": if let pid { result[pid] = String(line.dropFirst()) }
            default: break
            }
        }
        return result
    }

    func commandLines(for pids: [Int32]) throws -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let output = try run("/bin/ps", ["-o", "pid=,args=", "-p", list])
        var result: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            result[pid] = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Runs a tool and returns stdout. Exit status is ignored: `lsof` and `ps` exit 1 when
    /// nothing matches, which is a valid empty result.
    private func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
