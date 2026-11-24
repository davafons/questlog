// The quest log window: the game's dual-pane quest log frame, stretched to the window. Positions are in the frame's
// native pixels (at least 682 x 440) times `z`, the scale that keeps text at most 1.3x the game's size.
import AppKit
import QuestCore
import SwiftUI

/// What the log shows and how; filters and folds are remembered.
@MainActor
final class LogState: ObservableObject {
    static let shared = LogState()
    private let d = UserDefaults.standard

    @Published var filter: String { didSet { d.set(filter, forKey: "logFilter") } }
    @Published var hideLocked: Bool { didSet { d.set(hideLocked, forKey: "logHideLocked") } }
    @Published var hideDone: Bool { didSet { d.set(hideDone, forKey: "logHideDone") } }
    @Published var collapsed: Set<String> { didSet { d.set(Array(collapsed), forKey: "logCollapsed") } }
    /// "slug/questId" or "slug/#note<n>".
    @Published var selection: String?
    @Published var draft: EditorDraft?
    @Published var optionsOpen = false
    @Published var portraitMenu = false
    let listScroll = ScrollModel()
    let pageScroll = ScrollModel()

    init() {
        filter = d.string(forKey: "logFilter") ?? "all"
        hideLocked = d.bool(forKey: "logHideLocked")
        hideDone = d.bool(forKey: "logHideDone")
        collapsed = Set(d.stringArray(forKey: "logCollapsed") ?? [])
    }

    func select(_ ref: String) {
        draft = nil
        optionsOpen = false
        selection = ref
        pageScroll.toTop()
        let slug = String(ref.split(separator: "/").first ?? "")
        if slug != AppModel.shared.settings.current, AppModel.shared.project(slug) != nil { AppModel.shared.perform(.current(slug)) }
    }

    func visible(_ p: Project, _ q: Quest) -> Bool {
        let s = p.state(of: q)
        if hideDone && s.isClosed { return false }
        if hideLocked && s == .locked { return false }
        switch filter {
        case "avail": return [.available, .inProgress, .offered].contains(s)
        case "you": return q.who == "you"
        case "claude": return q.who == "claude"
        default: return true
        }
    }

    /// The selected quest, or the first open one.
    func quest(in p: Project) -> Quest? {
        if let sel = selection, sel.hasPrefix(p.slug + "/") {
            let id = String(sel.dropFirst(p.slug.count + 1))
            if let q = p.quest(id) { return q }
            if id.hasPrefix("#note") { return nil }
        }
        return p.quests.first { !p.state(of: $0).isClosed } ?? p.quests.first
    }

    func noteIndex(in p: Project) -> Int? {
        guard let sel = selection, sel.hasPrefix(p.slug + "/#note"), let n = Int(sel.dropFirst(p.slug.count + 6)), (p.notes ?? []).indices.contains(n) else { return nil }
        return n
    }
}

/// Text scale and frame size for a window size; Swift twin of the old fit().
func logLayout(_ size: CGSize) -> (z: CGFloat, w: CGFloat, h: CGFloat) {
    let z = max(0.6, min(1.3, size.width / 690, size.height / 448))
    return (z, max(682, (size.width / z - 8).rounded(.down)), max(440, (size.height / z - 8).rounded(.down)))
}

