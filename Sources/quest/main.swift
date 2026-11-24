// quest: command-line access to the quest log. Same data as the app (~/.questlog).
import Foundation
import QuestCore

let store = Store()
let color = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

func paint(_ code: String) -> (String) -> String { { color ? "\u{1B}[\(code)m\($0)\u{1B}[0m" : $0 } }
let gold = paint("38;2;255;209;0"), white = paint("97"), gray = paint("90"), green = paint("38;2;64;192;64")
let yellow = paint("38;2;255;255;0"), orange = paint("38;2;255;128;64"), red = paint("38;2;255;32;32"), purple = paint("38;2;183;124;255")
let bold = paint("1"), dim = paint("2")

func tint(_ d: Difficulty) -> (String) -> String {
    switch d { case .red: red; case .orange: orange; case .yellow: yellow; case .green: green; case .gray: gray }
}
func icon(_ s: QuestState) -> String {
    switch s {
    case .offered, .available: gold("!")
    case .inProgress: white("?")
    case .done: gold("✓")
    case .locked: gray("◆")
    case .declined, .abandoned: gray("×")
    }
}

let help = """
quest — track projects as WoW-style quests (data in \(store.home.path))

  quest                         next quests in the current project
  quest projects                list projects (* = current)
  quest use <project>           switch the current project
  quest project new <slug> <title> [--subtitle text]
  quest chain add <name> [--id id] [-p project]

  quest ls [--all] [--locked] [-p project] [--chain id]
  quest show <quest>
  quest add <title> [options]   offers a new quest (the app pops a quest window)
      -p project  --chain id  --lvl n  --who you|claude|family  --where text  --xp n
      --req quest (repeatable)  --obj text (repeatable)  --desc text (repeatable)
      --lore text  --tip text  --active (skip the accept window)
  quest edit <quest> [same options; --obj adds objectives]
  quest check <quest> <obj...>  mark objectives done (id, number or "all")
  quest uncheck <quest> <obj...>
  quest complete <quest>
  quest accept|decline|abandon|restore <quest>
  quest track|untrack <quest>
  quest rm <quest>
  quest json [-p project]       raw project JSON
  quest open [<quest>]          open the quest log app
  quest mcp                     run as an MCP server for agents (stdio)

<quest> is an id, project/id, or a unique part of the title.
"""

struct Flags {
    var args: [String] = []
    var values: [String: String] = [:]
    var lists: [String: [String]] = [:]
    var bools: Set<String> = []
    func value(_ k: String) -> String? { values[k] }
    func has(_ k: String) -> Bool { bools.contains(k) }
}

func parse(_ argv: [String]) throws -> Flags {
    var f = Flags()
    let multi: Set = ["obj", "desc", "req"], bool: Set = ["all", "active", "locked", "help"]
    var i = 0
    func next(_ name: String) throws -> String {
        i += 1
        guard i < argv.count else { throw QuestError("\(name) needs a value") }
        return argv[i]
    }
    while i < argv.count {
        let a = argv[i]
        if a == "-p" { f.values["project"] = try next(a) }
        else if a == "-h" { f.bools.insert("help") }
        else if a.hasPrefix("--") {
            let k = String(a.dropFirst(2))
            if bool.contains(k) { f.bools.insert(k) }
            else if multi.contains(k) { f.lists[k, default: []].append(try next(a)) }
            else { f.values[k] = try next(a) }
        } else { f.args.append(a) }
        i += 1
    }
    return f
}

func projectOf(_ f: Flags) throws -> Project {
    guard let slug = f.value("project") ?? store.loadSettings().current else { throw QuestError("No projects yet. Create one: quest project new <slug> <title>") }
    return try store.loadProject(slug)
}

func line(_ p: Project, _ q: Quest, _ level: Int) -> String {
    let s = p.state(of: q)
    let t = [.done, .locked, .declined, .abandoned].contains(s) ? gray : tint(difficulty(q, level: level))
    let prog = q.obj.isEmpty ? "" : dim(" \(q.objDone)/\(q.obj.count)")
    let who = q.who == "claude" ? purple(" [Claude]") : q.who == "family" ? dim(" [family]") : ""
    let tag = s == .offered ? gold(" (new)") : s == .locked ? gray(" (locked)") : s == .abandoned ? gray(" (abandoned)") : ""
    let lvl = String(q.lvl).count < 2 ? " \(q.lvl)" : "\(q.lvl)"
    return "  \(icon(s)) \(dim("[\(lvl)]")) \(t(q.title))\(prog)\(who)\(tag) \(dim(q.id))"
}

func header(_ p: Project) -> String {
    let t = p.totals
    let filled = Int((Double(t.intoLevel) / Double(xpPerLevel) * 20).rounded())
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
    return "\(gold(bold(p.title))) \(dim("(\(p.slug))"))  Level \(t.level)  \(purple(bar)) \(t.intoLevel)/\(xpPerLevel) XP  ·  \(t.done)/\(t.total) quests"
}

