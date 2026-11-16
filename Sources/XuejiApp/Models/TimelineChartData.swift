import Foundation
import XuejiCore

/// One row of the timeline chart: a period, or a document.
struct TimelineLane: Identifiable, Equatable {
    let id: String
    let name: String
    let isEra: Bool
}

/// Something drawn on the chart: a period, an event that lasted for a period, or an event on one date.
struct TimelineItem: Identifiable, Equatable {
    let id: UUID
    let start: Date
    /// nil for an event on a single date.
    let end: Date?
    let lane: String
    let title: String
    let dateLabel: String
    let quotes: [String]
    let isGap: Bool
    let isEra: Bool
    /// How deep the period is inside the others (0 is the master).
    let depth: Int
}

/// What the timeline chart draws: the periods on top (the master first), then one row per document.
struct TimelineChartData: Equatable {
    var items: [TimelineItem] = []
    var lanes: [TimelineLane] = []
    /// Events whose date could not be read; they are listed but not drawn.
    var undated = 0
    /// The first and the last year of what is drawn: the axis always runs in whole years.
    var years: ClosedRange<Int>?

    /// `events` come in date order and `outline` is the tree of periods, the master first.
    static func make(
        events: [EvidenceEvent], outline: [EraNode], masterName: String, title: (UUID?) -> String,
        quote: (UUID) -> String, noDocument: String
    ) -> TimelineChartData {
        var data = TimelineChartData()
        var first: EvidenceDate?
        var last: EvidenceDate?
        var begin: Date?
        var finish: Date?
        func note(_ from: EvidenceDate, _ until: EvidenceDate?, start: Date, end: Date) {
            if first == nil || from.year < first?.year ?? from.year { first = from }
            let tail = until ?? from
            if last == nil || tail.year > last?.year ?? tail.year { last = tail }
            begin = min(begin ?? start, start)
            finish = max(finish ?? end, end)
        }

        var eraItems: [TimelineItem] = []
        var eraLanes: [TimelineLane] = []
        for node in outline {
            guard let era = node.era else { continue }
            let lane = "era-" + era.id.uuidString
            let name = era.name.isEmpty ? era.dateLabel : era.name
            eraLanes.append(TimelineLane(id: lane, name: name, isEra: true))
            eraItems.append(TimelineItem(
                id: era.id, start: era.from.start, end: era.until.end, lane: lane, title: name, dateLabel: era.dateLabel,
                quotes: era.quoteIDs.map(quote).filter { !$0.isEmpty }, isGap: false, isEra: true, depth: node.depth
            ))
            note(era.from, era.until, start: era.from.start, end: era.until.end)
        }

        var documentLanes: [TimelineLane] = []
        var noDocumentLane: TimelineLane?
        var eventItems: [TimelineItem] = []
        for event in events {
            guard let from = event.position else {
                data.undated += 1
                continue
            }
            let lane: TimelineLane
            let name = event.sourceID.map(title) ?? ""
            if let sourceID = event.sourceID, !name.isEmpty {
                lane = TimelineLane(id: "doc-" + sourceID.uuidString, name: name, isEra: false)
                if !documentLanes.contains(lane) { documentLanes.append(lane) }
            } else {
                lane = TimelineLane(id: "doc-none", name: noDocument, isEra: false)
                noDocumentLane = lane
            }
            let until = event.until.flatMap { $0 != from ? $0 : nil }
            eventItems.append(TimelineItem(
                id: event.id, start: until == nil ? from.date : from.start, end: until?.end, lane: lane.id,
                title: event.event.isEmpty ? event.dateLabel : event.event, dateLabel: event.dateLabel,
                quotes: event.quoteID.map(quote).map { $0.isEmpty ? [] : [$0] } ?? [], isGap: event.isGap, isEra: false,
                depth: 0
            ))
            note(from, until, start: until == nil ? from.date : from.start, end: until?.end ?? from.date)
        }

        // The master period covers everything that is drawn.
        if let first, let last, let begin, let finish {
            data.years = first.year...last.year
            let master = TimelineLane(id: "era-master", name: masterName, isEra: true)
            data.lanes.append(master)
            data.items.append(TimelineItem(
                id: EraNode.masterID, start: begin, end: finish, lane: master.id, title: masterName,
                dateLabel: EvidenceDate.label(from: EvidenceDate(year: first.year), until: EvidenceDate(year: last.year)),
                quotes: [], isGap: false, isEra: true, depth: 0
            ))
        }
        data.lanes += eraLanes + documentLanes
        if let noDocumentLane { data.lanes.append(noDocumentLane) }
        data.items += eraItems + eventItems
        return data
    }
}
