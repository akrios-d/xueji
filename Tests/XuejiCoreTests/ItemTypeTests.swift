import XCTest
@testable import XuejiCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private struct Fixture {
    var ws = Workspace()
    let human: Member
    let agent: Member
    let track: Track

    init() throws {
        human = Member(name: "Nade", kind: .human, role: "owner")
        agent = Member(name: "Researcher", kind: .agent, role: "researcher", ownerID: human.id)
        track = Track(name: "Dissertation")
        try ws.addMember(human)
        try ws.addMember(agent)
        ws.addTrack(track)
    }

    mutating func makeSource(title: String = "Paper") throws -> Item {
        try ws.createItem(
            trackID: track.id, kind: .source, title: title,
            url: URL(string: "https://example.org/paper")!, by: human.id, at: t0
        )
    }
}

private func expect(
    _ expected: XuejiError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Void
) {
    XCTAssertThrowsError(try body(), file: file, line: line) {
        XCTAssertEqual($0 as? XuejiError, expected, file: file, line: line)
    }
}

final class ItemTypeTests: XCTestCase {
    // MARK: Built-in types

    func testBuiltInTypesAreInstalledWithStableIDs() {
        let ws = Workspace()
        XCTAssertEqual(Set(ws.types.keys), [ItemType.noteID, ItemType.researchRequestID, ItemType.sourceID, ItemType.statementID])
        XCTAssertEqual(ws.types[ItemType.sourceID]?.key, "source")
        XCTAssertTrue(ws.types.values.allSatisfy(\.isBuiltIn))
    }

    func testCreatingByKindResolvesTheBuiltInType() throws {
        var f = try Fixture()
        let source = try f.makeSource()
        XCTAssertEqual(source.typeID, ItemType.sourceID)
        XCTAssertEqual(source.kind, .source)
        let note = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        XCTAssertEqual(note.typeID, ItemType.noteID)
    }

    func testCustomKindCannotBeCreatedWithoutAType() throws {
        var f = try Fixture()
        expect(.typeNotFound) { _ = try f.ws.createItem(trackID: f.track.id, kind: .custom, title: "X", by: f.human.id) }
    }