func list(_ p: Project, _ f: Flags) {
    let level = p.totals.level
    print(header(p))
    for c in p.chains {
        if let only = f.value("chain"), c.id != only { continue }
        let qs = p.quests.filter { $0.chain == c.id }.filter { q in
            let s = p.state(of: q)
            if f.has("all") { return true }
            if s.isClosed { return false }
            return f.has("locked") || s != .locked
        }
        if qs.isEmpty { continue }
        print("\n \(gold(c.name))")
        qs.forEach { print(line(p, $0, level)) }
    }
}

func show(_ p: Project, _ q: Quest) {
    let level = p.totals.level, s = p.state(of: q)
    print("\(gold(bold(q.title)))  \(dim("\(p.slug)/\(q.id)"))")
    print(dim("Level \(q.lvl) · \(whoName(q.who)) · \(q.where) · \(p.chainName(q.chain)) · \(s.label)"))
    let missing = p.missing(for: q)
    if !missing.isEmpty { print(red("Requires: \(missing.map(\.id).joined(separator: ", "))")) }
    print("\n\(gold("Quest Objectives"))")
    for (i, o) in q.obj.enumerated() {
        let text = Rich.plain(o.text)
        print("  \(o.done ? green("✓") : "-") \(dim("\(i + 1).")) \(o.done ? gray(text) : text) \(dim(o.id))")
    }
    print("\n\(gold("Description"))")
    if !q.lore.isEmpty { print(dim("  “\(q.lore)”")) }
    q.desc.forEach { print("  \(Rich.plain($0))") }
    if let tip = q.tip { print("  \(yellow("Tip:")) \(Rich.plain(tip))") }
    print("\n\(gold("Rewards"))  \(purple("\(q.xp) XP"))   \(dim("difficulty: \(difficulty(q, level: level).rawValue)"))")
}

/// Applies --flags to a quest. --obj appends objectives and --req adds requirements.
func applyFields(_ p: inout Project, _ i: Int, _ f: Flags) throws {
    if let v = f.value("title") { p.quests[i].title = v }
    if let v = f.value("chain") {
        guard p.chains.contains(where: { $0.id == v }) else { throw QuestError("No chain \"\(v)\" in \(p.slug). Add it: quest chain add <name> --id \(v)") }
        p.quests[i].chain = v
    }
    if let v = f.value("lvl") { guard let n = Int(v) else { throw QuestError("--lvl needs a number") }; p.quests[i].lvl = n }
    if let v = f.value("xp") { guard let n = Int(v) else { throw QuestError("--xp needs a number") }; p.quests[i].xp = n }
    if let v = f.value("who") { p.quests[i].who = v }
    if let v = f.value("where") { p.quests[i].where = v }
    if let v = f.value("lore") { p.quests[i].lore = v }
    if let v = f.value("tip") { p.quests[i].tip = v }
    if let v = f.lists["desc"] { p.quests[i].desc = v }
    if let reqs = f.lists["req"] {
        for r in reqs where p.quest(r) == nil { throw QuestError("No quest \"\(r)\" in \(p.slug)") }
        for r in reqs where !p.quests[i].req.contains(r) { p.quests[i].req.append(r) }
    }
    if let objs = f.lists["obj"] {
        var taken = Set(p.quests[i].obj.map(\.id))
        for text in objs {
            let id = uniqueId(text, taken: taken)
            taken.insert(id)
            p.quests[i].obj.append(Objective(id: id, text: text))
        }
    }
}

