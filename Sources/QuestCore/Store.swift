// Storage: ~/.questlog/projects/<slug>.json, ~/.questlog/settings.json, portraits/ and theme/.
// The app and the CLI change data only through Store.apply, so they stay consistent.
import Foundation

public struct QuestError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Op: Sendable {
    case objectives(ref: String, select: [String], done: Bool)
    case complete(String), accept(String), decline(String), abandon(String), restore(String), remove(String)
    case track(String, on: Bool)
    case current(String)
    case save(project: String, id: String?, draft: QuestDraft)
}

/// Quest fields the editor sends. Objectives keep their id (and done state) when they have one.
public struct QuestDraft: Sendable {
    public var title: String
    public var chain: String?
    public var chainName: String?
    public var lvl: Int?
    public var who: String?
    public var `where`: String?
    public var xp: Int?
    public var lore: String?
    public var desc: [String]?
    public var tip: String?
    public var obj: [(id: String?, text: String)]?
    public var status: QuestStatus?

    public init(title: String, chain: String? = nil, chainName: String? = nil, lvl: Int? = nil, who: String? = nil, where: String? = nil,
                xp: Int? = nil, lore: String? = nil, desc: [String]? = nil, tip: String? = nil, obj: [(id: String?, text: String)]? = nil,
                status: QuestStatus? = nil) {
        self.title = title; self.chain = chain; self.chainName = chainName; self.lvl = lvl; self.who = who; self.where = `where`
        self.xp = xp; self.lore = lore; self.desc = desc; self.tip = tip; self.obj = obj; self.status = status
    }
}

public final class Store: @unchecked Sendable {
    public let home: URL
    public var projectsDir: URL { home.appendingPathComponent("projects") }
    public var settingsFile: URL { home.appendingPathComponent("settings.json") }
    public var portraitsDir: URL { home.appendingPathComponent("portraits") }
    public var themeDir: URL { home.appendingPathComponent("theme") }

    /// ~/.questlog, or $QUESTLOG_HOME.
    public init(home: URL? = nil) {
        if let home { self.home = home }
        else if let env = ProcessInfo.processInfo.environment["QUESTLOG_HOME"], !env.isEmpty { self.home = URL(fileURLWithPath: (env as NSString).expandingTildeInPath) }
        else { self.home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".questlog") }
        for d in [self.home, projectsDir, portraitsDir, themeDir.appendingPathComponent("textures"), themeDir.appendingPathComponent("sounds"), themeDir.appendingPathComponent("fonts")] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    // MARK: Files

    private func write(_ value: JSONWritable, to url: URL) throws {
        try Data((value.json.render() + "\n").utf8).write(to: url, options: .atomic)
    }

    public func listProjects() -> [Project] {
        let files = (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? JSONDecoder().decode(Project.self, from: Data(contentsOf: $0)) }
    }

