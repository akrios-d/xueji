import Foundation
import XuejiCore

/// What the Converter screen may read.
protocol IConverterView {
    var input: String { get }
    var targetStyle: CitationStyle { get }
    var results: [ConvertedReference] { get }
}

/// What the Converter screen may trigger.
protocol IConverterController {
    func setInput(_ text: String)
    func setTargetStyle(_ style: CitationStyle)
    func copy(_ reference: ConvertedReference)
    func copyAll()
    func clear()
}

typealias IConverterViewModel = IConverterView & IConverterController
