import XCTest
@testable import XuejiCore

final class PersistenceTests: XCTestCase {
    private func makeWorkspace() throws -> (Workspace, Member, Track) {
        var ws = Workspace()
        let me = Member(name: "Nade", kind: .human, role: "owner")
        let track = Track(name: "Thesis")
        try ws.addMember(me)
        ws.addTrack(track)
        return (ws, me, track)
    }

    func testAWorkspaceSurvivesBeingStoredAndLoaded() throws {
        var (ws, me, track) = try makeWorkspace()
        let url = URL(string: "https://example.org/paper")
        let item = try ws.createItem(trackID: track.id, kind: .source, title: "Paper", url: url, by: me.id, at: Date(timeIntervalSince1970: 1_000.001))
        try ws.move(itemID: item.id, to: .reading, by: me.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let loaded = try decoder.decode(Workspace.self, from: try encoder.encode(ws))

        XCTAssertEqual(loaded.items[item.id]?.title, "Paper")
        XCTAssertEqual(loaded.items[item.id]?.stage, .reading)
        XCTAssertEqual(loaded.items[item.id]?.url, url)
        XCTAssertEqual(loaded.items[item.id]?.createdAt.timeIntervalSince1970 ?? 0, 1_000.001, accuracy: 0.0005)
        XCTAssertEqual(loaded.events.count, ws.events.count)
        XCTAssertNotNil(loaded.members[me.id])
    }

    func testMergingBuiltInTypesAddsNewFieldsAndKeepsTheStudentsOwn() throws {
        var (ws, _, _) = try makeWorkspace()
        // An older file: the source type without "readingOrder", with a field the student added.
        var stored = try XCTUnwrap(ws.types[ItemType.sourceID])
        stored.fields.removeAll { $0.key == "readingOrder" }
        stored.fields.append(FieldDefinition(key: "pages", label: "Pages", kind: .number))
        let data = try JSONEncoder().encode(stored)
        _ = data
        ws.types[ItemType.sourceID] = stored

        ws.mergeBuiltInTypes()

        let keys = ws.types[ItemType.sourceID]?.fields.map(\.key) ?? []
        XCTAssertTrue(keys.contains("readingOrder"))
        XCTAssertTrue(keys.contains("pages"))
    }
}
