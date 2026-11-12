import Foundation
import Observation
import XuejiCore

@Observable
final class ProjectsViewModel: IProjectsView, IProjectsController {
    private let store: AppStore

    /// Wired by the composition root: runs after another project is opened (to leave screens that belong to the old one).
    var didSwitch: () -> Void = {}

    init(store: AppStore) { self.store = store }

    // MARK: IProjectsView

    var projects: [ProjectInfo] {
        store.activeProjects.map { ProjectInfo(id: $0.id, name: $0.name, isCurrent: $0.id == store.trackID) }
    }

    var archived: [ProjectInfo] {
        store.archivedProjects.map { ProjectInfo(id: $0.id, name: $0.name, isCurrent: false) }
    }

    var current: ProjectInfo? { projects.first { $0.isCurrent } }
    var canArchive: Bool { store.activeProjects.count > 1 }

    // MARK: IProjectsController

    func select(id: UUID) {
        guard id != store.trackID else { return }
        store.selectProject(id)
        didSwitch()
    }

    func create(name: String) {
        store.addProject(named: name)
        didSwitch()
    }

    func rename(id: UUID, name: String) { store.renameProject(id, to: name) }

    func archive(id: UUID) {
        let wasCurrent = id == store.trackID
        store.archiveProject(id)
        if wasCurrent { didSwitch() }
    }

    func restore(id: UUID) {
        store.restoreProject(id)
        didSwitch()
    }
}