struct LogView: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    var close: () -> Void = {}
    var minimize: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let (z, w, h) = logLayout(geo.size)
            frame(w, h, z)
                .frame(width: w * z, height: h * z, alignment: .topLeading)
                .offset(x: 4 * z, y: 4 * z)
        }
        .ignoresSafeArea()
        .onExitCommand {
            if ui.portraitMenu { ui.portraitMenu = false } else if ui.optionsOpen { ui.optionsOpen = false } else if ui.draft != nil { ui.draft = nil } else { close() }
        }
    }

    @ViewBuilder
    func frame(_ w: CGFloat, _ h: CGFloat, _ z: CGFloat) -> some View {
        let p = model.current
        ZStack(alignment: .topLeading) {
            background(w, h, z)

            // Title band: drags the window.
            Text("Quest Log").font(theme.ui(13 * z)).foregroundStyle(Color.gold).outlined()
                .frame(width: (w - 148) * z, height: 22 * z)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .place(72, 12, z)

            Portrait(project: p, z: z).place(9, 6, z)
            GearButton(on: ui.optionsOpen, z: z) { ui.optionsOpen.toggle(); if ui.optionsOpen { ui.draft = nil } }.place(w - 72, 15, z)
            TexButton(up: "hide-up", down: "hide-down", glyph: "_", z: z, help: "Minimize", action: minimize).place(w - 54, 7, z)
            TexButton(up: "close-up", down: "close-down", glyph: "✕", z: z, help: "Close", action: close).place(w - 32, 7, z)

            Band(project: p, z: z).frame(width: (w - 106) * z, height: 28 * z).place(74, 38, z)

            QuestList(project: p, z: z)
                .trackedScroll(ui.listScroll)
                .frame(width: 295 * z, height: (h - 106) * z).place(22, 74, z)
            ScrollBar(model: ui.listScroll, z: z).frame(width: 20 * z, height: (h - 102) * z).place(322, 72, z)

            Group {
                if let draft = ui.draft, let dp = model.project(draft.slug) {
                    EditorView(project: dp, z: z).trackedScroll(ui.pageScroll)
                } else if let p {
                    QuestPage(project: p, z: z).trackedScroll(ui.pageScroll)
                }
            }
            .frame(width: (w - 392) * z, height: (h - 114) * z).place(350, 78, z)
            ScrollBar(model: ui.pageScroll, z: z).frame(width: 20 * z, height: (h - 102) * z).place(w - 28, 72, z)

            if ui.optionsOpen {
                OptionsView(z: z).frame(width: (w - 24) * z, height: (h - 102) * z).place(20, 72, z)
            }

            BottomRow(project: p, w: w, h: h, z: z)

            if ui.portraitMenu, let p {
                PortraitMenu(project: p, z: z).place(30, 58, z)
            }
            if let t = model.toast {
                VStack(spacing: 2 * z) {
                    Text(t.title).font(theme.ui(26 * z)).foregroundStyle(Color.gold)
                    Text(t.sub).font(theme.ui(14 * z)).foregroundStyle(.white)
                }
                .shadow(color: .black, radius: 0, x: 2, y: 2).shadow(color: .black, radius: 6)
                .frame(width: w * z).place(0, h * 0.28, z)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast?.id)
    }

    @ViewBuilder
    func background(_ w: CGFloat, _ h: CGFloat, _ z: CGFloat) -> some View {
        let insets: (CGFloat, CGFloat, CGFloat, CGFloat) = (90, 350, 50, 92)
        if theme.themed, let parts = theme.slices("questlog-frame", insets) {
            NineSlice(parts: parts, insets: insets, scale: z).frame(width: w * z, height: h * z)
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8 * z)
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2723), Color(hex: 0x15130F)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8 * z).strokeBorder(Color(hex: 0x6A6050), lineWidth: 2 * z))
                    .shadow(color: .black.opacity(0.7), radius: 12 * z, y: 6 * z)
                    .frame(width: (w - 8) * z, height: (h - 8) * z).place(4, 8, z)
                Rectangle().fill(Color(hex: 0x0B0A08)).overlay(Rectangle().strokeBorder(.black, lineWidth: 2 * z))
                    .frame(width: 298 * z, height: (h - 102) * z).place(20, 72, z)
                Rectangle().fill(Color(hex: 0x0B0A08)).frame(width: 20 * z, height: (h - 102) * z).place(322, 72, z)
                Rectangle().fill(Color(hex: 0x0B0A08)).frame(width: 20 * z, height: (h - 102) * z).place(w - 28, 72, z)
                Parchment().overlay(Rectangle().strokeBorder(.black, lineWidth: 2 * z))
                    .frame(width: (w - 390) * z, height: (h - 107) * z).place(348, 75, z)
            }
        }
    }
}

extension View {
    /// Positions a view at native frame coordinates.
    func place(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> some View { offset(x: x * z, y: y * z) }
}

/// Drawn parchment for when there is no extracted art.
struct Parchment: View {
    var body: some View {
        ZStack {
            Color(hex: 0xE6CC94)
            RadialGradient(colors: [Color(hex: 0xFFF5DA, alpha: 0.7), .clear], center: UnitPoint(x: 0.35, y: 0.15), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [.clear, Color(hex: 0x8A5A22, alpha: 0.45)], center: .center, startRadius: 120, endRadius: 520)
        }
    }
}

// MARK: - Header

struct Portrait: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project?
    let z: CGFloat
    @State private var hover = false

