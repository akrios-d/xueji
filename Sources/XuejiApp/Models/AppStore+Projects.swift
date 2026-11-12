import Foundation
import XuejiCore

/// Several projects (tracks) in one workspace: switching, creating, renaming, archiving and copying cards between them.
extension AppStore {
    var activeProjects: [Track] {
        workspace.tracks.values.filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var archivedProjects: [Track] {
        workspace.tracks.values.filter(\.isArchived)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The other projects in use, as targets for "Copy to project".
    var otherProjects: [ProjectInfo] {
        activeProjects.filter { $0.id != trackID }.map { ProjectInfo(id: $0.id, name: $0.name, isCurrent: false) }
    }

    /// Makes another project the one on screen. Undo history is per session of one project, so it starts over.
    func selectProject(_ id: UUID) {
        guard id != trackID, let track = workspace.tracks[id], !track.isArchived else { return }
        switchTrack(to: id)
    }

    /// Creates a project and opens it.
    func addProject(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let track = Track(name: clean)
        perform(L("undo.addProject")) { ws in ws.addTrack(track) }
        switchTrack(to: track.id)
    }

    func renameProject(_ id: UUID, to name: String) {
        perform(L("undo.rename")) { ws in try ws.renameTrack(id, to: name) }
    }

    func archiveProject(_ id: UUID) {
        guard activeProjects.count > 1 else { return }
        perform(L("undo.archiveProject")) { ws in try ws.setTrackArchived(id, true) }
        if id == trackID, let other = activeProjects.first(where: { $0.id != id }) { switchTrack(to: other.id) }
    }

    func restoreProject(_ id: UUID) {
        perform(L("undo.restoreProject")) { ws in try ws.setTrackArchived(id, false) }
        switchTrack(to: id)
    }

    /// A new card in another project with the same content (and the same PDF, which is not duplicated).
    /// Links to other cards are not carried over, since those cards stay in this project.
    func copyCard(_ id: UUID, toProject target: UUID) {
        guard let item = workspace.items[id], let track = workspace.tracks[target], target != item.trackID else { return }
        let values = item.values.filter { entry in
            if case .relation = entry.value { return false }
            return true
        }
        perform(L("undo.copyCard")) { ws in
            let copy = try ws.createItem(
                trackID: target, typeID: item.typeID, title: item.title, details: item.details, url: item.url,
                classification: item.classification, values: values, by: meID
            )
            if !item.notes.isEmpty { _ = try ws.setNotes(itemID: copy.id, to: item.notes, by: meID) }
        }
        announce(Lf("project.copied", item.title, track.name))
    }
}
