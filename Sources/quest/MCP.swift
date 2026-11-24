// `quest mcp`: a Model Context Protocol server over stdio, so agents can read and manage quests.
// Register it with e.g. `claude mcp add questlog -- quest mcp`.
import Foundation
import QuestCore

private let tools: [[String: Any]] = [
    tool("list_projects", "List the quest log projects, with level, XP and quest counts. Marks the current project.", [:], []),
    tool("show_project", "The whole project as JSON: chains, quests with objectives and status, and notes. Also reports each quest's state (available, locked, in progress, done...).",
         ["project": str("Project slug; defaults to the current project")], []),
    tool("add_quest", "Add a quest. By default it is offered: the user sees a quest window and accepts or declines it. Set active to add it straight to the log.",
         ["title": str("Quest title"), "project": str("Project slug; defaults to the current project"),
          "objectives": ["type": "array", "items": ["type": "string"], "description": "Objectives, one step each"] as [String: Any],
          "description": ["type": "array", "items": ["type": "string"], "description": "Paragraphs; may use <b>, <i>, <code>"] as [String: Any],
          "chain": str("Chain id to add it to; defaults to the first chain"), "new_chain": str("Name of a new chain to create for it"),
          "level": ["type": "integer"], "xp": ["type": "integer"], "who": ["type": "string", "enum": ["you", "claude", "family"]] as [String: Any],
          "where": str("Where it happens"), "lore": str("One line of flavour text"), "tip": str("Optional tip"),
          "active": ["type": "boolean", "description": "Skip the offer and add it as active"] as [String: Any]],
         ["title"]),
    tool("set_objectives", "Mark objectives of a quest done or not done. Completing the last one completes the quest.",
         ["quest": str("Quest id, slug/id, or part of its title"),
          "objectives": ["type": "array", "items": ["type": "string"], "description": "Objective numbers (1-based) or ids, or [\"all\"]"] as [String: Any],
          "done": ["type": "boolean", "description": "Default true"] as [String: Any]],
         ["quest", "objectives"]),
    tool("quest_action", "Change a quest: complete, accept, decline, abandon, restore, track, untrack or remove.",
         ["quest": str("Quest id, slug/id, or part of its title"),
          "action": ["type": "string", "enum": ["complete", "accept", "decline", "abandon", "restore", "track", "untrack", "remove"]] as [String: Any]],
         ["quest", "action"]),
]

private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }

private func tool(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
    ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required] as [String: Any]]
}

func runMCP() {
    let store = Store()
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let method = msg["method"] as? String else { continue }
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        guard id != nil else { continue }  // notifications need no answer
        var result: Any?
        var error: [String: Any]?
        switch method {
        case "initialize":
            result = ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                      "capabilities": ["tools": [String: Any]()],
                      "serverInfo": ["name": "questlog", "version": "0.1.0"],
                      "instructions": "Quest Log tracks the user's projects as quests. Read with show_project before changing things; offer new work with add_quest."] as [String: Any]
        case "ping": result = [String: Any]()
        case "tools/list": result = ["tools": tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do { result = ["content": [["type": "text", "text": try call(store, name, args)]]] }
            catch { result = ["content": [["type": "text", "text": "\(error.localizedDescription)"]], "isError": true] as [String: Any] }
        default: error = ["code": -32601, "message": "Method not found: \(method)"]
        }
        var reply: [String: Any] = ["jsonrpc": "2.0", "id": id!]
        if let error { reply["error"] = error } else { reply["result"] = result ?? NSNull() }
        if let out = try? JSONSerialization.data(withJSONObject: reply), let s = String(data: out, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    }
}

private func call(_ store: Store, _ name: String, _ a: [String: Any]) throws -> String {
    let settings = store.loadSettings()
    func project() throws -> Project {
        guard let slug = (a["project"] as? String) ?? settings.current ?? store.listProjects().first?.slug else { throw QuestError("No projects yet") }
        return try store.loadProject(slug)
    }
    func ref() throws -> String {
        guard let q = a["quest"] as? String else { throw QuestError("Missing quest") }
        let (p, quest) = try store.resolve(q, prefer: settings.current)
        return "\(p.slug)/\(quest.id)"
    }
    switch name {
    case "list_projects":
        return store.listProjects().map { p in
            let t = p.totals
            return "\(p.slug)\(p.slug == settings.current ? " (current)" : ""): \(p.title), level \(t.level), \(t.xp) XP, \(t.done)/\(t.total) quests done"
        }.joined(separator: "\n").ifEmpty("No projects yet.")
    case "show_project":
        let p = try project()
        let states = p.quests.map { "\($0.id): \(p.state(of: $0).label)" }.joined(separator: "\n")
        return try p.json.render() + "\n\nStates:\n" + states
    case "add_quest":
        let p = try project()
        guard let title = a["title"] as? String, !title.isEmpty else { throw QuestError("Missing title") }
        let draft = QuestDraft(title: title, chain: a["chain"] as? String, chainName: a["new_chain"] as? String, lvl: a["level"] as? Int,
                               who: a["who"] as? String, where: a["where"] as? String, xp: a["xp"] as? Int, lore: a["lore"] as? String,
                               desc: a["description"] as? [String], tip: a["tip"] as? String,
                               obj: (a["objectives"] as? [String])?.map { (id: nil, text: $0) },
                               status: (a["active"] as? Bool ?? false) ? .active : .offered)
        guard let (saved, q) = try store.apply(.save(project: p.slug, id: nil, draft: draft)) else { throw QuestError("Not saved") }
        return "\(q.status == .offered ? "Offered" : "Added") \(q.title) as \(saved.slug)/\(q.id)"
    case "set_objectives":
        let r = try ref()
        let select = (a["objectives"] as? [Any] ?? []).map { "\($0)" }
        guard let (_, q) = try store.apply(.objectives(ref: r, select: select, done: a["done"] as? Bool ?? true)) else { throw QuestError("Not saved") }
        return "\(q.title): \(q.objDone)/\(q.obj.count)\(q.isDone ? ", quest complete" : "")"
    case "quest_action":
        let r = try ref()
        let op: Op
        switch a["action"] as? String {
        case "complete": op = .complete(r)
        case "accept": op = .accept(r)
        case "decline": op = .decline(r)
        case "abandon": op = .abandon(r)
        case "restore": op = .restore(r)
        case "track": op = .track(r, on: true)
        case "untrack": op = .track(r, on: false)
        case "remove": op = .remove(r)
        default: throw QuestError("Unknown action")
        }
        try store.apply(op)
        return "Done: \(a["action"]!) \(r)"
    default:
        throw QuestError("Unknown tool \(name)")
    }
}

private extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}
