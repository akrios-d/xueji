import Foundation
import XuejiCore

struct StartingWorkspace {
    let workspace: Workspace
    let meID: UUID
    let trackID: UUID
}

/// The workspace the app opens with. There is one person, the Mac's user, and one track. Agents are added
/// later, when the local API exists; the core already supports them.
extension StartingWorkspace {
    static func make(now: Date = Date(), withDemoCards: Bool = false) -> StartingWorkspace {
        var ws = Workspace()
        let me = Member(name: macUserName, kind: .human, role: L("demo.me.role"))
        let track = Track(name: L("track.default"))
        try! ws.addMember(me)
        ws.addTrack(track)

        #if DEBUG
        if withDemoCards { addDemoCards(to: &ws, trackID: track.id, meID: me.id, now: now) }
        #endif
        return StartingWorkspace(workspace: ws, meID: me.id, trackID: track.id)
    }

    /// The name of the person using this Mac.
    private static var macUserName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let short = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return short.isEmpty ? L("demo.me.fallbackName") : short
    }

    #if DEBUG
    /// A few cards of your own, so the board, the calendar and the due-day states are not empty while developing.
    private static func addDemoCards(to ws: inout Workspace, trackID: UUID, meID: UUID, now: Date) {
        let today = CalendarDay(now)

        let request = try! ws.createItem(
            trackID: trackID, kind: .researchRequest, title: L("demo.request.title"), by: meID, at: now
        )
        try! ws.setDueDay(itemID: request.id, to: today.adding(days: 4), by: meID, at: now)

        let reading = try! ws.createItem(
            trackID: trackID, kind: .note, title: L("demo.note.reading"), by: meID, at: now.addingTimeInterval(1)
        )
        try! ws.move(itemID: reading.id, to: .reading, by: meID, at: now.addingTimeInterval(2))
        // Already late, so the overdue states are visible.
        try! ws.setDueDay(itemID: reading.id, to: today.adding(days: -2), by: meID, at: now)

        let questions = try! ws.createItem(
            trackID: trackID, kind: .note, title: L("demo.note.questions"), by: meID, at: now.addingTimeInterval(3)
        )
        try! ws.setDueDay(itemID: questions.id, to: today.adding(days: 1), by: meID, at: now)

        try! ws.addMilestone(trackID: trackID, title: L("demo.milestone.1"), day: today.adding(days: 3), by: meID, at: now)
        try! ws.addMilestone(trackID: trackID, title: L("demo.milestone.2"), day: today.adding(days: 12), by: meID, at: now)
    }
    #endif
}
