// Quest text may use a little markup: <b>, <strong>, <i>, <em>, <code>, <br> and <span class="...">.
// Anything else is shown as plain text.
import Foundation

public struct RichRun: Hashable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var code = false
    public var classes: [String] = []
}

public enum Rich {
    public static func parse(_ html: String) -> [RichRun] {
        var runs: [RichRun] = []
        var stack: [(tag: String, classes: [String])] = []
        var buf = ""
        func style() -> RichRun {
            var r = RichRun(text: "")
            for s in stack {
                switch s.tag {
                case "b", "strong": r.bold = true
                case "i", "em": r.italic = true
                case "code": r.code = true
                case "span": r.classes += s.classes
                default: break
                }
            }
            return r
        }
        func flush() {
            guard !buf.isEmpty else { return }
            var r = style(); r.text = decode(buf); buf = ""
            if let last = runs.last, last.bold == r.bold, last.italic == r.italic, last.code == r.code, last.classes == r.classes {
                runs[runs.count - 1].text += r.text
            } else { runs.append(r) }
        }
        var i = html.startIndex
        while i < html.endIndex {
            if html[i] == "<", let close = html[i...].firstIndex(of: ">") {
                let inner = html[html.index(after: i)..<close].trimmingCharacters(in: .whitespaces)
                let closing = inner.hasPrefix("/")
                let body = closing ? String(inner.dropFirst()) : inner.hasSuffix("/") ? String(inner.dropLast()) : inner
                let name = body.split(whereSeparator: { $0 == " " }).first.map { $0.lowercased() } ?? ""
                if ["b", "strong", "i", "em", "code", "span", "br"].contains(name) {
                    flush()
                    if name == "br" { buf = "\n"; flush() }
                    else if closing { if let k = stack.lastIndex(where: { $0.tag == name }) { stack.remove(at: k) } }
                    else { stack.append((name, classAttribute(body))) }
                }
                i = html.index(after: close)
                continue
            }
            buf.append(html[i])
            i = html.index(after: i)
        }
        flush()
        return runs
    }

    public static func plain(_ html: String) -> String { parse(html).map(\.text).joined() }

    static func classAttribute(_ tag: String) -> [String] {
        guard let r = tag.range(of: "class=") else { return [] }
        var rest = tag[r.upperBound...]
        let quote = rest.first
        guard quote == "\"" || quote == "'" else { return [] }
        rest = rest.dropFirst()
        guard let end = rest.firstIndex(of: quote!) else { return [] }
        return rest[..<end].split(separator: " ").map(String.init)
    }

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}").replacingOccurrences(of: "&amp;", with: "&")
    }
}
