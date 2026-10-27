import Testing
import Foundation
import PortlyCore

struct FakeProcessSource: ProcessSource {
    var lsof: String
    var commandLines: [Int32: String] = [:]
    var workingDirectories: [Int32: String] = [:]

    func listeningSockets() throws -> String { lsof }
    func commandLines(for pids: [Int32]) throws -> [Int32: String] {
        commandLines.filter { pids.contains($0.key) }
    }

    func workingDirectories(for pids: [Int32]) throws -> [Int32: String] {
        workingDirectories.filter { pids.contains($0.key) }
    }
}

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}