func run() throws {
    let f = try parse(Array(CommandLine.arguments.dropFirst()))
    let cmd = f.args.first, rest = Array(f.args.dropFirst())
    if f.has("help") || cmd == "help" { print(help); return }
    let settings = store.loadSettings()
    func need(_ n: Int, _ usage: String) throws { if rest.count < n { throw QuestError("Usage: \(usage)") } }

    switch cmd {
    case nil:
        let p = try projectOf(f)
        print(header(p))
        let mine = Settings(current: p.slug, tracked: settings.tracked.filter { $0.hasPrefix(p.slug + "/") })
        let items = trackerList([p], mine, limit: 5).items
        let offered = p.quests.filter { $0.status == .offered }
        if !offered.isEmpty {
            print("\n \(gold("New quests waiting to be accepted"))")
            offered.forEach { print(line(p, $0, p.totals.level)) }
        }
        print("\n \(gold("Next up"))")
        for item in items {
            print(line(p, item.quest, p.totals.level))
            item.quest.obj.filter { !$0.done }.prefix(4).forEach { print("      - \(Rich.plain($0.text))") }
        }
        if items.isEmpty { print(dim("  Nothing open. Add a quest: quest add <title>")) }
    case "projects":
        for p in store.listProjects() {
            let t = p.totals
            print("\(p.slug == settings.current ? gold("*") : " ") \(gold(p.title)) \(dim(p.slug))  Lv \(t.level) · \(t.done)/\(t.total) quests")
        }
    case "use":
        try need(1, "quest use <project>")
        try store.apply(.current(rest[0]))
        print("Current project: \(rest[0])")
    case "project":
        guard rest.first == "new", rest.count >= 3 else { throw QuestError("Usage: quest project new <slug> <title>") }
        let slug = slugify(rest[1])
        if store.projectExists(slug) { throw QuestError("Project \"\(slug)\" already exists") }
        try store.saveProject(Project(slug: slug, title: rest[2], subtitle: f.value("subtitle") ?? "", chains: [Chain(id: "main", name: "Main Quests")], notes: []))
        if settings.current == nil { try store.apply(.current(slug)) }
        print("Created project \(slug) with chain \"main\". Switch to it: quest use \(slug)")
    case "chain":
        guard rest.first == "add", rest.count >= 2 else { throw QuestError("Usage: quest chain add <name> [--id id]") }
        var p = try projectOf(f)
        let id = f.value("id") ?? uniqueId(rest[1], taken: Set(p.chains.map(\.id)))
        p.chains.append(Chain(id: id, name: rest[1]))
        try store.saveProject(p)
        print("Added chain \(id) to \(p.slug)")
    case "ls": list(try projectOf(f), f)
    case "show":
        try need(1, "quest show <quest>")
        let (p, q) = try store.resolve(rest[0], prefer: settings.current)
        show(p, q)
    case "json":
        print(try projectOf(f).json.render())
    case "add":
        try need(1, "quest add <title> [options]")
        var p = try projectOf(f)
        if p.chains.isEmpty { p.chains.append(Chain(id: "main", name: "Main Quests")) }
        let id = f.value("id") ?? uniqueId(rest[0], taken: Set(p.quests.map(\.id)))
        if p.quest(id) != nil { throw QuestError("Quest \"\(id)\" already exists in \(p.slug)") }
        p.quests.append(Quest(id: id, chain: p.chains[0].id, title: rest[0], lvl: max(1, p.totals.level),
                              status: f.has("active") ? .active : .offered, created: ISO8601DateFormatter().string(from: Date())))
        try applyFields(&p, p.quests.count - 1, f)
        if p.quests[p.quests.count - 1].obj.isEmpty { p.quests[p.quests.count - 1].obj = [Objective(id: "do", text: rest[0])] }
        try store.saveProject(p)
        print("\(f.has("active") ? "Added" : "Offered") \(gold(rest[0])) \(dim("\(p.slug)/\(id)"))")
    case "edit":
        try need(1, "quest edit <quest> [options]")
        let (found, q) = try store.resolve(rest[0], prefer: settings.current)
        var p = try store.loadProject(found.slug)
        guard let i = p.quests.firstIndex(where: { $0.id == q.id }) else { throw QuestError("No quest \(q.id)") }
        try applyFields(&p, i, f)
        try store.saveProject(p)
        print("Updated \(p.slug)/\(q.id)")
    case "check", "uncheck":
        try need(2, "quest \(cmd!) <quest> <obj...>")
        let (p0, q0) = try store.resolve(rest[0], prefer: settings.current)
        guard let (_, q) = try store.apply(.objectives(ref: "\(p0.slug)/\(q0.id)", select: Array(rest.dropFirst()), done: cmd == "check")) else { return }
        print("\(q.title): \(q.objDone)/\(q.obj.count)")
        if !q0.isDone && q.isDone { print(gold("\(q.title) completed. Experience gained: \(q.xp)")) }
    case "complete", "accept", "decline", "abandon", "restore":
        try need(1, "quest \(cmd!) <quest>")
        let r = rest[0]
        let op: Op = switch cmd! { case "complete": .complete(r); case "accept": .accept(r); case "decline": .decline(r); case "abandon": .abandon(r); default: .restore(r) }
        guard let (_, q) = try store.apply(op) else { return }
        print("\(cmd!.prefix(1).uppercased() + cmd!.dropFirst()): \(q.title)")
    case "track", "untrack":
        try need(1, "quest \(cmd!) <quest>")
        guard let (_, q) = try store.apply(.track(rest[0], on: cmd == "track")) else { return }
        print("\(cmd == "track" ? "Tracking" : "Stopped tracking") \(q.title)")
    case "rm":
        try need(1, "quest rm <quest>")
        guard let (p, q) = try store.apply(.remove(rest[0])) else { return }
        print("Removed \(p.slug)/\(q.id)")
    case "mcp": runMCP()
    case "open":
        var url = "questlog://open"
        if let r = rest.first {
            let (p, q) = try store.resolve(r, prefer: settings.current)
            url += "/\(p.slug)/\(q.id)"
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url]
        try task.run(); task.waitUntilExit()
    default:
        print(help)
        exit(1)
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data((red(error.localizedDescription) + "\n").utf8))
    exit(1)
}
