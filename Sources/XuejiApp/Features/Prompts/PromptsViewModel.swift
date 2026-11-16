import AppKit
import Observation

@Observable
final class PromptsViewModel: IPromptsView, IPromptsController {
    private(set) var copiedID: String?
    @ObservationIgnored private var reset: Task<Void, Never>?

    var prompts: [PromptTemplate] { PromptLibrary.all }

    func copy(_ prompt: PromptTemplate) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.text, forType: .string)
        copiedID = prompt.id
        reset?.cancel()
        reset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.copiedID = nil }
        }
    }
}
