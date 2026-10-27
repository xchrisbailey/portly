/// A TCP listening socket read from `lsof -F` output.
struct ListeningSocket: Equatable {
    enum Binding { case loopback, allInterfaces }

    let pid: Int32
    let processGroup: Int32
    /// Executable name as reported by lsof's `c` field.
    let executable: String
    /// Login name from lsof's `L` field.
    let owner: String?
    let binding: Binding
    let port: Int
}

enum LsofParser {
    /// Parses `lsof -F pgcLftPn` output. Keeps TCP sockets bound to loopback or all
    /// interfaces; drops UDP, outbound connections and sockets on other addresses.
    static func listeningSockets(from output: String) -> [ListeningSocket] {
        var sockets: [ListeningSocket] = []
        var pid: Int32?
        var processGroup: Int32 = 0
        var executable = ""
        var owner: String?
        var proto = ""

        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                pid = Int32(value)
                processGroup = 0
                executable = ""
                owner = nil
            case "g": processGroup = Int32(value) ?? 0
            case "c": executable = String(value)
            case "L": owner = String(value)
            case "f": proto = ""
            case "P": proto = String(value)
            case "n":
                guard let pid, proto == "TCP", let (binding, port) = parseName(value) else { continue }
                sockets.append(ListeningSocket(
                    pid: pid, processGroup: processGroup, executable: executable, owner: owner, binding: binding, port: port))
            default: break
            }
        }
        return sockets
    }

    private static func parseName(_ name: Substring) -> (ListeningSocket.Binding, Int)? {
        guard !name.contains("->"), let colon = name.lastIndex(of: ":"),
              let port = Int(name[name.index(after: colon)...]) else { return nil }
        switch name[..<colon] {
        case "*", "0.0.0.0", "[::]": return (.allInterfaces, port)
        case "127.0.0.1", "[::1]": return (.loopback, port)
        default: return nil
        }
    }
}
