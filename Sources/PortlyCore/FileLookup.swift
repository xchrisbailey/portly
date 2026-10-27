import Foundation

/// The boundary between Portly's core and the file system, used to name Projects.
public protocol FileLookup: Sendable {
    /// Looks for the nearest `package.json` in `directory` or any ancestor.
    /// Returns nil when none exists.
    func package(atOrAbove directory: String) -> PackageJSON?
}

/// A located `package.json`: the directory holding it and the `name` it declares,
/// which is nil when the file has no usable name.
public struct PackageJSON: Sendable, Equatable {
    public let directory: String
    public let name: String?

    public init(directory: String, name: String?) {
        self.directory = directory
        self.name = name
    }
}

/// Real adapter: walks up the directory tree reading `package.json` files.
public struct DiskFileLookup: FileLookup {
    public init() {}

    public func package(atOrAbove directory: String) -> PackageJSON? {
        var url = URL(fileURLWithPath: directory)
        while true {
            let file = url.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: file) {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let name = (json?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return PackageJSON(directory: url.path, name: name)
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
    }
}