    var body: some View {
        let t = project?.totals ?? Totals()
        Button { ui.portraitMenu.toggle() } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let slug = project?.slug, let img = model.portrait(slug) { Image(nsImage: img).resizable().scaledToFill() }
                    else if let img = theme.tex("book-icon") { Image(nsImage: img).resizable().scaledToFill() }
                    else {
                        ZStack {
                            RadialGradient(colors: [Color(hex: 0x4A3514), Color(hex: 0x120C04)], center: UnitPoint(x: 0.42, y: 0.38), startRadius: 0, endRadius: 30 * z)
                            Text("!").font(.system(size: 34 * z, weight: .bold, design: .serif)).foregroundStyle(Color.gold).shadow(color: Color(hex: 0x5A3B00), radius: 0, x: 2, y: 2)
                        }
                    }
                }
                .frame(width: 57 * z, height: 57 * z)
                .clipShape(Circle())
                .overlay(theme.themed ? nil : Circle().strokeBorder(Color(hex: 0xA3802F), lineWidth: 3 * z))
                .brightness(hover ? 0.1 : 0)
                Text("\(t.level)").font(theme.ui(11 * z)).foregroundStyle(Color.gold).outlined()
                    .frame(width: 22 * z, height: 22 * z)
                    .background(Circle().fill(Color(hex: 0x1A1206)).overlay(Circle().strokeBorder(Color(hex: 0xA3802F), lineWidth: 1.5 * z)))
                    .offset(x: -4 * z, y: 4 * z)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Level \(t.level) · XP \(t.intoLevel) / \(xpPerLevel). Click to change the portrait.")
    }
}

struct PortraitMenu: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project
    let z: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item("Choose image…") {
                ui.portraitMenu = false
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
                panel.message = "Choose a portrait for \(project.title)"
                if panel.runModal() == .OK, let url = panel.url { model.setPortrait(project.slug, url) }
            }
            item("Use book icon") { ui.portraitMenu = false; model.setPortrait(project.slug, nil) }
        }
        .padding(5 * z)
        .background(RoundedRectangle(cornerRadius: 4 * z).fill(Color(hex: 0x050712, alpha: 0.96)).overlay(RoundedRectangle(cornerRadius: 4 * z).strokeBorder(Color(hex: 0x9AA3B5), lineWidth: max(1, z))))
    }

    func item(_ title: String, _ action: @escaping () -> Void) -> some View {
        HoverRow(z: z, action: action) { hover in
            Text(title).font(theme.ui(11.5 * z)).foregroundStyle(hover ? Color.gold : .white)
                .padding(.horizontal, 8 * z).padding(.vertical, 2 * z)
                .frame(minWidth: 120 * z, alignment: .leading)
        }
    }
}

/// A plain button that highlights while hovered.
struct HoverRow<Label: View>: View {
    let z: CGFloat
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hover = false
    var body: some View {
        Button(action: action) { label(hover).background(hover ? Color.gold.opacity(0.18) : .clear).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
    }
}

struct Band: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project?
    let z: CGFloat

