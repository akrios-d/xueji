import Foundation
import XuejiCore

/// Keeps everything the student has made between runs: one JSON file in Application Support.
/// The previous run's file is kept next to it as a copy, and a file that cannot be read is moved aside
/// instead of being overwritten.
enum Persistence {
    struct Snapshot: Codable {
        var format = 1
        var workspace: Workspace
        var meID: UUID
        var trackID: UUID
        var drafts: [Draft]
        var versions: [ReadingVersion]
        /// Absent in files written before the Compile screen existed.
        var compilation: Compilation?
        /// One per project.
        var compilations: [UUID: Compilation]?
        /// One per project; absent in files written before the Evidence screen existed.
        var triages: [UUID: EvidenceSet]?
        /// Several per project (replaces `triages`).
        var triageSets: [UUID: [EvidenceSet]]?
    }

    enum Loaded {
        /// First run, nothing stored yet.
        case fresh
        case loaded(Snapshot)
        /// The file could not be read (for example, written by a different version). It was moved here.
        case unreadable(movedTo: URL)
    }

    private static var folder: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Xueji", isDirectory: true)
    }

    private static var fileURL: URL? { folder?.appendingPathComponent("data.json") }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func load() -> Loaded {
        guard let url = fileURL, let folder, FileManager.default.fileExists(atPath: url.path) else { return .fresh }
        do {
            let snapshot = try decoder().decode(Snapshot.self, from: Data(contentsOf: url))
            // A copy of what this run started from, in case something goes wrong later.
            let previous = folder.appendingPathComponent("data.previous.json")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.copyItem(at: url, to: previous)
            return .loaded(snapshot)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let moved = folder.appendingPathComponent("data.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: moved)
            return .unreadable(movedTo: moved)
        }
    }

    static func save(_ snapshot: Snapshot) throws {
        guard let url = fileURL, let folder else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
