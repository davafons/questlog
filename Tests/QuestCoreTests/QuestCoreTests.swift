import Foundation
import Testing
@testable import QuestCore

/// A store in a fresh temporary folder with one project.
func makeStore() throws -> Store {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("questlog-tests-\(UUID().uuidString)")
    let store = Store(home: dir)
    let p = Project(slug: "demo", title: "Demo", chains: [Chain(id: "main", name: "Main Quests")], quests: [
        Quest(id: "first", chain: "main", title: "First Steps", xp: 200, obj: [Objective(id: "a", text: "A"), Objective(id: "b", text: "B")]),
        Quest(id: "second", chain: "main", title: "Second Wind", lvl: 9, req: ["first"], xp: 600, obj: [Objective(id: "c", text: "C")]),
    ])
    try store.saveProject(p)
    try store.saveSettings(Settings(current: "demo"))
    return store
}

@Test func statesFollowRequirementsAndProgress() throws {
    let store = try makeStore()
    var p = try store.loadProject("demo")
    #expect(p.state(of: p.quest("first")!) == .available)
    #expect(p.state(of: p.quest("second")!) == .locked)
    p.quests[0].obj[0].done = true
    #expect(p.state(of: p.quests[0]) == .inProgress)
    p.quests[0].obj[1].done = true
    #expect(p.state(of: p.quests[0]) == .done)
    #expect(p.state(of: p.quests[1]) == .available)
}

@Test func totalsCountPartialXPAndLevels() throws {
    var p = try makeStore().loadProject("demo")
    p.quests[0].obj[0].done = true          // half of 200
    p.quests[1].obj[0].done = true          // all of 600
    let t = p.totals
    #expect(t.xp == 700)
    #expect(t.max == 800)
    #expect(t.level == 2)
    #expect(t.intoLevel == 300)
    #expect(t.done == 1 && t.open == 1)
    p.quests[1].status = .abandoned
    #expect(p.totals.max == 200)
}

@Test func difficultyColours() {
    let q = Quest(id: "x", chain: "main", title: "X", lvl: 10)
    #expect(difficulty(q, level: 5) == .red)
    #expect(difficulty(q, level: 7) == .orange)
    #expect(difficulty(q, level: 12) == .yellow)
    #expect(difficulty(q, level: 15) == .green)
    #expect(difficulty(q, level: 16) == .gray)
}

@Test func checkingObjectivesCompletesAndUntracks() throws {
    let store = try makeStore()
    try store.apply(.track("first", on: true))
    #expect(store.loadSettings().tracked == ["demo/first"])
    try store.apply(.objectives(ref: "first", select: ["1"], done: true))
    var q = try store.loadProject("demo").quest("first")!
    #expect(q.objDone == 1 && q.completed == nil)
    try store.apply(.objectives(ref: "demo/first", select: ["b"], done: true))
    q = try store.loadProject("demo").quest("first")!
    #expect(q.isDone && q.completed != nil)
    #expect(store.loadSettings().tracked.isEmpty)
    try store.apply(.objectives(ref: "first", select: ["all"], done: false))
    #expect(try store.loadProject("demo").quest("first")!.completed == nil)
    #expect(throws: QuestError.self) { try store.apply(.objectives(ref: "first", select: ["9"], done: true)) }
}

@Test func resolveByIdTitleAndAmbiguity() throws {
    let store = try makeStore()
    #expect(try store.resolve("second").1.id == "second")
    #expect(try store.resolve("wind").1.id == "second")
    #expect(throws: QuestError.self) { try store.resolve("s") }      // "First Steps" and "Second Wind"
    #expect(throws: QuestError.self) { try store.resolve("nope") }
}

@Test func saveQuestCreatesEditsAndKeepsObjectiveIds() throws {
    let store = try makeStore()
    let draft = QuestDraft(title: "Brand New", chainName: "Side Quests", lvl: 3, xp: 50, desc: ["One", " ", "Two"],
                           obj: [(nil, "Do this"), (nil, "Do that"), (nil, "  ")])
    guard let (p1, q1) = try store.apply(.save(project: "demo", id: nil, draft: draft)) else { Issue.record("no result"); return }
    #expect(q1.id == "brand-new")
    #expect(p1.chains.contains(Chain(id: "side-quests", name: "Side Quests")))
    #expect(q1.chain == "side-quests")
    #expect(q1.obj.map(\.id) == ["do-this", "do-that"])
    #expect(q1.desc == ["One", "Two"])
    #expect(q1.status == .active)

    try store.apply(.objectives(ref: "brand-new", select: ["do-this"], done: true))
    let edit = QuestDraft(title: "Renamed", chain: "main", obj: [("do-this", "Do this, edited"), (nil, "Third")])
    guard let (_, q2) = try store.apply(.save(project: "demo", id: "brand-new", draft: edit)) else { Issue.record("no result"); return }
    #expect(q2.id == "brand-new" && q2.title == "Renamed" && q2.chain == "main")
    #expect(q2.obj == [Objective(id: "do-this", text: "Do this, edited", done: true), Objective(id: "third", text: "Third")])
    #expect(throws: QuestError.self) { try store.apply(.save(project: "demo", id: nil, draft: QuestDraft(title: "  "))) }
}

@Test func removeClearsRequirementsAndTracking() throws {
    let store = try makeStore()
    try store.apply(.track("first", on: true))
    try store.apply(.remove("first"))
    let p = try store.loadProject("demo")
    #expect(p.quest("first") == nil)
    #expect(p.quest("second")!.req.isEmpty)
    #expect(store.loadSettings().tracked.isEmpty)
}

@Test func trackerListPrefersTrackedThenInProgress() throws {
    let store = try makeStore()
    try store.apply(.objectives(ref: "first", select: ["a"], done: true))
    var (auto, items) = trackerList(store.listProjects(), store.loadSettings())
    #expect(auto && items.map(\.quest.id) == ["first"])
    try store.apply(.track("second", on: true))
    (auto, items) = trackerList(store.listProjects(), store.loadSettings())
    #expect(!auto && items.map(\.quest.id) == ["second"])
}

@Test func readsExistingFilesWithMissingFields() throws {
    let store = try makeStore()
    let json = #"{"slug":"old","title":"Old","chains":[{"id":"c","name":"C"}],"quests":[{"id":"q","title":"Q","obj":[{"id":"o","text":"O","done":true}]}]}"#
    try json.write(to: store.projectsDir.appendingPathComponent("old.json"), atomically: true, encoding: .utf8)
    let q = try store.loadProject("old").quests[0]
    #expect(q.status == .active && q.xp == 100 && q.where == "Anywhere" && q.isDone)
}

@Test func slugsAndIds() {
    #expect(slugify("¡Hola, Mundo!") == "hola-mundo")
    #expect(slugify("  --  ") == "quest")
    #expect(uniqueId("Hello", taken: ["hello", "hello-2"]) == "hello-3")
}

@Test func richTextParsesTheAllowedTags() {
    let runs = Rich.parse(##"Plain <b>bold</b> <i>it</i> <code>x &lt; y</code><br><span class="flav">gold</span> <a href="#">link</a>"##)
    #expect(runs.first { $0.bold }?.text == "bold")
    #expect(runs.first { $0.italic }?.text == "it")
    #expect(runs.first { $0.code }?.text == "x < y")
    #expect(runs.first { $0.classes == ["flav"] }?.text == "gold")
    #expect(Rich.plain(##"a<br>b <a href="#">link</a>"##) == "a\nb link")
}