    var body: some View {
        HStack(spacing: 2 * z) {
            Menu {
                ForEach(model.projects) { p in
                    Button(p.title) { ui.selection = nil; ui.draft = nil; model.perform(.current(p.slug)) }
                }
            } label: {
                HStack {
                    Text(project?.title ?? "No projects").font(theme.ui(11.5 * z)).foregroundStyle(Color.gold).lineLimit(1)
                    Spacer(minLength: 4 * z)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7 * z)).foregroundStyle(Color.gold)
                }
                .padding(.horizontal, 7 * z)
                .frame(height: 20 * z)
                .background(LinearGradient(colors: [Color(hex: 0x141210), Color(hex: 0x050404)], startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x5A5246), lineWidth: max(1, z)))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 190 * z)
            .help(project?.subtitle ?? "")

            Spacer(minLength: 8 * z)
            tab("All", ui.filter == "all") { ui.filter = "all" }
            tab("Available", ui.filter == "avail") { ui.filter = "avail" }
            tab("Mine", ui.filter == "you") { ui.filter = "you" }
            tab("Claude", ui.filter == "claude") { ui.filter = "claude" }
            Rectangle().fill(Color(hex: 0x4A443A)).frame(width: 1, height: 14 * z).padding(.horizontal, 4 * z)
            toggle("Hide locked", ui.hideLocked) { ui.hideLocked.toggle() }
            toggle("Hide done", ui.hideDone) { ui.hideDone.toggle() }
        }
    }

    func tab(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(theme.ui(11 * z)).foregroundStyle(on ? Color.gold : Color(hex: 0xC8C0AD)).outlined()
                .padding(.horizontal, 6 * z).padding(.vertical, 2 * z)
                .background(on ? Color.gold.opacity(0.12) : .clear)
                .overlay(on ? RoundedRectangle(cornerRadius: 2 * z).strokeBorder(Color.gold.opacity(0.35), lineWidth: max(1, z * 0.8)) : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func toggle(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4 * z) {
                CheckBox(on: on, z: z * 0.85)
                Text(title).font(theme.ui(11 * z)).foregroundStyle(Color(hex: 0xC8C0AD)).outlined()
            }
            .padding(.horizontal, 4 * z)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quest list

struct QuestList: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project?
    let z: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = project {
                let level = p.totals.level, selected = ui.draft == nil ? ui.quest(in: p)?.id : nil, note = ui.noteIndex(in: p)
                ForEach(p.chains, id: \.id) { c in
                    let qs = p.quests.filter { $0.chain == c.id }, vis = qs.filter { ui.visible(p, $0) }
                    if !vis.isEmpty {
                        zone(c.name, key: "\(p.slug)/\(c.id)", count: "\(qs.filter(\.isDone).count)/\(qs.count)")
                        if !ui.collapsed.contains("\(p.slug)/\(c.id)") {
                            ForEach(vis) { q in row(p, q, level, on: note == nil && q.id == selected) }
                        }
                    }
                }
                if let notes = p.notes, !notes.isEmpty {
                    zone("Notes", key: "\(p.slug)/#notes", count: "\(notes.count)")
                    if !ui.collapsed.contains("\(p.slug)/#notes") {
                        ForEach(notes.indices, id: \.self) { i in
                            ListRow(z: z, on: note == i, action: { ui.select("\(p.slug)/#note\(i)") }) {
                                Text(notes[i].title).font(theme.ui(12 * z)).foregroundStyle(Color(hex: 0xE8E0C8)).lineLimit(1)
                            } trailing: { EmptyView() }
                        }
                    }
                }
                if !p.quests.contains(where: { ui.visible(p, $0) }) && (p.notes ?? []).isEmpty {
                    Text("No quests match these filters.").font(theme.ui(12 * z)).foregroundStyle(Color(hex: 0xA59C89)).padding(10 * z)
                }
                HoverRow(z: z, action: { EditorDraft.start(p, nil) }) { hover in
                    Text("+ New Quest").font(theme.ui(11.5 * z)).foregroundStyle(hover ? .white : Color(hex: 0x9B927F)).outlined()
                        .padding(.leading, 20 * z).padding(.vertical, 2 * z).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6 * z)
            } else {
                Text("No projects yet. In a terminal: quest project new my-project \"My Project\"")
                    .font(theme.ui(12 * z)).foregroundStyle(Color(hex: 0xA59C89)).padding(10 * z)
            }
        }
        .padding(.vertical, 4 * z)
    }

    func zone(_ name: String, key: String, count: String) -> some View {
        let folded = ui.collapsed.contains(key)
        return Button { if folded { ui.collapsed.remove(key) } else { ui.collapsed.insert(key) } } label: {
            HStack(spacing: 5 * z) {
                Text(folded ? "+" : "−").font(.system(size: 10 * z, weight: .bold)).foregroundStyle(Color(hex: 0xE8E0C8))
                    .frame(width: 12 * z, height: 12 * z)
                    .background(LinearGradient(colors: [Color(hex: 0x3A352D), Color(hex: 0x16130F)], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().strokeBorder(Color(hex: 0x6A6050), lineWidth: max(1, z * 0.8)))
                Text(name).font(theme.ui(12 * z)).foregroundStyle(Color.gold).outlined().lineLimit(1)
                Spacer(minLength: 4 * z)
                Text(count).font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0x9B927F)).monospacedDigit()
            }
            .padding(.leading, 4 * z).padding(.trailing, 6 * z)
            .frame(height: 17 * z)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func row(_ p: Project, _ q: Quest, _ level: Int, on: Bool) -> some View {
        let s = p.state(of: q)
        let color: Color = [.done, .locked, .declined, .abandoned].contains(s) ? .qGray : .difficulty(difficulty(q, level: level))
        let label: String? = switch s {
        case .done: "(Complete)"; case .locked: "(Locked)"; case .offered: "(New)"; case .declined: "(Declined)"; case .abandoned: "(Abandoned)"; default: nil
        }
        return ListRow(z: z, on: on, action: { ui.select("\(p.slug)/\(q.id)") }) {
            Text(q.title).font(theme.ui(12 * z)).foregroundStyle(on ? .white : color).outlined().lineLimit(1)
        } trailing: {
            if let label { Text(label).font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0xBFB7A5)).outlined() }
            else if model.isTracked(p, q) { Text("Tracked").font(theme.ui(10.5 * z)).foregroundStyle(Color.gold).outlined() }
            else { Text("[\(q.lvl)]").font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0xBFB7A5)).outlined().monospacedDigit() }
        }
    }
}

