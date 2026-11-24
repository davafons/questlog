// Shared app state: the data in ~/.questlog, kept fresh by polling, and every change made from the app.
import AppKit
import QuestCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store = Store()
    @Published private(set) var projects: [Project] = []
    @Published private(set) var settings = Settings()
    @Published private(set) var portraitVersion = 0
    @Published var status = ""
    @Published var toast: (title: String, sub: String, id: UUID)?
    /// Set by the app delegate: called when the first offered quest changes.
    var onOffer: ((String?) -> Void)?

    private var signature = ""
    private var timer: Timer?
    private var seen: (objs: Set<String>, quests: Set<String>, levels: [String: Int])?

    init() {
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in Task { @MainActor in AppModel.shared.reload() } }
    }

    var current: Project? { projects.first { $0.slug == settings.current } ?? projects.first }

    func project(_ slug: String) -> Project? { projects.first { $0.slug == slug } }

    func reload(force: Bool = false) {
        let sig = store.signature()
        guard force || sig != signature else { return }
        signature = sig
        projects = store.listProjects()
        settings = store.loadSettings()
        portraitVersion += 1
        react()
    }

    @discardableResult
    func perform(_ op: Op) -> Bool {
        do {
            try store.apply(op)
            status = "Saved"
            reload(force: true)
            return true
        } catch {
            status = error.localizedDescription
            NSSound.beep()
            return false
        }
    }

    /// Saves a quest from the editor and returns its id.
    func save(project: String, id: String?, draft: QuestDraft) -> String? {
        do {
            guard let (_, q) = try store.apply(.save(project: project, id: id, draft: draft)) else { return nil }
            status = "Saved"
            reload(force: true)
            return q.id
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    func portrait(_ slug: String) -> NSImage? { store.portrait(for: slug).flatMap { NSImage(contentsOf: $0) } }

    func setPortrait(_ slug: String, _ url: URL?) {
        do { try store.setPortrait(slug, from: url); reload(force: true) }
        catch { status = error.localizedDescription; NSSound.beep() }
    }

    func isTracked(_ p: Project, _ q: Quest) -> Bool { settings.tracked.contains("\(p.slug)/\(q.id)") }

    /// Plays the sound that matches what changed, whether it came from the app, the CLI or an agent.
    private func react() {
        var objs = Set<String>(), quests = Set<String>(), levels: [String: Int] = [:]
        for p in projects {
            levels[p.slug] = p.totals.level
            for q in p.quests {
                for o in q.obj where o.done { objs.insert("\(p.slug)/\(q.id)/\(o.id)") }
                if q.isDone { quests.insert("\(p.slug)/\(q.id)") }
            }
        }
        if let seen {
            let newQuests = quests.subtracting(seen.quests)
            let newObj = !objs.subtracting(seen.objs).isEmpty
            let newLevel = levels.first { slug, l in (seen.levels[slug] ?? l) < l }
            if !newQuests.isEmpty { Sound.shared.play("complete") } else if newObj { Sound.shared.play("objective") }
            if let ref = newQuests.first {
                let parts = ref.split(separator: "/").map(String.init)
                if let q = project(parts[0])?.quest(parts[1]) { showToast("\(q.title) completed.", "Experience gained: \(q.xp)") }
            }
            if let (_, level) = newLevel {
                DispatchQueue.main.asyncAfter(deadline: .now() + (newQuests.isEmpty ? 0.2 : 1.4)) {
                    Sound.shared.play("levelup")
                    self.showToast("Level \(level)!", "You have reached a new level.")
                }
            }
        }
        seen = (objs, quests, levels)
        let offer = offers(projects).first
        onOffer?(offer.map(\.ref))
    }

    func showToast(_ title: String, _ sub: String) {
        let id = UUID()
        toast = (title, sub, id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if self.toast?.id == id { self.toast = nil } }
    }
}
