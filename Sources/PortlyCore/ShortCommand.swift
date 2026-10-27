enum ShortCommand {
    /// Reduces a full command line to the part a person recognises: the script's file name
    /// plus its subcommand words, e.g. `node /app/node_modules/.bin/next dev --port 3000`
    /// becomes `next dev`. Falls back to the runtime name when there is no script.
    static func make(runtime: Runtime, commandLine: String) -> String {
        var words = commandLine.split(separator: " ").dropFirst().filter { !$0.isEmpty }[...]
        while let first = words.first, first.hasPrefix("-") { words.removeFirst() }
        // `deno run x.ts` and `bun run dev`: the subcommand is noise.
        if runtime != .node, words.first == "run" {
            words.removeFirst()
            while let first = words.first, first.hasPrefix("-") { words.removeFirst() }
        }
        guard let script = words.first else { return runtime.rawValue }
        let name = script.split(separator: "/").last.map(String.init) ?? String(script)
        let subcommands = words.dropFirst().prefix { !$0.hasPrefix("-") }
        return ([name] + subcommands.map(String.init)).joined(separator: " ")
    }
}