/// A row in the quest list with the game's selection highlight.
struct ListRow<Title: View, Trailing: View>: View {
    @ObservedObject var theme = Theme.shared
    let z: CGFloat
    let on: Bool
    let action: () -> Void
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * z) {
                title()
                Spacer(minLength: 4 * z)
                trailing()
            }
            .padding(.leading, 20 * z).padding(.trailing, 6 * z).padding(.vertical, 1 * z)
            .frame(minHeight: 16 * z)
            .background(alignment: .leading) {
                Group {
                    if let hi = theme.tex("title-highlight") { Image(nsImage: hi).resizable() }
                    else { LinearGradient(colors: [Color.gold.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing) }
                }
                .opacity(on ? 0.55 : hover ? 0.25 : 0)
                .padding(.leading, 14 * z)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Quest page

/// Quest text as styled text: the little markup quests may use, on parchment.
func richText(_ html: String, font: Font, color: Color = .ink, italic: Bool = false, z: CGFloat) -> Text {
    var out = AttributedString()
    for run in Rich.parse(html) {
        var a = AttributedString(run.text)
        var f = run.code ? Font.system(size: 11 * z, design: .monospaced) : font
        if run.bold { f = f.bold() }
        if run.italic || italic { f = f.italic() }
        a.font = f
        a.foregroundColor = run.classes.contains("grn") ? Color(hex: 0x2F5A10) : run.classes.contains("flav") ? Color(hex: 0x4A3017) : color
        if run.code { a.backgroundColor = Color(hex: 0x50321A, alpha: 0.15) }
        out += a
    }
    return Text(out)
}

struct QuestPage: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project
    let z: CGFloat

    var body: some View {
        let p = project
        VStack(alignment: .leading, spacing: 0) {
            if let n = ui.noteIndex(in: p), let note = p.notes?[n] {
                Text(note.title).font(theme.title(18 * z)).foregroundStyle(Color.inkHead)
                if let sub = note.sub { Text(sub).font(theme.ui(11 * z)).foregroundStyle(Color.inkSoft) }
                heading("Notes")
                ForEach(note.body.indices, id: \.self) { i in para(richText(note.body[i], font: theme.ui(12.5 * z), z: z)) }
            } else if let q = ui.quest(in: p) {
                quest(p, q)
            } else {
                Text("No quests yet").font(theme.title(18 * z)).foregroundStyle(Color.inkHead)
                para(Text("Add one with + New Quest, or from a terminal: quest add \"Title\" --obj \"First step\"").font(theme.ui(12.5 * z)))
            }
        }
        .padding(EdgeInsets(top: 8 * z, leading: 12 * z, bottom: 22 * z, trailing: 10 * z))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    func quest(_ p: Project, _ q: Quest) -> some View {
        let s = p.state(of: q), level = p.totals.level
        let editable = ![.offered, .declined, .abandoned].contains(s)
        HStack(alignment: .firstTextBaseline, spacing: 6 * z) {
            Text(q.title).font(theme.title(18 * z)).foregroundStyle(Color.inkHead).frame(maxWidth: .infinity, alignment: .leading)
            Button { EditorDraft.start(p, q) } label: {
                Text("Edit").font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0x5C3B14)).padding(.horizontal, 5 * z)
                    .overlay(RoundedRectangle(cornerRadius: 2 * z).strokeBorder(Color(hex: 0x5C3B14, alpha: 0.45), lineWidth: max(1, z * 0.8)))
            }
            .buttonStyle(.plain)
        }
        HStack(spacing: 8 * z) {
            Text(whoName(q.who)).font(theme.ui(10.5 * z)).foregroundStyle(.white).outlined().padding(.horizontal, 5 * z)
                .background(RoundedRectangle(cornerRadius: 2 * z).fill(Color(hex: q.who == "claude" ? 0x1F5F7F : q.who == "family" ? 0x7A2F5C : 0x7A4F12)))
            Text(q.where).font(theme.ui(11 * z)).foregroundStyle(Color.inkSoft)
            Text("Level \(q.lvl)").font(theme.ui(11 * z)).foregroundStyle(Color.difficulty(difficulty(q, level: level))).outlined()
            Text(p.chainName(q.chain)).font(theme.ui(11 * z)).foregroundStyle(Color.inkSoft).lineLimit(1)
        }
        .padding(.top, 2 * z)
        if s == .offered { banner("New quest. Accept it to add it to your log.") }
        if s == .abandoned || s == .declined { banner("You \(s.rawValue) this quest. Restore it to pick it up again.") }
        let missing = p.missing(for: q)
        if !missing.isEmpty {
            HStack(spacing: 4 * z) {
                Text("Requires:").font(theme.ui(11.5 * z)).foregroundStyle(Color(hex: 0x8A1010))
                ForEach(missing) { m in
                    Button { ui.select("\(p.slug)/\(m.id)") } label: { Text(m.title).font(theme.ui(11.5 * z)).underline().foregroundStyle(Color(hex: 0x8A1010)) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 6 * z)
        }
        heading("Quest Objectives")
        ForEach(q.obj, id: \.id) { o in
            Button { model.perform(.objectives(ref: "\(p.slug)/\(q.id)", select: [o.id], done: !o.done)) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6 * z) {
                    CheckBox(on: o.done, z: z, parchment: true).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 * z }
                    (richText(o.text, font: theme.ui(12.5 * z), color: o.done ? Color(hex: 0x5A4A32) : .ink, z: z)
                     + Text(o.done ? " (Complete)" : "").font(theme.ui(12.5 * z)).foregroundColor(Color(hex: 0x5A4A32)))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 1 * z)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .opacity(editable ? 1 : 0.6)
        }
        heading("Description")
        if !q.lore.isEmpty { para(Text(q.lore).font(theme.ui(12.5 * z)).foregroundColor(Color(hex: 0x4A3017))) }
        ForEach(q.desc.indices, id: \.self) { i in para(richText(q.desc[i], font: theme.ui(12.5 * z), z: z)) }
        if let tip = q.tip {
            (Text("Tip: ").font(theme.ui(12.5 * z)).bold() + richText(tip, font: theme.ui(12.5 * z), z: z))
                .padding(.horizontal, 7 * z).padding(.vertical, 4 * z)
                .background(Color(hex: 0x6E4614, alpha: 0.13))
                .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x8B5A1C)).frame(width: 2 * z) }
                .padding(.top, 4 * z)
        }
        heading("Rewards")
        HStack(spacing: 6 * z) {
            Text("You will receive:").font(theme.ui(12.5 * z)).foregroundStyle(Color.ink)
            HStack(spacing: 5 * z) {
                Text("XP").font(.system(size: 8.5 * z, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18 * z, height: 18 * z)
                    .background(RoundedRectangle(cornerRadius: 2 * z).fill(LinearGradient(colors: [Color(hex: 0xB77CFF), Color(hex: 0x4B0F8A)], startPoint: .top, endPoint: .bottom)))
                Text("\(q.xp) experience").font(theme.ui(12.5 * z)).foregroundStyle(Color.ink)
            }
            .padding(2 * z).padding(.trailing, 5 * z)
            .background(Color(hex: 0x281400, alpha: 0.12))
            .overlay(RoundedRectangle(cornerRadius: 2 * z).strokeBorder(Color(hex: 0x5C3B14, alpha: 0.45), lineWidth: max(1, z * 0.8)))
        }
        if s == .done { Text("Quest complete.").font(theme.ui(12.5 * z)).foregroundStyle(Color(hex: 0x2F5A10)).padding(.top, 8 * z) }
    }

    func heading(_ t: String) -> some View {
        Text(t).font(theme.title(15.5 * z)).foregroundStyle(Color.inkHead).padding(.top, 12 * z).padding(.bottom, 4 * z)
    }

    func para(_ t: Text) -> some View {
        t.font(theme.ui(12.5 * z)).foregroundColor(.ink).lineSpacing(2 * z).fixedSize(horizontal: false, vertical: true).padding(.bottom, 7 * z)
    }

    func banner(_ t: String) -> some View {
        Text(t).font(theme.ui(11.5 * z)).foregroundStyle(Color.ink)
            .padding(.horizontal, 7 * z).padding(.vertical, 4 * z)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gold.opacity(0.22))
            .overlay(Rectangle().strokeBorder(Color(hex: 0x5C3B14, alpha: 0.45), lineWidth: max(1, z * 0.8)))
            .padding(.top, 8 * z)
    }
}

