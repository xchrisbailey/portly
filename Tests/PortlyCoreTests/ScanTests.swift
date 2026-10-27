import Testing
import PortlyCore

@Suite struct ScanTests {
    // Real `lsof -nP -iTCP -sTCP:LISTEN -F pgcLftPn` output captured on a machine running
    // node (pid 65897, ports 47311-47313), bun (65898, 47321) and deno (65899, 47331),
    // plus an unrelated node (94566, port 7265) and non-JavaScript listeners
    // (postgres, ControlCenter, ...).
    let commandLines: [Int32: String] = [
        65897: "node /private/tmp/x/srv.js",
        65898: "/Users/chris/.bun/bin/bun /private/tmp/x/b.js",
        65899: "deno run --allow-net /private/tmp/x/d.js",
        94566: "node /work/app/node_modules/.bin/vite --port 7265",
    ]

    func scan(lsof: String? = nil) throws -> [Row] {
        let source = FakeProcessSource(lsof: try lsof ?? fixture("lsof-mixed"), commandLines: commandLines)
        return try Portly(processSource: source).scan()
    }

    @Test func listsOnlyNodeBunAndDenoListeners() throws {
        let rows = try scan()
        #expect(rows.map(\.pid) == [94566, 65897, 65898, 65899])
        #expect(rows.map(\.runtime) == [.node, .node, .bun, .deno])
    }

    @Test func mergesIPv4AndIPv6AndListsAllPortsAscendingOnOneRow() throws {
        let node = try #require(try scan().first { $0.pid == 65897 })
        #expect(node.ports == [47311, 47312, 47313])
    }

    @Test func sortsRowsByLowestPort() throws {
        #expect(try scan().map(\.ports.first) == [7265, 47311, 47321, 47331])
    }

    @Test func rowsShowShortCommandAndFullCommandLine() throws {
        let rows = try scan()
        #expect(rows.map(\.command) == ["vite", "srv.js", "b.js", "d.js"])
        #expect(rows[0].commandLine == "node /work/app/node_modules/.bin/vite --port 7265")
    }

    @Test func showsSubcommandWordsInShortCommand() throws {
        let source = FakeProcessSource(
            lsof: "p10\ng10\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\n",
            commandLines: [10: "node /app/node_modules/.bin/next dev --port 3000"])
        #expect(try Portly(processSource: source).scan().map(\.command) == ["next dev"])
    }

    @Test func ignoresUDPOutboundAndNonLocalBindings() throws {
        let lsof = """
        p10
        g10
        cnode
        f1
        tIPv4
        PUDP
        n*:5353
        f2
        tIPv4
        PTCP
        n127.0.0.1:50000->127.0.0.1:5432
        f3
        tIPv4
        PTCP
        n192.168.1.5:8080
        f4
        tIPv4
        PTCP
        n127.0.0.1:3000

        """
        let rows = try scan(lsof: lsof)
        #expect(rows.map(\.ports) == [[3000]])
    }

    @Test func listsListenersBoundToAllInterfaces() throws {
        let lsof = "p10\ng10\ncbun\nf1\ntIPv6\nPTCP\nn[::]:8080\nf2\ntIPv4\nPTCP\nn0.0.0.0:8081\n"
        #expect(try scan(lsof: lsof).map(\.ports) == [[8080, 8081]])
    }

    @Test func returnsNoRowsWhenNothingIsListening() throws {
        #expect(try scan(lsof: "").isEmpty)
    }
}