    func testSourceKeepsItsLinkRule() throws {
        var f = try Fixture()
        expect(.sourceRequiresValidURL) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.sourceID, title: "S", by: f.human.id)
        }
    }

    // MARK: Statements

    func testStatementStoresItsValuesAndPointsAtASource() throws {
        var f = try Fixture()
        let source = try f.makeSource()
        let statement = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "Osborne, Shanghai",
            values: [
                "source": .relation(source.id),
                "actor": .text("George Osborne"),
                "actorKind": .select("government"),
                "position": .text("Britain can be China's best partner in the West."),
                "statementDate": .date(CalendarDay(year: 2015, month: 9, day: 22)),
                "dateApproximate": .checkbox(false),
            ],
            by: f.human.id, at: t0
        )
        XCTAssertEqual(statement.kind, .statement)
        XCTAssertEqual(f.ws.items(referencing: source.id).map(\.id), [statement.id])
    }

    func testRequiredFieldsMustBePresentAndNotBlank() throws {
        var f = try Fixture()
        expect(.requiredFieldMissing) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "S",
                                    values: ["position": .text("x")], by: f.agent.id)
        }
        expect(.requiredFieldMissing) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "S",
                                    values: ["actor": .text("  "), "position": .text("x")], by: f.agent.id)
        }
    }

    func testAStudentCanCaptureACardBeforeFillingTheRequiredFields() throws {
        var f = try Fixture()
        let draft = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "Draft", by: f.human.id)
        XCTAssertEqual(draft.approval, .approved)
        XCTAssertTrue(draft.values.isEmpty)
    }

    func testValuesAreCheckedAgainstTheirFields() throws {
        var f = try Fixture()
        let base: [String: FieldValue] = ["actor": .text("A"), "position": .text("P")]
        func create(_ extra: [String: FieldValue]) throws -> Item {
            try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "S",
                                values: base.merging(extra) { $1 }, by: f.human.id, at: t0)
        }
        expect(.fieldNotFound) { _ = try create(["nonsense": .text("x")]) }
        expect(.invalidFieldValue) { _ = try create(["quote": .number(3)]) }
        expect(.invalidFieldValue) { _ = try create(["actorKind": .select("alien")]) }
        expect(.invalidFieldValue) { _ = try create(["source": .relation(UUID())]) }
    }

    func testRelationMustPointAtTheRightTypeInTheSameTrack() throws {
        var f = try Fixture()
        let note = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        expect(.invalidFieldValue) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "S",
                                    values: ["actor": .text("A"), "position": .text("P"), "source": .relation(note.id)],
                                    by: f.human.id)
        }
        let other = Track(name: "Other")
        f.ws.addTrack(other)
        let foreign = try f.ws.createItem(trackID: other.id, kind: .source, title: "F",
                                          url: URL(string: "https://example.org/f")!, by: f.human.id, at: t0)
        expect(.invalidFieldValue) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: ItemType.statementID, title: "S",
                                    values: ["actor": .text("A"), "position": .text("P"), "source": .relation(foreign.id)],
                                    by: f.human.id)
        }
    }

    func testAgentStatementWaitsForApproval() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "S",
            values: ["actor": .text("A"), "position": .text("P")], by: f.agent.id, at: t0
        )
        XCTAssertEqual(item.approval, .pending)
        XCTAssertTrue(f.ws.kanban(trackID: f.track.id).values.allSatisfy { $0.isEmpty })
    }

    // MARK: Custom types

    private func lectureFields() -> [FieldDefinition] {
        [
            FieldDefinition(key: "held_on", label: "Held on", kind: .date),
            FieldDefinition(key: "format", label: "Format", kind: .select, options: [
                FieldOption(key: "lecture", label: "Lecture"),
                FieldOption(key: "seminar", label: "Seminar"),
            ]),
        ]
    }

    func testHumanCreatesACustomTypeAndUsesIt() throws {
        var f = try Fixture()
        let type = try f.ws.addType(name: "  Lecture ", fields: lectureFields(), by: f.human.id)
        XCTAssertEqual(type.name, "Lecture")
        XCTAssertEqual(type.behavior, .custom)
        XCTAssertFalse(type.isBuiltIn)

        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: type.id, title: "Week 3",
            values: ["format": .select("seminar")], by: f.human.id, at: t0
        )
        XCTAssertEqual(item.kind, .custom)
        XCTAssertEqual(item.typeID, type.id)
        expect(.invalidFieldValue) {
            _ = try f.ws.createItem(trackID: f.track.id, typeID: type.id, title: "x",
                                    values: ["format": .select("webinar")], by: f.human.id)
        }
    }

    func testOnlyHumansCreateTypesAndAgentsNeedPermissionToUseThem() throws {
        var f = try Fixture()
        expect(.notPermitted) { _ = try f.ws.addType(name: "Lecture", by: f.agent.id) }

        let closed = try f.ws.addType(name: "Private", agentsMayPropose: false, by: f.human.id)
        expect(.notPermitted) { _ = try f.ws.createItem(trackID: f.track.id, typeID: closed.id, title: "x", by: f.agent.id) }

        let open = try f.ws.addType(name: "Open", agentsMayPropose: true, by: f.human.id)
        let item = try f.ws.createItem(trackID: f.track.id, typeID: open.id, title: "x", by: f.agent.id, at: t0)
        XCTAssertEqual(item.approval, .pending)
    }

    func testFieldDefinitionsAreValidated() throws {
        var f = try Fixture()
        expect(.emptyText) { _ = try f.ws.addType(name: " ", by: f.human.id) }
        expect(.invalidFieldKey) {
            _ = try f.ws.addType(name: "T", fields: [FieldDefinition(key: "Bad Key", label: "x", kind: .text)], by: f.human.id)
        }
        expect(.duplicateFieldKey) {
            _ = try f.ws.addType(name: "T", fields: [
                FieldDefinition(key: "a", label: "A", kind: .text),
                FieldDefinition(key: "a", label: "A2", kind: .number),
            ], by: f.human.id)
        }
        expect(.invalidFieldDefinition) {
            _ = try f.ws.addType(name: "T", fields: [FieldDefinition(key: "pick", label: "Pick", kind: .select)], by: f.human.id)
        }
        expect(.invalidFieldDefinition) {
            _ = try f.ws.addType(name: "T", fields: [
                FieldDefinition(key: "rel", label: "Rel", kind: .relation, relatedTypeID: UUID()),
            ], by: f.human.id)
        }
    }

    // MARK: Changing types after the fact

    func testAddingAFieldAndAnOptionToABuiltInType() throws {
        var f = try Fixture()
        try f.ws.addField(typeID: ItemType.sourceID, field: FieldDefinition(key: "pages", label: "Pages", kind: .number), by: f.human.id)
        XCTAssertNotNil(f.ws.types[ItemType.sourceID]?.fields.first { $0.key == "pages" })
        expect(.duplicateFieldKey) {
            _ = try f.ws.addField(typeID: ItemType.sourceID, field: FieldDefinition(key: "pages", label: "Again", kind: .number), by: f.human.id)
        }

        try f.ws.addOption(typeID: ItemType.statementID, fieldKey: "actorKind", option: FieldOption(key: "ngo", label: "NGO"), by: f.human.id)
        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "S",
            values: ["actor": .text("A"), "position": .text("P"), "actorKind": .select("ngo")], by: f.human.id, at: t0
        )
        XCTAssertEqual(item.values["actorKind"], .select("ngo"))
        expect(.duplicateFieldKey) {
            _ = try f.ws.addOption(typeID: ItemType.statementID, fieldKey: "actorKind", option: FieldOption(key: "ngo", label: "Again"), by: f.human.id)
        }
        expect(.invalidFieldDefinition) {
            _ = try f.ws.addOption(typeID: ItemType.statementID, fieldKey: "actor", option: FieldOption(key: "x", label: "X"), by: f.human.id)
        }
    }

    func testARequiredFieldCannotBeAddedOnceItemsExist() throws {
        var f = try Fixture()
        let type = try f.ws.addType(name: "Lecture", by: f.human.id)
        try f.ws.addField(typeID: type.id, field: FieldDefinition(key: "early", label: "Early", kind: .text, isRequired: true), by: f.human.id)
        _ = try f.ws.createItem(trackID: f.track.id, typeID: type.id, title: "x", values: ["early": .text("y")], by: f.human.id, at: t0)
        expect(.invalidFieldDefinition) {
            _ = try f.ws.addField(typeID: type.id, field: FieldDefinition(key: "late", label: "Late", kind: .text, isRequired: true), by: f.human.id)
        }
    }

    // MARK: Editing values

    func testHumanEditsAndClearsValuesButAgentsCannot() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "S",
            values: ["actor": .text("A"), "position": .text("P")], by: f.human.id, at: t0
        )
        try f.ws.setFieldValue(itemID: item.id, key: "quote", to: .text("exact words"), by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[item.id]?.values["quote"], .text("exact words"))
        try f.ws.setFieldValue(itemID: item.id, key: "quote", to: nil, by: f.human.id, at: t0)
        XCTAssertNil(f.ws.items[item.id]?.values["quote"])
        XCTAssertEqual(f.ws.events.last?.kind, .edited)

        expect(.requiredFieldMissing) { _ = try f.ws.setFieldValue(itemID: item.id, key: "actor", to: nil, by: f.human.id) }
        expect(.fieldNotFound) { _ = try f.ws.setFieldValue(itemID: item.id, key: "nope", to: .text("x"), by: f.human.id) }
        expect(.invalidFieldValue) { _ = try f.ws.setFieldValue(itemID: item.id, key: "locator", to: .number(1), by: f.human.id) }
        expect(.notPermitted) { _ = try f.ws.setFieldValue(itemID: item.id, key: "quote", to: .text("x"), by: f.agent.id) }
    }

    func testHumanCanCorrectAnAgentProposalBeforeApproving() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "S",
            values: ["actor": .text("A"), "position": .text("P")], by: f.agent.id, at: t0
        )
        try f.ws.setFieldValue(itemID: item.id, key: "verification", to: .select("verified"), by: f.human.id, at: t0)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[item.id]?.values["verification"], .select("verified"))
    }

    func testValuesSurviveACodableRoundTrip() throws {
        var f = try Fixture()
        let source = try f.makeSource()
        let item = try f.ws.createItem(
            trackID: f.track.id, typeID: ItemType.statementID, title: "S",
            values: [
                "source": .relation(source.id), "actor": .text("A"), "position": .text("P"),
                "statementDate": .date(CalendarDay(year: 2020, month: 7, day: 16)), "dateApproximate": .checkbox(true),
            ],
            by: f.human.id, at: t0
        )
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(Item.self, from: data), item)
    }
}
