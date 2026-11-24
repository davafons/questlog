// Create or edit a quest on the parchment page.
import AppKit
import QuestCore
import SwiftUI

@MainActor
final class EditorDraft: ObservableObject, Identifiable {
    let id = UUID()
    let slug: String
    let questId: String?
    @Published var title = ""
    @Published var chain = ""
    @Published var newChain = ""
    @Published var lvl = 1
    @Published var who = "you"
    @Published var place = ""
    @Published var xp = 100
    @Published var lore = ""
    @Published var desc = ""
    @Published var tip = ""
    /// One objective per line.
    @Published var objectives = ""
    private let oldObj: [Objective]

    static let newChainTag = "__new"

    init(_ p: Project, _ q: Quest?) {
        slug = p.slug
        questId = q?.id
        oldObj = q?.obj ?? []
        if let q {
            title = q.title; chain = q.chain; lvl = q.lvl; who = q.who; place = q.where; xp = q.xp
            lore = q.lore; desc = q.desc.joined(separator: "\n\n"); tip = q.tip ?? ""
            objectives = q.obj.map(\.text).joined(separator: "\n")
        } else {
            chain = p.chains.first?.id ?? EditorDraft.newChainTag
            lvl = p.totals.level
        }
    }

    static func start(_ p: Project, _ q: Quest?) {
        let ui = LogState.shared
        ui.optionsOpen = false
        ui.draft = EditorDraft(p, q)
        ui.pageScroll.toTop()
    }

    func save() {
        let ui = LogState.shared, model = AppModel.shared
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { model.status = "A quest needs a title"; NSSound.beep(); return }
        // Objectives keep their ids (and done state) when their text is unchanged, otherwise by position.
        var unused = oldObj
        let lines = objectives.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var obj: [(id: String?, text: String)] = lines.map { line in
            if let i = unused.firstIndex(where: { $0.text == line }) { return (unused.remove(at: i).id, line) }
            return (nil, line)
        }
        for i in obj.indices where obj[i].id == nil {
            if let o = oldObj.indices.contains(i) ? oldObj[i] : nil, unused.contains(where: { $0.id == o.id }) {
                obj[i].id = o.id
                unused.removeAll { $0.id == o.id }
            }
        }
        let paragraphs = desc.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let isNew = chain == EditorDraft.newChainTag
        let draft = QuestDraft(title: t, chain: isNew ? nil : chain, chainName: isNew ? (newChain.isEmpty ? "Quests" : newChain) : nil,
                               lvl: lvl, who: who, where: place, xp: xp, lore: lore, desc: paragraphs,
                               tip: tip.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tip, obj: obj)
        if let id = model.save(project: slug, id: questId, draft: draft) {
            ui.draft = nil
            ui.selection = "\(slug)/\(id)"
        } else {
            NSSound.beep()
        }
    }
}

struct EditorView: View {
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project
    let z: CGFloat

    var body: some View {
        if let d = ui.draft { Form(d: d, project: project, z: z, theme: theme) }
    }

    struct Form: View {
        @ObservedObject var d: EditorDraft
        let project: Project
        let z: CGFloat
        let theme: Theme

        var body: some View {
            VStack(alignment: .leading, spacing: 6 * z) {
                Text(d.questId == nil ? "New Quest" : "Edit Quest").font(theme.title(18 * z)).foregroundStyle(Color.inkHead)
                field("Title") { input($d.title, "What needs doing") }
                HStack(alignment: .top, spacing: 8 * z) {
                    field("Chain") {
                        choice($d.chain, project.chains.map { ($0.id, $0.name) } + [(EditorDraft.newChainTag, "New chain…")])
                    }
                    field("Who") {
                        choice($d.who, ["you", "claude", "family"].map { ($0, whoName($0)) })
                    }
                }
                if d.chain == EditorDraft.newChainTag { field("New chain name") { input($d.newChain, "Act II") } }
                HStack(alignment: .top, spacing: 8 * z) {
                    field("Level") { number($d.lvl) }.frame(width: 60 * z)
                    field("XP") { number($d.xp) }.frame(width: 70 * z)
                    field("Where") { input($d.place, "Anywhere") }
                }
                field("Objectives, one per line") { area($d.objectives, lines: 4) }
                field("Lore") { input($d.lore, "A line of flavour, in italics") }
                field("Description (blank line between paragraphs)") { area($d.desc, lines: 5) }
                field("Tip") { input($d.tip, "Optional") }
                Text("Quest text may use <b>, <i>, <code> and <br>.").font(theme.ui(10.5 * z)).foregroundStyle(Color.inkSoft)
            }
            .padding(EdgeInsets(top: 8 * z, leading: 12 * z, bottom: 22 * z, trailing: 10 * z))
            .environment(\.colorScheme, .light)
        }

        func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
            VStack(alignment: .leading, spacing: 2 * z) {
                Text(label).font(theme.ui(11 * z)).foregroundStyle(Color.inkHead)
                content()
            }
        }

        func box<C: View>(_ c: C) -> some View {
            c.padding(.horizontal, 5 * z).padding(.vertical, 3 * z)
                .background(Color(hex: 0xFFF8E1, alpha: 0.55))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x5C3B14, alpha: 0.5), lineWidth: max(1, z * 0.8)))
        }

        /// A dropdown drawn like the other fields.
        func choice(_ value: Binding<String>, _ options: [(String, String)]) -> some View {
            Menu {
                ForEach(options, id: \.0) { o in Button(o.1) { value.wrappedValue = o.0 } }
            } label: {
                box(HStack {
                    Text(options.first { $0.0 == value.wrappedValue }?.1 ?? value.wrappedValue).font(theme.ui(12.5 * z)).foregroundStyle(Color.ink).lineLimit(1)
                    Spacer(minLength: 4 * z)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7 * z)).foregroundStyle(Color.inkSoft)
                }.contentShape(Rectangle()))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }

        func input(_ text: Binding<String>, _ prompt: String) -> some View {
            box(TextField("", text: text, prompt: Text(prompt).foregroundColor(Color(hex: 0x8A7558)))
                .textFieldStyle(.plain).font(theme.ui(12.5 * z)).foregroundStyle(Color.ink))
        }

        func number(_ value: Binding<Int>) -> some View {
            box(TextField("", value: value, format: .number).textFieldStyle(.plain).font(theme.ui(12.5 * z)).foregroundStyle(Color.ink))
        }

        func area(_ text: Binding<String>, lines: Int) -> some View {
            box(TextEditor(text: text)
                .font(theme.ui(12.5 * z)).foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(lines) * 17 * z))
        }
    }
}
