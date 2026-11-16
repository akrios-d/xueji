import Foundation

/// One period in the outline of the timeline. The whole timeline is always the first one (the master period, which
/// has no entry of its own: `era` is nil) and every other period sits inside the master or inside another period.
struct EraNode: Identifiable, Equatable {
    static let masterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    let era: EvidenceEra?
    /// 0 for the master, 1 for the periods directly inside it, and so on.
    let depth: Int

    var id: UUID { era?.id ?? Self.masterID }
    var isMaster: Bool { era == nil }
}

extension Array where Element == EraNode {
    /// The periods inside the one given, at any depth.
    func descendantIDs(of id: UUID) -> Set<UUID> {
        guard let index = firstIndex(where: { $0.id == id }) else { return [] }
        let depth = self[index].depth
        var result = Set<UUID>()
        for node in self[(index + 1)...] {
            if node.depth <= depth { break }
            result.insert(node.id)
        }
        return result
    }
}

extension EvidenceSet {
    /// The periods as a tree read top to bottom: the master, then each period followed by the ones inside it.
    func outline() -> [EraNode] {
        let known = Set(eras.map(\.id))
        let ordered = sortedEras
        var result = [EraNode(era: nil, depth: 0)]
        func add(parent: UUID?, depth: Int, path: Set<UUID>) {
            for era in ordered where !path.contains(era.id) {
                let own = era.parentID.flatMap { known.contains($0) ? $0 : nil }
                guard own == parent else { continue }
                result.append(EraNode(era: era, depth: depth))
                add(parent: era.id, depth: depth + 1, path: path.union([era.id]))
            }
        }
        add(parent: nil, depth: 1, path: [])
        return result
    }

    /// The period an event belongs to; the master (nil) when it names none or one that is gone.
    func validEraID(_ id: UUID?) -> UUID? {
        guard let id, eras.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The events of one period, in date order. nil is the master.
    func events(in era: UUID?) -> [EvidenceEvent] {
        sortedEvents.filter { validEraID($0.eraID) == era }
    }
}
