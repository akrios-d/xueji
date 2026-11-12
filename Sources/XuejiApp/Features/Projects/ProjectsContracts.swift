import Foundation

/// A project: a dissertation, an article, anything with its own board, library, drafts and compilation.
struct ProjectInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isCurrent: Bool
}

/// What the project switcher may read.
protocol IProjectsView {
    /// The projects in use, by name.
    var projects: [ProjectInfo] { get }
    var archived: [ProjectInfo] { get }
    var current: ProjectInfo? { get }
    /// The last project in use cannot be archived.
    var canArchive: Bool { get }
}

/// What the project switcher may trigger.
protocol IProjectsController {
    func select(id: UUID)
    func create(name: String)
    func rename(id: UUID, name: String)
    func archive(id: UUID)
    func restore(id: UUID)
}

typealias IProjectsViewModel = IProjectsView & IProjectsController
