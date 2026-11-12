import Foundation
import XuejiCore

extension AppStore {
    /// Every approved source of the track, as something that can be cited.
    func references() -> [Reference] {
        workspace.items.values
            .filter { $0.trackID == trackID && $0.kind == .source && $0.approval == .approved }
            .map { item in
                var authors = "", venue = "", doi = "", kind = ""
                var year: Int?
                if case .text(let value)? = item.values["authors"] { authors = value }
                if case .text(let value)? = item.values["venue"] { venue = value }
                if case .text(let value)? = item.values["doi"] { doi = value }
                if case .number(let value)? = item.values["year"] { year = Int(value) }
                if case .select(let value)? = item.values["sourceKind"] { kind = value }
                let address = item.url.flatMap { $0.isFileURL ? nil : $0.absoluteString } ?? ""
                return Reference(
                    id: item.id, authors: authors, year: year, title: item.title, venue: venue, doi: doi,
                    url: address, kind: kind, created: item.createdAt
                )
            }
    }
}
