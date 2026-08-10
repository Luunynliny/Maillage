import Foundation

/// A file that could not be parsed. Surfaced to the UI rather than thrown, so one
/// malformed file never blocks loading the rest of the vault.
public struct VaultLoadIssue: Identifiable, Hashable, Sendable, Error {
    public var id: String { path }
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Everything loaded from a vault in one pass.
public struct VaultSnapshot: Sendable {
    public var people: [EntityID: Person] = [:]
    public var organizations: [EntityID: Organization] = [:]
    public var projects: [EntityID: Project] = [:]
    public var issues: [VaultLoadIssue] = []

    public init() {}

    public var isEmpty: Bool {
        people.isEmpty && organizations.isEmpty && projects.isEmpty
    }
}

/// Loads every markdown file in a vault into a ``VaultSnapshot``.
public struct VaultReader {
    public let location: VaultLocation

    public init(location: VaultLocation) {
        self.location = location
    }

    public func load() throws -> VaultSnapshot {
        var snapshot = VaultSnapshot()

        for url in markdownFiles(in: .person) {
            switch decode(Person.self, at: url) {
            case .success(var person):
                // The filename is authoritative: it is what wikilinks resolve against,
                // so a mismatched `id:` in frontmatter is corrected here.
                person.id = url.deletingPathExtension().lastPathComponent
                snapshot.people[person.id] = person
            case .failure(let issue):
                snapshot.issues.append(issue)
            }
        }

        for url in markdownFiles(in: .organization) {
            switch decode(Organization.self, at: url) {
            case .success(var org):
                org.id = url.deletingPathExtension().lastPathComponent
                snapshot.organizations[org.id] = org
            case .failure(let issue):
                snapshot.issues.append(issue)
            }
        }

        for url in markdownFiles(in: .project) {
            switch decode(Project.self, at: url) {
            case .success(var project):
                project.id = url.deletingPathExtension().lastPathComponent
                snapshot.projects[project.id] = project
            case .failure(let issue):
                snapshot.issues.append(issue)
            }
        }

        return snapshot
    }

    private func markdownFiles(in kind: EntityKind) -> [URL] {
        let directory = location.directory(for: kind)
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return [] }
        return contents.filter { $0.pathExtension.lowercased() == "md" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    private func decode<T: Decodable & BodyWritable>(_ type: T.Type, at url: URL) -> Result<
        T, VaultLoadIssue
    > {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            var (value, body) = try FrontmatterCodec.decode(type, from: contents, path: url.path)
            // `body` lives outside the frontmatter, so graft it on after decoding.
            value.body = body
            return .success(value)
        } catch {
            return .failure(
                VaultLoadIssue(
                    path: url.lastPathComponent,
                    message: (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription))
        }
    }
}

/// Lets ``VaultReader`` attach the markdown body after frontmatter decoding.
protocol BodyWritable {
    var body: String { get set }
}

extension Person: BodyWritable {}
extension Organization: BodyWritable {}
extension Project: BodyWritable {}