// MARK: - Bottom row

struct BottomRow: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @ObservedObject var ui = LogState.shared
    let project: Project?
    let w: CGFloat, h: CGFloat, z: CGFloat
    @State private var armed = false

    var body: some View {
        let slots: [(x: CGFloat, w: CGFloat)] = [(21, 103), (130, 91), (227, 93)]
        let buttons = actions()
        ZStack(alignment: .topLeading) {
            ForEach(Array(buttons.prefix(3).enumerated()), id: \.offset) { i, b in
                RedButton(title: b.0, width: 88, height: 19, z: z, action: b.1)
                    .frame(width: slots[i].w * z, height: 20 * z).place(slots[i].x, h - 29, z)
            }
            if let p = project {
                let t = p.totals
                HStack {
                    (Text("Quests ") + Text("\(t.done)/\(t.total)").foregroundColor(Color(hex: 0xD8CFBD)) + Text("   Chains ")
                     + Text("\(p.chainsDone)/\(p.chains.count)").foregroundColor(Color(hex: 0xD8CFBD)) + Text("   Open ") + Text("\(t.open)").foregroundColor(Color(hex: 0xD8CFBD)))
                        .font(theme.ui(10.5 * z)).foregroundColor(Color(hex: 0xA59C89)).outlined().lineLimit(1)
                    Spacer(minLength: 6 * z)
                    Text(model.status).font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0xA59C89)).outlined().lineLimit(1)
                }
                .frame(width: (w - 420) * z, height: 20 * z).place(330, h - 29, z)
            }
            RedButton(title: "Close", width: 68, height: 19, z: z) { NSApp.keyWindow?.performClose(nil) }
                .frame(width: 73 * z, height: 20 * z).place(w - 85, h - 29, z)
        }
        .onChange(of: ui.draft?.id) { armed = false }
    }

    func actions() -> [(String, () -> Void)] {
        if ui.optionsOpen {
            return [("Done", { ui.optionsOpen = false }), ("Default Keys", { Hotkeys.shared.reset() })]
        }
        if let draft = ui.draft {
            var out: [(String, () -> Void)] = [("Save", { draft.save() }), ("Cancel", { ui.draft = nil })]
            if let id = draft.questId {
                out.append((armed ? "Sure?" : "Delete", {
                    if armed {
                        Sound.shared.play("abandon")
                        if model.perform(.remove("\(draft.slug)/\(id)")) { ui.draft = nil; ui.selection = nil }
                    } else {
                        armed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { armed = false }
                    }
                }))
            }
            return out
        }
        guard let p = project, ui.noteIndex(in: p) == nil, let q = ui.quest(in: p) else { return [] }
        let ref = "\(p.slug)/\(q.id)", s = p.state(of: q)
        switch s {
        case .offered:
            return [("Accept", { Sound.shared.play("accept"); model.perform(.accept(ref)) }), ("Decline", { Sound.shared.play("close"); model.perform(.decline(ref)) })]
        case .declined, .abandoned:
            return [("Restore", { model.perform(.restore(ref)) })]
        default:
            var out: [(String, () -> Void)] = [("Abandon", { Sound.shared.play("abandon"); model.perform(.abandon(ref)) })]
            if s != .done {
                let tracked = model.isTracked(p, q)
                out.append((tracked ? "Untrack" : "Track", { model.perform(.track(ref, on: !tracked)) }))
                out.append(("Complete", { model.perform(.complete(ref)) }))
            }
            return out
        }
    }
}
