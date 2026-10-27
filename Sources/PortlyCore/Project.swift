/// Where a Listener was started from, and the Project name derived from it.
public struct Project: Sendable, Equatable {
    /// The process's current working directory.
    public let workingDirectory: String
    /// Nil when the working directory is `/` or the home folder, which name nothing.
    public let name: String?
    /// Directory of the package.json that named the Project, else the working directory.
    public let directory: String

    public init(workingDirectory: String, name: String?, directory: String) {
        self.workingDirectory = workingDirectory
        self.name = name
        self.directory = directory
    }
}

/// Project naming: the nearest enclosing package.json name without its scope, else the folder name.
struct ProjectNaming: Sendable {
    let fileLookup: any FileLookup
    let homeDirectory: String

    func project(workingDirectory: String) -> Project {
        var path = workingDirectory
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard path != "/", path != homeDirectory else {
            return Project(workingDirectory: workingDirectory, name: nil, directory: workingDirectory)
        }
        if let found = fileLookup.package(atOrAbove: path), let name = found.name {
            return Project(
                workingDirectory: workingDirectory, name: name.split(separator: "/").last.map(String.init) ?? name,
                directory: found.directory)
        }
        return Project(
            workingDirectory: workingDirectory, name: path.split(separator: "/").last.map(String.init),
            directory: path)
    }
}
