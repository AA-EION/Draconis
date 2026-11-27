import Foundation

/// Valve's text KeyValues format (libraryfolders.vdf, appmanifest_*.acf,
/// config.vdf). Keys are matched case-insensitively, as Steam does.
public indirect enum VDF: Equatable, Sendable {
    case string(String)
    case object([(key: String, value: VDF)])

    public static func == (a: VDF, b: VDF) -> Bool {
        switch (a, b) {
        case let (.string(x), .string(y)): return x == y
        case let (.object(x), .object(y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    public subscript(key: String) -> VDF? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    public subscript(path: [String]) -> VDF? {
        path.reduce(Optional(self)) { $0?[$1] }
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var entries: [(key: String, value: VDF)] {
        if case .object(let pairs) = self { return pairs }
        return []
    }

    public static func parse(_ text: String) -> VDF? {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        return parser.parseObject(topLevel: true)
    }

    public static func load(_ url: URL) -> VDF? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var i = 0

        init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

        mutating func parseObject(topLevel: Bool) -> VDF? {
            var pairs: [(key: String, value: VDF)] = []
            while let token = nextToken() {
                switch token {
                case .close:
                    return topLevel ? nil : .object(pairs)
                case .open:
                    return nil
                case .text(let key):
                    guard let next = nextToken() else { return nil }
                    switch next {
                    case .text(let value): pairs.append((key, .string(value)))
                    case .open:
                        guard let child = parseObject(topLevel: false) else { return nil }
                        pairs.append((key, child))
                    case .close: return nil
                    }
                }
            }
            return topLevel ? .object(pairs) : nil
        }

        enum Token { case open, close, text(String) }

        mutating func nextToken() -> Token? {
            skipTrivia()
            guard i < scalars.count else { return nil }
            let c = scalars[i]
            if c == "{" { i += 1; return .open }
            if c == "}" { i += 1; return .close }
            if c == "\"" {
                i += 1
                var out = String.UnicodeScalarView()
                while i < scalars.count, scalars[i] != "\"" {
                    if scalars[i] == "\\", i + 1 < scalars.count {
                        i += 1
                        switch scalars[i] {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(scalars[i])
                        }
                    } else {
                        out.append(scalars[i])
                    }
                    i += 1
                }
                i += 1
                return .text(String(out))
            }
            var out = String.UnicodeScalarView()
            while i < scalars.count, !isSpace(scalars[i]), scalars[i] != "{", scalars[i] != "}", scalars[i] != "\"" {
                out.append(scalars[i]); i += 1
            }
            return .text(String(out))
        }

        mutating func skipTrivia() {
            while i < scalars.count {
                if isSpace(scalars[i]) { i += 1; continue }
                if scalars[i] == "/", i + 1 < scalars.count, scalars[i + 1] == "/" {
                    while i < scalars.count, scalars[i] != "\n" { i += 1 }
                    continue
                }
                if scalars[i] == "[" { // platform conditionals like [$WIN32]
                    while i < scalars.count, scalars[i] != "]" { i += 1 }
                    i += 1
                    continue
                }
                break
            }
        }

        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }
    }
}
