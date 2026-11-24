// Quest model. One JSON file per project in ~/.questlog/projects/<slug>.json.
import Foundation

public let xpPerLevel = 400

/// Who a quest is for. Free-form in the files; these are the ones the app knows by name.
public let whoNames: [(id: String, name: String)] = [("you", "You"), ("claude", "Claude"), ("family", "Family / friend")]
public func whoName(_ id: String) -> String { whoNames.first { $0.id == id }?.name ?? id }

public struct Objective: Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var done: Bool
    public init(id: String, text: String, done: Bool = false) { self.id = id; self.text = text; self.done = done }
}

public enum QuestStatus: String, Codable, Sendable { case offered, active, declined, abandoned }

public struct Quest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var chain: String
    public var title: String
    public var lvl: Int
    public var who: String
    public var `where`: String
    public var req: [String]
    public var lore: String
    public var desc: [String]
    public var tip: String?
    public var xp: Int
    public var status: QuestStatus
    public var obj: [Objective]
    public var created: String?
    public var completed: String?

    public init(id: String, chain: String, title: String, lvl: Int = 1, who: String = "you", where: String = "Anywhere",
                req: [String] = [], lore: String = "", desc: [String] = [], tip: String? = nil, xp: Int = 100,
                status: QuestStatus = .active, obj: [Objective] = [], created: String? = nil, completed: String? = nil) {
        self.id = id; self.chain = chain; self.title = title; self.lvl = lvl; self.who = who; self.where = `where`
        self.req = req; self.lore = lore; self.desc = desc; self.tip = tip; self.xp = xp; self.status = status
        self.obj = obj; self.created = created; self.completed = completed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        chain = try c.decodeIfPresent(String.self, forKey: .chain) ?? ""
        title = try c.decode(String.self, forKey: .title)
        lvl = try c.decodeIfPresent(Int.self, forKey: .lvl) ?? 1
        who = try c.decodeIfPresent(String.self, forKey: .who) ?? "you"
        self.where = try c.decodeIfPresent(String.self, forKey: .where) ?? "Anywhere"
        req = try c.decodeIfPresent([String].self, forKey: .req) ?? []
        lore = try c.decodeIfPresent(String.self, forKey: .lore) ?? ""
        desc = try c.decodeIfPresent([String].self, forKey: .desc) ?? []
        tip = try c.decodeIfPresent(String.self, forKey: .tip)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 100
        status = try c.decodeIfPresent(QuestStatus.self, forKey: .status) ?? .active
        obj = try c.decodeIfPresent([Objective].self, forKey: .obj) ?? []
        created = try c.decodeIfPresent(String.self, forKey: .created)
        completed = try c.decodeIfPresent(String.self, forKey: .completed)
    }

    public var objDone: Int { obj.filter(\.done).count }
    public var isDone: Bool { !obj.isEmpty && obj.allSatisfy(\.done) }
    /// Declined and abandoned quests don't count toward XP or progress.
    var counts: Bool { status != .declined && status != .abandoned }
}

public struct Chain: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Note: Codable, Hashable, Sendable {
    public var title: String
    public var sub: String?
    public var body: [String]
    public init(title: String, sub: String? = nil, body: [String] = []) { self.title = title; self.sub = sub; self.body = body }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var slug: String
    public var title: String
    public var subtitle: String?
    public var chains: [Chain]
    public var quests: [Quest]
    public var notes: [Note]?
    public var id: String { slug }

    public init(slug: String, title: String, subtitle: String? = nil, chains: [Chain] = [], quests: [Quest] = [], notes: [Note]? = nil) {
        self.slug = slug; self.title = title; self.subtitle = subtitle; self.chains = chains; self.quests = quests; self.notes = notes
    }

    public func quest(_ id: String) -> Quest? { quests.first { $0.id == id } }
    public func chainName(_ id: String) -> String { chains.first { $0.id == id }?.name ?? id }
}

public struct Settings: Codable, Hashable, Sendable {
    public var current: String?
    public var tracked: [String]
    public init(current: String? = nil, tracked: [String] = []) { self.current = current; self.tracked = tracked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = try c.decodeIfPresent(String.self, forKey: .current)
        tracked = try c.decodeIfPresent([String].self, forKey: .tracked) ?? []
    }
}

// MARK: - Derived state

