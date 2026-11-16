import Foundation

/// What the Prompts screen may read.
protocol IPromptsView {
    var prompts: [PromptTemplate] { get }
    /// The prompt that was just copied, for a moment, so its button can say so.
    var copiedID: String? { get }
}

/// What the Prompts screen may trigger.
protocol IPromptsController {
    func copy(_ prompt: PromptTemplate)
}

typealias IPromptsViewModel = IPromptsView & IPromptsController
