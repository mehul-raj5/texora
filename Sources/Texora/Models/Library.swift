import Foundation
import Observation

struct ProjectRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var mainFile: String?
    var engine: TexEngine?
    var collectionID: UUID?
    var createdAt: Date = Date()
    var lastOpened: Date = Date()

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

struct CollectionRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var isExpanded: Bool = true
}

struct ChatRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID
    var title: String
    var sessionID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Everything Texora remembers about projects, collections and chats.
/// Stored as one JSON file in Application Support, so project folders stay clean.
@MainActor
@Observable
final class LibraryStore {
    private struct Snapshot: Codable {
        var projects: [ProjectRecord]
        var collections: [CollectionRecord]
        var chats: [ChatRecord]
    }

    var projects: [ProjectRecord] = [] { didSet { scheduleSave() } }
    var collections: [CollectionRecord] = [] { didSet { scheduleSave() } }
    var chats: [ChatRecord] = [] { didSet { scheduleSave() } }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = Paths.libraryFile) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? Self.decoder.decode(Snapshot.self, from: data) {
            projects = snap.projects
            collections = snap.collections
            chats = snap.chats
        }
        saveTask?.cancel()
    }

    // MARK: Projects

    var recentProjects: [ProjectRecord] { projects.sorted { $0.lastOpened > $1.lastOpened } }

    func project(_ id: UUID) -> ProjectRecord? { projects.first { $0.id == id } }

    func project(atPath path: String) -> ProjectRecord? {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        return projects.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == std }
    }

    @discardableResult
    func addProject(_ p: ProjectRecord) -> ProjectRecord {
        if let existing = project(atPath: p.path) { return existing }
        projects.append(p)
        return p
    }

    func update(_ id: UUID, _ change: (inout ProjectRecord) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[i])
    }

    /// Forgets a project (files on disk are left alone).
    func removeProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        chats.removeAll { $0.projectID == id }
    }

    // MARK: Collections

    func addCollection(named name: String) -> CollectionRecord {
        let c = CollectionRecord(name: name)
        collections.append(c)
        return c
    }

    func projects(in collection: UUID) -> [ProjectRecord] {
        projects.filter { $0.collectionID == collection }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func removeCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        for i in projects.indices where projects[i].collectionID == id { projects[i].collectionID = nil }
    }

    // MARK: Chats

    func chats(for project: UUID) -> [ChatRecord] {
        chats.filter { $0.projectID == project }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentChats: [ChatRecord] { chats.sorted { $0.updatedAt > $1.updatedAt } }

    func addChat(projectID: UUID, title: String = "New chat") -> ChatRecord {
        let c = ChatRecord(projectID: projectID, title: title)
        chats.append(c)
        return c
    }

    func updateChat(_ id: UUID, _ change: (inout ChatRecord) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[i])
    }

    func removeChat(_ id: UUID) {
        chats.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Paths.chatsDir.appendingPathComponent("\(id.uuidString).json"))
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snap = Snapshot(projects: projects, collections: collections, chats: chats)
        if let data = try? Self.encoder.encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
