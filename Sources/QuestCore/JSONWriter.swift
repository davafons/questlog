// Writes project and settings files the way JSON.stringify(value, null, 2) does, with keys in a fixed order,
// so saving a file only changes what actually changed.
import Foundation

public indirect enum JSONValue {
    case string(String), int(Int), bool(Bool), null
    case array([JSONValue])
    case object([(String, JSONValue)])

    public func render(_ depth: Int = 0) -> String {
        let pad = String(repeating: "  ", count: depth + 1), end = String(repeating: "  ", count: depth)
        switch self {
        case .string(let s): return JSONValue.quote(s)
        case .int(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[\n" + items.map { pad + $0.render(depth + 1) }.joined(separator: ",\n") + "\n\(end)]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            return "{\n" + pairs.map { "\(pad)\(JSONValue.quote($0.0)): \($0.1.render(depth + 1))" }.joined(separator: ",\n") + "\n\(end)}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
}

public protocol JSONWritable { var json: JSONValue { get } }

private func opt(_ key: String, _ v: String?) -> [(String, JSONValue)] { v.map { [(key, .string($0))] } ?? [] }

extension Objective: JSONWritable {
    public var json: JSONValue { .object([("id", .string(id)), ("text", .string(text)), ("done", .bool(done))]) }
}

extension Quest: JSONWritable {
    public var json: JSONValue {
        var pairs: [(String, JSONValue)] = [
            ("id", .string(id)), ("chain", .string(chain)), ("title", .string(title)), ("lvl", .int(lvl)), ("who", .string(who)),
            ("where", .string(self.where)), ("req", .array(req.map { .string($0) })), ("lore", .string(lore)),
            ("desc", .array(desc.map { .string($0) })),
        ]
        pairs += opt("tip", tip)
        pairs += [("xp", .int(xp)), ("status", .string(status.rawValue)), ("obj", .array(obj.map(\.json)))]
        pairs += opt("created", created) + opt("completed", completed)
        return .object(pairs)
    }
}

extension Chain: JSONWritable {
    public var json: JSONValue { .object([("id", .string(id)), ("name", .string(name))]) }
}

extension Note: JSONWritable {
    public var json: JSONValue { .object([("title", .string(title))] + opt("sub", sub) + [("body", .array(body.map { .string($0) }))]) }
}

extension Project: JSONWritable {
    public var json: JSONValue {
        var pairs: [(String, JSONValue)] = [("slug", .string(slug)), ("title", .string(title))]
        pairs += opt("subtitle", subtitle)
        pairs += [("chains", .array(chains.map(\.json))), ("quests", .array(quests.map(\.json)))]
        if let notes { pairs.append(("notes", .array(notes.map(\.json)))) }
        return .object(pairs)
    }
}

extension Settings: JSONWritable {
    public var json: JSONValue { .object([("current", current.map { .string($0) } ?? .null), ("tracked", .array(tracked.map { .string($0) }))]) }
}
