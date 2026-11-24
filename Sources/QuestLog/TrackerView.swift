// The objective tracker floating over the desktop, and the new-quest window.
import AppKit
import QuestCore
import SwiftUI

struct TrackerView: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    @AppStorage("trackerCollapsed") var collapsed = false
    var onHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        let list = trackerList(model.projects, model.settings, limit: 3)
        let p = model.current
        VStack(alignment: .leading, spacing: 0) {
            header(p)
            if !collapsed {
                ForEach(Array(list.items.prefix(6)), id: \.ref) { item in entry(item) }
                if list.items.count > 6 {
                    Text("+\(list.items.count - 6) more").font(theme.ui(11 * 1)).foregroundStyle(Color(hex: 0x9B927F)).padding(.leading, 10).padding(.top, 2)
                }
                if list.items.isEmpty {
                    Text("No quests in progress.").font(theme.ui(12)).foregroundStyle(Color(hex: 0x9B927F)).padding(.horizontal, 10).padding(.vertical, 4)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(width: 314, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x0A0908, alpha: 0.72), Color(hex: 0x0A0908, alpha: 0.5)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x6A6050, alpha: 0.35), lineWidth: 1))
        )
        .padding(8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
    }

    func header(_ p: Project?) -> some View {
        let t = p?.totals ?? Totals()
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quests").font(theme.ui(14)).foregroundStyle(Color.gold).outlined()
                Spacer()
                Text("Level \(t.level)").font(theme.ui(11)).foregroundStyle(Color(hex: 0xD8CFBD)).outlined()
                Text(collapsed ? "+" : "−").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0xD8CFBD))
            }
            // Experience into the level.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.6))
                    Rectangle().fill(LinearGradient(colors: [Color(hex: 0xB77CFF), Color(hex: 0x6A2BB8)], startPoint: .top, endPoint: .bottom))
                        .frame(width: g.size.width * CGFloat(t.intoLevel) / CGFloat(xpPerLevel))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .simultaneousGesture(TapGesture(count: 2).onEnded { collapsed.toggle() })
        .help("Drag to move. Double-click to fold.")
    }

    func entry(_ item: QuestRef) -> some View {
        let p = item.project, q = item.quest, level = p.totals.level
        return VStack(alignment: .leading, spacing: 1) {
            Button { (NSApp.delegate as? AppDelegate)?.openLog(ref: item.ref) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(q.title).font(theme.ui(12.5)).foregroundStyle(Color.difficulty(difficulty(q, level: level))).outlined().lineLimit(1)
                    Text(p.chainName(q.chain)).font(theme.ui(10)).foregroundStyle(Color(hex: 0x8A826F)).outlined().lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if q.isDone {
                Text("Quest complete").font(theme.ui(11.5)).foregroundStyle(Color.gold).outlined().padding(.leading, 10)
            } else {
                let open = q.obj.filter { !$0.done }
                ForEach(Array(q.obj.filter { !$0.done || open.count < 4 }.prefix(4)), id: \.id) { o in
                    Button { model.perform(.objectives(ref: item.ref, select: [o.id], done: !o.done)) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("-").foregroundStyle(Color(hex: 0xBFB7A5))
                            Text(Rich.plain(o.text)).foregroundStyle(o.done ? Color(hex: 0x7A7466) : .white).strikethrough(o.done, color: Color(hex: 0x7A7466))
                        }
                        .font(theme.ui(11.5)).outlined().lineLimit(2)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if open.count > 4 { Text("+\(open.count - 4) more").font(theme.ui(10.5)).foregroundStyle(Color(hex: 0x9B927F)).padding(.leading, 20) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
    }
}

/// The game's quest window for a new offered quest: read it, then Accept or Decline.
struct OfferView: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var theme = Theme.shared
    let ref: String
    var close: () -> Void

    var body: some View {
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        let p = parts.count == 2 ? model.project(parts[0]) : nil, q = p?.quest(parts[1])
        ZStack(alignment: .topLeading) {
            if theme.themed, let img = theme.tex("quest-frame") {
                Image(nsImage: img).resizable().frame(width: 384, height: 478).frame(width: 384, height: 406, alignment: .top).clipped()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Color(hex: 0x2A2723), Color(hex: 0x15130F)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x6A6050), lineWidth: 2))
                    .frame(width: 368, height: 395).offset(x: 8, y: 8)
                Parchment().frame(width: 322, height: 333).offset(x: 22, y: 43)
            }
            Text(p?.title ?? "Quest").font(theme.ui(13)).foregroundStyle(Color.gold).outlined()
                .frame(width: 300, height: 20).contentShape(Rectangle()).gesture(WindowDragGesture()).offset(x: 18, y: 14)
            TexButton(up: "close-up", down: "close-down", glyph: "✕", z: 1, help: "Close", action: close).offset(x: theme.themed ? 322 : 344, y: theme.themed ? 8 : 6)
            if let p, let q {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.title).font(theme.title(18)).foregroundStyle(Color.inkHead)
                        if !q.lore.isEmpty { Text(q.lore).font(theme.ui(12.5)).foregroundStyle(Color(hex: 0x4A3017)) }
                        ForEach(q.desc.indices, id: \.self) { i in
                            richText(q.desc[i], font: theme.ui(12.5), z: 1).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Quest Objectives").font(theme.title(15.5)).foregroundStyle(Color.inkHead).padding(.top, 6)
                        ForEach(q.obj, id: \.id) { o in richText("- " + o.text, font: theme.ui(12.5), z: 1).fixedSize(horizontal: false, vertical: true) }
                        Text("Rewards").font(theme.title(15.5)).foregroundStyle(Color.inkHead).padding(.top, 6)
                        Text("\(q.xp) experience · \(whoName(q.who)) · Level \(q.lvl) · \(p.chainName(q.chain))").font(theme.ui(12)).foregroundStyle(Color.inkSoft)
                    }
                    .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: theme.themed ? 28 : 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(width: 322, height: 333).offset(x: 22, y: 43)
                RedButton(title: "Accept", width: 96, height: 21, z: 1) {
                    Sound.shared.play("accept"); model.perform(.accept(ref)); close()
                }.offset(x: 22, y: 378)
                RedButton(title: "Decline", width: 96, height: 21, z: 1) {
                    Sound.shared.play("close"); model.perform(.decline(ref)); close()
                }.offset(x: 246, y: 378)
            }
        }
        .frame(width: 384, height: 411, alignment: .topLeading)
    }
}