    public func loadProject(_ slug: String) throws -> Project {
        let url = projectsDir.appendingPathComponent("\(slug).json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw QuestError("No project \"\(slug)\". Run: quest projects") }
        do { return try JSONDecoder().decode(Project.self, from: Data(contentsOf: url)) }
        catch { throw QuestError("Could not read \(url.path): \(error.localizedDescription)") }
    }

    public func saveProject(_ p: Project) throws { try write(p, to: projectsDir.appendingPathComponent("\(p.slug).json")) }

    public func projectExists(_ slug: String) -> Bool { FileManager.default.fileExists(atPath: projectsDir.appendingPathComponent("\(slug).json").path) }

    public func loadSettings() -> Settings {
        var s = (try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsFile))) ?? Settings()
        if s.current.map({ !projectExists($0) }) ?? true { s.current = listProjects().first?.slug }
        return s
    }

    public func saveSettings(_ s: Settings) throws { try write(s, to: settingsFile) }

    /// Changes whenever a project or the settings file changes on disk; cheap enough to poll.
    public func signature() -> String {
        let fm = FileManager.default
        var parts: [String] = []
        for dir in [projectsDir, portraitsDir] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            for f in files.sorted(by: { $0.path < $1.path }) {
                let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                parts.append("\(f.lastPathComponent):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(v?.fileSize ?? 0)")
            }
        }
        let sv = try? settingsFile.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        parts.append("settings:\(sv?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(sv?.fileSize ?? 0)")
        return parts.joined(separator: "|")
    }

    // MARK: Lookups

    /// "slug/id", or a bare id looked up in the current project first, then everywhere, then by title.
    public func resolve(_ ref: String, prefer: String? = nil) throws -> (Project, Quest) {
        if ref.contains("/") {
            let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
            let p = try loadProject(parts[0])
            guard let q = p.quest(parts[1]) else { throw QuestError("No quest \"\(parts[1])\" in \(parts[0])") }
            return (p, q)
        }
        let order = listProjects().sorted { ($0.slug == prefer ? 0 : 1) < ($1.slug == prefer ? 0 : 1) }
        let hits = order.flatMap { p in p.quests.filter { $0.id == ref }.map { (p, $0) } }
        if hits.isEmpty {
            let needle = ref.lowercased()
            let fuzzy = order.flatMap { p in p.quests.filter { $0.title.lowercased().contains(needle) }.map { (p, $0) } }
            if fuzzy.count == 1 { return fuzzy[0] }
            if fuzzy.count > 1 { throw QuestError("\"\(ref)\" matches several quests: \(fuzzy.map { "\($0.0.slug)/\($0.1.id)" }.joined(separator: ", "))") }
            throw QuestError("No quest matches \"\(ref)\"")
        }
        if hits.count > 1 && hits[0].0.slug != prefer {
            throw QuestError("\"\(ref)\" exists in several projects: \(hits.map { "\($0.0.slug)/\($0.1.id)" }.joined(separator: ", "))")
        }
        return hits[0]
    }

    /// Objective selector: ids, 1-based numbers, or "all". Returns indexes into q.obj.
    public static func pickObjectives(_ q: Quest, _ select: [String]) throws -> [Int] {
        if select.contains("all") { return Array(q.obj.indices) }
        return try select.map { s in
            if let n = Int(s), n >= 1, n <= q.obj.count { return n - 1 }
            if let i = q.obj.firstIndex(where: { $0.id == s }) { return i }
            throw QuestError("Quest \"\(q.id)\" has no objective \"\(s)\"")
        }
    }

    // MARK: Changes

    @discardableResult
    public func apply(_ op: Op) throws -> (Project, Quest)? {
        var settings = loadSettings()
        if case .current(let slug) = op {
            _ = try loadProject(slug)
            settings.current = slug
            try saveSettings(settings)
            return nil
        }
        if case .save(let slug, let id, let draft) = op {
            var p = try loadProject(slug)
            let wasDone = id.flatMap { p.quest($0) }?.isDone ?? false
            let saved = try Store.saveQuest(&p, draft, id: id)
            if let i = p.quests.firstIndex(where: { $0.id == saved }) {
                if !wasDone && p.quests[i].isDone { p.quests[i].completed = Store.now() }
                if wasDone && !p.quests[i].isDone { p.quests[i].completed = nil }
            }
            try saveProject(p)
            return (p, p.quest(saved)!)
        }

        let ref: String
        switch op {
        case .objectives(let r, _, _), .complete(let r), .accept(let r), .decline(let r), .abandon(let r), .restore(let r), .remove(let r), .track(let r, _): ref = r
        case .current, .save: fatalError("handled above")
        }
        var (p, q) = try resolve(ref, prefer: settings.current)
        let full = "\(p.slug)/\(q.id)"
        guard let i = p.quests.firstIndex(where: { $0.id == q.id }) else { throw QuestError("No quest \(full)") }
        let wasDone = q.isDone
        switch op {
        case .objectives(_, let select, let done):
            for k in try Store.pickObjectives(q, select) { p.quests[i].obj[k].done = done }
        case .complete:
            for k in p.quests[i].obj.indices { p.quests[i].obj[k].done = true }
            if p.quests[i].status == .offered { p.quests[i].status = .active }
        case .accept: p.quests[i].status = .active
        case .decline: p.quests[i].status = .declined
        case .abandon:
            p.quests[i].status = .abandoned
            settings.tracked.removeAll { $0 == full }
        case .restore: p.quests[i].status = .active
        case .track(_, let on):
            settings.tracked.removeAll { $0 == full }
            if on { settings.tracked.append(full) }
        case .remove:
            p.quests.remove(at: i)
            for k in p.quests.indices { p.quests[k].req.removeAll { $0 == q.id } }
            settings.tracked.removeAll { $0 == full }
            try saveProject(p); try saveSettings(settings)
            return (p, q)
        case .current, .save: break
        }
        q = p.quests[i]
        if !wasDone && q.isDone {
            p.quests[i].completed = Store.now()
            settings.tracked.removeAll { $0 == full }
        }
        if wasDone && !q.isDone { p.quests[i].completed = nil }
        try saveProject(p)
        try saveSettings(settings)
        return (p, p.quests[i])
    }

    static func now() -> String { ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds]) }

    /// Creates a quest (no id) or updates one from a draft. Returns the quest's id.
    public static func saveQuest(_ p: inout Project, _ d: QuestDraft, id: String?) throws -> String {
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw QuestError("A quest needs a title") }
        var i: Int
        if let id {
            guard let found = p.quests.firstIndex(where: { $0.id == id }) else { throw QuestError("No quest \"\(id)\" in \(p.slug)") }
            i = found
        } else {
            let q = Quest(id: uniqueId(title, taken: Set(p.quests.map(\.id))), chain: "", title: title, lvl: max(1, p.totals.level),
                          status: d.status ?? .active, created: now())
            p.quests.append(q)
            i = p.quests.count - 1
        }
        if let name = d.chainName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            if let found = p.chains.first(where: { $0.name.lowercased() == name.lowercased() }) { p.quests[i].chain = found.id }
            else {
                let cid = uniqueId(name, taken: Set(p.chains.map(\.id)))
                p.chains.append(Chain(id: cid, name: name))
                p.quests[i].chain = cid
            }
        } else if let chain = d.chain {
            guard p.chains.contains(where: { $0.id == chain }) else { throw QuestError("No chain \"\(chain)\" in \(p.slug). Add it: quest chain add <name> --id \(chain)") }
            p.quests[i].chain = chain
        }
        if p.quests[i].chain.isEmpty {
            if p.chains.isEmpty { p.chains.append(Chain(id: "main", name: "Main Quests")) }
            p.quests[i].chain = p.chains[0].id
        }
        p.quests[i].title = title
        if let v = d.lvl { p.quests[i].lvl = max(1, v) }
        if let v = d.xp { p.quests[i].xp = max(0, v) }
        if let v = d.who, !v.isEmpty { p.quests[i].who = v }
        if let v = d.where { let w = v.trimmingCharacters(in: .whitespaces); p.quests[i].where = w.isEmpty ? "Anywhere" : w }
        if let v = d.lore { p.quests[i].lore = v.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let v = d.desc { p.quests[i].desc = v.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        if let v = d.tip { let t = v.trimmingCharacters(in: .whitespacesAndNewlines); p.quests[i].tip = t.isEmpty ? nil : t }
        if let objs = d.obj {
            let old = Dictionary(p.quests[i].obj.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var taken = Set<String>()
            p.quests[i].obj = objs.compactMap { o in
                let text = o.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let prev = o.id.flatMap { old[$0] }
                let oid = prev.map(\.id).flatMap { taken.contains($0) ? nil : $0 } ?? uniqueId(text, taken: taken.union(old.keys))
                taken.insert(oid)
                return Objective(id: oid, text: text, done: prev?.done ?? false)
            }
        }
        if p.quests[i].obj.isEmpty { p.quests[i].obj = [Objective(id: "do", text: p.quests[i].title)] }
        return p.quests[i].id
    }

    // MARK: Portraits and theme

    public static let portraitExtensions = ["png", "jpg", "jpeg", "gif", "webp"]

    public func portrait(for slug: String) -> URL? {
        Store.portraitExtensions.map { portraitsDir.appendingPathComponent("\(slug).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Copies an image as the project's portrait, or removes it (nil).
    public func setPortrait(_ slug: String, from source: URL?) throws {
        _ = try loadProject(slug)
        for e in Store.portraitExtensions { try? FileManager.default.removeItem(at: portraitsDir.appendingPathComponent("\(slug).\(e)")) }
        guard let source else { return }
        let ext = source.pathExtension.lowercased()
        guard Store.portraitExtensions.contains(ext) else { throw QuestError("Pick a PNG, JPEG, GIF or WebP image") }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 5_000_000 else { throw QuestError("That image is over 5 MB") }
        try FileManager.default.copyItem(at: source, to: portraitsDir.appendingPathComponent("\(slug).\(ext)"))
    }

    /// Files in theme/<dir> by name without extension.
    public func themeFiles(_ dir: String, extensions: [String]) -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: themeDir.appendingPathComponent(dir), includingPropertiesForKeys: nil)) ?? []
        var out: [String: URL] = [:]
        for f in files where extensions.contains(f.pathExtension.lowercased()) { out[f.deletingPathExtension().lastPathComponent] = f }
        return out
    }
}
