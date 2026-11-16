import AppKit
import Observation
import XuejiCore

@Observable
final class LinksViewModel: ILinksView, ILinksController {
    private let checker: LinkChecker
    @ObservationIgnored private var job: Task<Void, Never>?

    private(set) var input = ""
    private(set) var tasks: [LinkTask] = []
    private(set) var offlineCount = 0
    private(set) var isChecking = false

    private let network: NetworkMonitor

    init(checker: LinkChecker = LinkChecker(), network: NetworkMonitor = .shared) {
        self.checker = checker
        self.network = network
    }

    var isOnline: Bool { network.isOnline }

    var doneCount: Int { tasks.filter(\.isDone).count }

    func setInput(_ text: String) { input = text }

    func check() {
        guard network.isOnline else { return }
        let found = LinkExtractor.links(in: input)
        offlineCount = found.offline
        tasks = found.online.map { LinkTask(id: $0.number, text: $0.text, url: $0.url) }
        run(ids: tasks.map(\.id))
    }

    func recheckOpen() {
        guard network.isOnline else { return }
        run(ids: tasks.filter { !$0.isDone }.map(\.id))
    }

    func toggleConfirmed(_ id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].confirmedByHand.toggle()
    }

    func openLink(_ id: Int) {
        if let task = tasks.first(where: { $0.id == id }) { NSWorkspace.shared.open(task.url) }
    }

    func clear() {
        job?.cancel()
        input = ""
        tasks = []
        offlineCount = 0
        isChecking = false
    }

    // MARK: Private

    /// Visits the links a few at a time, so a long list neither waits for each one nor floods the network.
    private func run(ids: [Int]) {
        job?.cancel()
        guard !ids.isEmpty else { isChecking = false; return }
        for id in ids { setStatus(.checking, for: id) }
        isChecking = true
        job = Task { @MainActor [checker, weak self] in
            let wanted: [(Int, URL)] = (self?.tasks ?? []).filter { ids.contains($0.id) }.map { ($0.id, $0.url) }
            for start in stride(from: 0, to: wanted.count, by: 4) {
                let chunk = wanted[start..<min(start + 4, wanted.count)]
                let answers = await withTaskGroup(of: (Int, LinkStatus).self) { group -> [(Int, LinkStatus)] in
                    for (id, url) in chunk { group.addTask { (id, await checker.check(url)) } }
                    var all: [(Int, LinkStatus)] = []
                    for await answer in group { all.append(answer) }
                    return all
                }
                guard !Task.isCancelled, let self else { return }
                for (id, status) in answers { self.setStatus(status, for: id) }
            }
            self?.isChecking = false
        }
    }

    private func setStatus(_ status: LinkStatus, for id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
    }
}