/// Where a quest stands, in the order the log checks it.
public enum QuestState: String, Sendable {
    case offered, declined, abandoned, done, locked, inProgress, available
    public var isClosed: Bool { self == .done || self == .declined || self == .abandoned }
    public var label: String {
        switch self {
        case .offered: "new"
        case .inProgress: "in progress"
        default: rawValue
        }
    }
}

/// WoW-style difficulty colour of a quest relative to the project's level.
public enum Difficulty: String, Sendable { case red, orange, yellow, green, gray }

public struct Totals: Hashable, Sendable {
    public var xp = 0, max = 0, done = 0, open = 0
    public init() {}
    public var total: Int { done + open }
    public var level: Int { xp / xpPerLevel + 1 }
    public var intoLevel: Int { xp % xpPerLevel }
}

public extension Project {
    func state(of q: Quest) -> QuestState {
        switch q.status {
        case .offered: return .offered
        case .declined: return .declined
        case .abandoned: return .abandoned
        case .active: break
        }
        if q.isDone { return .done }
        if q.req.contains(where: { r in quest(r).map { !$0.isDone } ?? false }) { return .locked }
        return q.objDone > 0 ? .inProgress : .available
    }

    var totals: Totals {
        var t = Totals()
        for q in quests where q.counts {
            t.max += q.xp
            let f = q.obj.isEmpty ? 0 : Double(q.objDone) / Double(q.obj.count)
            t.xp += Int((Double(q.xp) * f).rounded())
            if f == 1 { t.done += 1 } else { t.open += 1 }
        }
        return t
    }

    /// Chains whose counted quests are all done.
    var chainsDone: Int {
        chains.filter { c in
            let qs = quests.filter { $0.chain == c.id && $0.counts }
            return !qs.isEmpty && qs.allSatisfy(\.isDone)
        }.count
    }

    /// Quests this one waits for that aren't done yet.
    func missing(for q: Quest) -> [Quest] { q.req.compactMap { quest($0) }.filter { !$0.isDone } }
}

public func difficulty(_ q: Quest, level: Int) -> Difficulty {
    let d = q.lvl - level
    if d >= 5 { return .red }
    if d >= 3 { return .orange }
    if d >= -2 { return .yellow }
    if d >= -5 { return .green }
    return .gray
}

public struct QuestRef: Hashable, Sendable {
    public var project: Project
    public var quest: Quest
    public var ref: String { "\(project.slug)/\(quest.id)" }
}

/// What the tracker shows: the tracked quests, or the next few of the current project.
public func trackerList(_ projects: [Project], _ settings: Settings, limit: Int = 3) -> (auto: Bool, items: [QuestRef]) {
    let bySlug = Dictionary(projects.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    let tracked = settings.tracked.compactMap { ref -> QuestRef? in
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let p = bySlug[parts[0]], let q = p.quest(parts[1]) else { return nil }
        return QuestRef(project: p, quest: q)
    }
    if !tracked.isEmpty { return (false, tracked) }
    guard let p = settings.current.flatMap({ bySlug[$0] }) ?? projects.first else { return (true, []) }
    let pick = { (s: QuestState) in p.quests.filter { p.state(of: $0) == s }.map { QuestRef(project: p, quest: $0) } }
    return (true, Array((pick(.inProgress) + pick(.available)).prefix(limit)))
}

public func offers(_ projects: [Project]) -> [QuestRef] {
    projects.flatMap { p in p.quests.filter { $0.status == .offered }.map { QuestRef(project: p, quest: $0) } }
}

// MARK: - Ids

public func slugify(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en")).lowercased()
    var out = "", dash = false
    for ch in folded.unicodeScalars {
        if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) { out.unicodeScalars.append(ch); dash = false }
        else if !dash && !out.isEmpty { out += "-"; dash = true }
    }
    while out.hasSuffix("-") { out.removeLast() }
    let cut = String(out.prefix(40))
    let trimmed = cut.hasSuffix("-") ? String(cut.dropLast()) : cut
    return trimmed.isEmpty ? "quest" : trimmed
}

public func uniqueId(_ base: String, taken: Set<String>) -> String {
    let root = slugify(base)
    var id = root, n = 2
    while taken.contains(id) { id = "\(root)-\(n)"; n += 1 }
    return id
}
