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
        865: "/usr/libexec/rapportd",
        943: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        1395: "/opt/homebrew/opt/postgresql@16/bin/postgres -D /opt/homebrew/var/postgresql@16",
    ]

    func scanAll() throws -> [Row] {
        let source = FakeProcessSource(lsof: try fixture("lsof-mixed"), commandLines: commandLines)
        return try Portly(processSource: source, signaller: FakeSignaller()).scan(showAll: true)
    }

    @Test func showAllListsEveryListenerWithoutARuntimeForNonDevServers() throws {
        let rows = try scanAll()
        #expect(rows.count == 11)
        let postgres = try #require(rows.first { $0.pid == 1395 })
        #expect(postgres.runtime == nil)
        #expect(!postgres.isDevServer)
        #expect(postgres.ports == [5432])
        #expect(try #require(rows.first { $0.pid == 65897 }).runtime == .node)
    }

    @Test func defaultScanStillHidesNonDevServers() throws {
        #expect(try scan().count == 4)
        #expect(try scan().allSatisfy(\.isDevServer))
    }

    @Test func systemBinariesAreMarkedNotKillable() throws {
        let rows = try scanAll()
        #expect(try #require(rows.first { $0.pid == 943 }).killBlockedReason != nil)
        #expect(try #require(rows.first { $0.pid == 865 }).isSystemBinary)
        #expect(try #require(rows.first { $0.pid == 1395 }).killBlockedReason == nil)
        #expect(try #require(rows.first { $0.pid == 94566 }).killBlockedReason == nil)
    }

    func scan(lsof: String? = nil) throws -> [Row] {
        let source = FakeProcessSource(lsof: try lsof ?? fixture("lsof-mixed"), commandLines: commandLines)
        return try Portly(processSource: source, signaller: FakeSignaller()).scan()
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
        #expect(try Portly(processSource: source, signaller: FakeSignaller()).scan().map(\.command) == ["next dev"])
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

    @Test func marksAllInterfaceBindingsAsExposedAndLoopbackAsNot() throws {
        let lsof = "p10\ng10\ncbun\nf1\ntIPv4\nPTCP\nn*:8080\np11\ng11\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\n"
        let rows = try scan(lsof: lsof)
        #expect(rows.map(\.ports) == [[3000], [8080]])
        #expect(rows.map(\.exposed) == [false, true])
    }

    @Test func exposedWhenAnyPortIsBoundToAllInterfaces() throws {
        let lsof = "p10\ng10\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\nf2\ntIPv4\nPTCP\nn*:3001\n"
        #expect(try scan(lsof: lsof).map(\.exposed) == [true])
    }

    @Test func rowsCarryTheWorkingDirectory() throws {
        let source = FakeProcessSource(
            lsof: "p10\ng10\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\n",
            commandLines: [10: "node /app/srv.js"],
            workingDirectories: [10: "/work/app"])
        #expect(try Portly(processSource: source, signaller: FakeSignaller()).scan().map(\.workingDirectory) == ["/work/app"])
    }

    // MARK: Project naming

    func projectRows(cwd: String, packages: [String: String?], commandLine: String = "node /x/server.js") throws -> [Row] {
        let source = FakeProcessSource(
            lsof: "p10\ng10\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\nf2\ntIPv6\nPTCP\nn[::1]:24678\n",
            commandLines: [10: commandLine], workingDirectories: [10: cwd])
        return try Portly(
            processSource: source, signaller: FakeSignaller(), fileLookup: FakeFileLookup(packages: packages),
            homeDirectory: "/Users/chris").scan()
    }

    @Test func projectNameComesFromNearestPackageJsonAtOrAboveWorkingDirectory() throws {
        let rows = try projectRows(
            cwd: "/work/mono/apps/web/src",
            packages: ["/work/mono": "mono", "/work/mono/apps/web": "web"],
            commandLine: "node /x/vite")
        #expect(rows[0].project == "web")
        #expect(rows[0].subtitle == "web · vite")
    }

    @Test func removesNpmScope() throws {
        let rows = try projectRows(cwd: "/work/web", packages: ["/work/web": "@acme/web"])
        #expect(rows[0].project == "web")
    }

    @Test func fallsBackToFolderNameWithoutPackageJson() throws {
        let rows = try projectRows(cwd: "/work/my-app", packages: [:])
        #expect(rows[0].project == "my-app")
    }

    @Test func showsRuntimeAndScriptWhenWorkingDirectoryIsRoot() throws {
        let rows = try projectRows(cwd: "/", packages: [:])
        #expect(rows[0].project == nil)
        #expect(rows[0].subtitle == "node server.js")
    }

    @Test func showsRuntimeAndScriptWhenWorkingDirectoryIsHome() throws {
        let rows = try projectRows(cwd: "/Users/chris", packages: [:])
        #expect(rows[0].subtitle == "node server.js")
    }

    @Test func showsRuntimeAndScriptWhenWorkingDirectoryUnknown() throws {
        let source = FakeProcessSource(
            lsof: "p10\ng10\ncnode\nf1\ntIPv4\nPTCP\nn127.0.0.1:3000\n",
            commandLines: [10: "node /x/server.js"])
        let rows = try Portly(processSource: source, signaller: FakeSignaller(), fileLookup: FakeFileLookup()).scan()
        #expect(rows[0].subtitle == "node server.js")
    }

    @Test func rowTitleListsPortsThenProjectThenCommand() throws {
        let rows = try projectRows(cwd: "/work/web", packages: ["/work/web": "@acme/web"], commandLine: "node /x/vite")
        #expect(rows[0].title == "3000, 24678 · web · vite")
    }

    @Test func projectDirectoryIsWhereThePackageJsonThatNamedTheProjectLives() throws {
        let rows = try projectRows(cwd: "/work/mono/apps/web/src", packages: ["/work/mono/apps/web": "web"])
        #expect(rows[0].projectDirectory == "/work/mono/apps/web")
        #expect(rows[0].workingDirectory == "/work/mono/apps/web/src")
    }

    @Test func projectDirectoryFallsBackToWorkingDirectory() throws {
        let rows = try projectRows(cwd: "/work/my-app", packages: [:])
        #expect(rows[0].projectDirectory == "/work/my-app")
    }
}

