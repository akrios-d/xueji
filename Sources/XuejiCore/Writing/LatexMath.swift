import Foundation

/// Turns a formula written in LaTeX into Word's own equation markup (OMML), so it stays editable in Word.
/// It covers what an article needs: fractions, powers, indices, roots, sums and integrals, Greek letters, the usual
/// operators and relations, and text inside a formula. Anything it does not know is written as plain text.
public enum LatexMath {
    /// The inside of an `<m:oMath>` element.
    public static func omml(_ source: String) -> String {
        var parser = Parser(Array(source))
        return parser.sequence(until: nil)
    }

    // MARK: Tables

    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "cdot": "⋅", "times": "×", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗", "circ": "∘",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡",
        "sim": "∼", "propto": "∝", "ll": "≪", "gg": "≫",
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃", "emptyset": "∅",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "cup": "∪", "cap": "∩",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "mapsto": "↦", "ldots": "…", "cdots": "⋯", "dots": "…", "degree": "°",
        "neg": "¬", "land": "∧", "lor": "∨", "angle": "∠", "perp": "⊥", "hbar": "ℏ",
    ]
    private static let nary: [String: (String, Bool)] = [
        "sum": ("∑", true), "prod": ("∏", true), "int": ("∫", false), "iint": ("∬", false),
        "oint": ("∮", false), "bigcup": ("⋃", true), "bigcap": ("⋂", true),
    ]
    private static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "log", "ln", "exp", "lim", "max", "min", "sup", "inf", "det", "dim", "gcd", "arg", "Pr",
    ]
    private static let accents: [String: String] = ["hat": "\u{302}", "tilde": "\u{303}", "dot": "\u{307}", "vec": "\u{20D7}"]
    private static let spaces: Set<String> = [",", ";", ":", "!", " ", "quad", "qquad"]

    // MARK: Parser

    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { i >= chars.count }

        mutating func skipSpaces() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

        /// Reads items until the closing character (or the end), each with its indices.
        mutating func sequence(until close: Character?) -> String {
            var result = ""
            while true {
                skipSpaces()
                if atEnd { break }
                if let close, chars[i] == close { i += 1; break }
                result += scripted()
            }
            return result
        }

        mutating func scripted() -> String {
            var base = atom()
            var sub: String?
            var sup: String?
            while true {
                skipSpaces()
                guard !atEnd, chars[i] == "^" || chars[i] == "_" else { break }
                let isSup = chars[i] == "^"
                i += 1
                let argument = argumentXML()
                if isSup { sup = argument } else { sub = argument }
            }
            if sub != nil || sup != nil {
                switch (sub, sup) {
                case let (sub?, sup?): base = "<m:sSubSup><m:e>\(base)</m:e><m:sub>\(sub)</m:sub><m:sup>\(sup)</m:sup></m:sSubSup>"
                case let (sub?, nil): base = "<m:sSub><m:e>\(base)</m:e><m:sub>\(sub)</m:sub></m:sSub>"
                case let (nil, sup?): base = "<m:sSup><m:e>\(base)</m:e><m:sup>\(sup)</m:sup></m:sSup>"
                default: break
                }
            }
            return base
        }

        /// A `{group}` or a single item.
        mutating func argumentXML() -> String {
            skipSpaces()
            guard !atEnd else { return "" }
            if chars[i] == "{" { i += 1; return sequence(until: "}") }
            return atom()
        }

        /// The raw text of a `{group}` (for \text and friends).
        mutating func rawGroup() -> String {
            skipSpaces()
            guard !atEnd, chars[i] == "{" else { return "" }
            i += 1
            var depth = 1
            var text = ""
            while !atEnd {
                let ch = chars[i]; i += 1
                if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1; if depth == 0 { break } }
                text.append(ch)
            }
            return text
        }

        mutating func atom() -> String {
            skipSpaces()
            guard !atEnd else { return "" }
            let ch = chars[i]
            if ch == "{" { i += 1; return sequence(until: "}") }
            if ch == "\\" { i += 1; return command() }
            if ch.isNumber {
                var number = ""
                while !atEnd, chars[i].isNumber || (chars[i] == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                    number.append(chars[i]); i += 1
                }
                return run(number)
            }
            i += 1
            return run(String(ch))
        }

        mutating func command() -> String {
            guard !atEnd else { return "" }
            // A control symbol such as \, or \{ .
            if !chars[i].isLetter {
                let symbol = String(chars[i]); i += 1
                if LatexMath.spaces.contains(symbol) { return run("\u{2009}") }
                return run(symbol)
            }
            var name = ""
            while !atEnd, chars[i].isLetter { name.append(chars[i]); i += 1 }
            switch name {
            case "frac", "dfrac", "tfrac":
                let numerator = argumentXML(), denominator = argumentXML()
                return "<m:f><m:num>\(numerator)</m:num><m:den>\(denominator)</m:den></m:f>"
            case "sqrt":
                skipSpaces()
                var degree = ""
                if !atEnd, chars[i] == "[" {
                    i += 1
                    var raw = ""
                    while !atEnd, chars[i] != "]" { raw.append(chars[i]); i += 1 }
                    i += 1
                    var inner = Parser(Array(raw))
                    degree = inner.sequence(until: nil)
                }
                let body = argumentXML()
                if degree.isEmpty {
                    return "<m:rad><m:radPr><m:degHide m:val=\"1\"/></m:radPr><m:deg/><m:e>\(body)</m:e></m:rad>"
                }
                return "<m:rad><m:deg>\(degree)</m:deg><m:e>\(body)</m:e></m:rad>"
            case "text", "mathrm", "textrm", "operatorname", "mbox":
                return run(rawGroup(), style: "<m:rPr><m:nor/></m:rPr>")
            case "mathbf", "boldsymbol", "bm":
                return run(rawGroup(), style: "<m:rPr><m:sty m:val=\"b\"/></m:rPr>")
            case "mathbb":
                return run(LatexMath.blackboard(rawGroup()))
            case "left", "right", "big", "Big", "bigg", "Bigg":
                skipSpaces()
                guard !atEnd else { return "" }
                if chars[i] == "." { i += 1; return "" }
                if chars[i] == "\\" {
                    i += 1
                    let delimiter = command()
                    return delimiter
                }
                let delimiter = chars[i]; i += 1
                return run(String(delimiter))
            case "bar", "overline":
                return "<m:bar><m:barPr><m:pos m:val=\"top\"/></m:barPr><m:e>\(argumentXML())</m:e></m:bar>"
            case "underline":
                return "<m:bar><m:barPr><m:pos m:val=\"bot\"/></m:barPr><m:e>\(argumentXML())</m:e></m:bar>"
            case "lbrace": return run("{")
            case "rbrace": return run("}")
            case "langle": return run("⟨")
            case "rangle": return run("⟩")
            case "quad", "qquad", "space": return run("\u{2003}")
            default: break
            }
            if let accent = LatexMath.accents[name] {
                return "<m:acc><m:accPr><m:chr m:val=\"\(accent)\"/></m:accPr><m:e>\(argumentXML())</m:e></m:acc>"
            }
            if let (symbol, stacked) = LatexMath.nary[name] {
                var lower = "", upper = ""
                while true {
                    skipSpaces()
                    guard !atEnd, chars[i] == "^" || chars[i] == "_" else { break }
                    let isUpper = chars[i] == "^"
                    i += 1
                    let argument = argumentXML()
                    if isUpper { upper = argument } else { lower = argument }
                }
                let body = scripted()
                var properties = "<m:chr m:val=\"\(symbol)\"/><m:limLoc m:val=\"\(stacked ? "undOvr" : "subSup")\"/>"
                if lower.isEmpty { properties += "<m:subHide m:val=\"1\"/>" }
                if upper.isEmpty { properties += "<m:supHide m:val=\"1\"/>" }
                return "<m:nary><m:naryPr>\(properties)</m:naryPr><m:sub>\(lower)</m:sub><m:sup>\(upper)</m:sup><m:e>\(body)</m:e></m:nary>"
            }
            if LatexMath.functions.contains(name) { return run(name, style: "<m:rPr><m:nor/></m:rPr>") }
            if let symbol = LatexMath.symbols[name] { return run(symbol) }
            return run(name, style: "<m:rPr><m:nor/></m:rPr>")
        }

        func run(_ text: String, style: String = "") -> String {
            guard !text.isEmpty else { return "" }
            return "<m:r>\(style)<m:t xml:space=\"preserve\">\(DocxWriter.escape(text))</m:t></m:r>"
        }
    }

    private static func blackboard(_ letters: String) -> String {
        let map: [Character: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "E": "𝔼", "P": "ℙ"]
        return letters.map { map[$0] ?? String($0) }.joined()
    }
}