@Suite struct SiblingTests {
    func lsof(_ servers: [(pid: Int, group: Int, cmd: String, port: Int)]) -> String {
        servers.map { "p\($0.pid)\ng\($0.group)\nc\($0.cmd)\nf1\ntIPv4\nPTCP\nn127.0.0.1:\($0.port)\n" }.joined()
    }

    func scan(_ servers: [(pid: Int, group: Int, cmd: String, port: Int)]) throws -> [Row] {
        let source = FakeProcessSource(lsof: lsof(servers))
        return try Portly(processSource: source, signaller: FakeSignaller()).scan()
    }

    @Test func reportsPortsOfOtherDevServersInTheSameProcessGroup() throws {
        let rows = try scan([(10, 5, "node", 3000), (11, 5, "bun", 4000), (12, 5, "node", 5000)])
        #expect(rows.map(\.siblingPorts) == [[4000, 5000], [3000, 5000], [3000, 4000]])
        #expect(rows[0].siblingWarning == "also kills :4000, :5000")
    }

    @Test func rowsWithoutSiblingsHaveNoWarning() throws {
        let rows = try scan([(10, 5, "node", 3000), (11, 6, "node", 4000)])
        #expect(rows.allSatisfy { $0.siblingPorts.isEmpty && $0.siblingWarning == nil })
    }

    @Test func nonDevServerListenersInTheGroupAreNotSiblings() throws {
        let rows = try scan([(10, 5, "node", 3000), (11, 5, "postgres", 5432)])
        #expect(rows.map(\.siblingPorts) == [[]])
    }

    @Test func siblingsDisappearOnRescanAfterKill() throws {
        let before = try scan([(10, 5, "node", 3000), (11, 5, "node", 4000)])
        #expect(before.count == 2)
        #expect(try scan([]).isEmpty)
    }
}
