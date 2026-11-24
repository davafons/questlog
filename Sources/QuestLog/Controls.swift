// Controls shared by the windows. Each draws the game's art when it was extracted and its own shapes otherwise.
import AppKit
import SwiftUI

/// The red panel button (Accept, Abandon, Close...).
struct RedButton: View {
    @ObservedObject var theme = Theme.shared
    let title: String
    let width: CGFloat
    let height: CGFloat
    let z: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if theme.themed, let up = theme.crop("button-up", CGRect(x: 1, y: 1, width: 78, height: 21)) {
                    Image(nsImage: up).resizable()
                    if hover, let hi = theme.crop("button-highlight", CGRect(x: 1, y: 1, width: 78, height: 21)) { Image(nsImage: hi).resizable().blendMode(.screen) }
                } else {
                    RoundedRectangle(cornerRadius: 3 * z)
                        .fill(LinearGradient(colors: [Color(hex: hover ? 0xC21D14 : 0x9B130C), Color(hex: 0x640905), Color(hex: 0x3A0402)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3 * z).strokeBorder(Color(hex: 0xB58A3A), lineWidth: max(1, z)))
                }
                Text(title).font(theme.ui(11 * z)).foregroundStyle(Color.gold).outlined().lineLimit(1)
            }
            .frame(width: width * z, height: height * z)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

/// Nudges a button down while pressed, like the game's buttons.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0).brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/// A square button drawn from a 32x32 texture (close, minimize), or a small red tile with a glyph.
struct TexButton: View {
    @ObservedObject var theme = Theme.shared
    let up: String
    let down: String?
    let glyph: String
    let z: CGFloat
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Group {
                if theme.themed, let img = theme.tex(up) {
                    Image(nsImage: img).resizable().frame(width: 32 * z, height: 32 * z).brightness(hover ? 0.12 : 0)
                } else {
                    RoundedRectangle(cornerRadius: 3 * z)
                        .fill(LinearGradient(colors: [Color(hex: 0xB3170F), Color(hex: 0x5C0603)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3 * z).strokeBorder(Color(hex: 0xD8A842), lineWidth: max(1, z * 0.8)))
                        .overlay(Text(glyph).font(.system(size: 11 * z, weight: .bold)).foregroundStyle(Color.gold))
                        .frame(width: 20 * z, height: 20 * z)
                        .frame(width: 32 * z, height: 32 * z)
                        .brightness(hover ? 0.12 : 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TexPressStyle(theme: theme, down: down, z: z))
        .onHover { hover = $0 }
        .help(help)
    }
}

struct TexPressStyle: ButtonStyle {
    let theme: Theme
    let down: String?
    let z: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        if configuration.isPressed, theme.themed, let down, let img = theme.tex(down) {
            Image(nsImage: img).resizable().frame(width: 32 * z, height: 32 * z)
        } else {
            configuration.label.brightness(configuration.isPressed ? -0.1 : 0)
        }
    }
}

/// The gear: the game's 16px options icon, or a drawn one.
struct GearButton: View {
    @ObservedObject var theme = Theme.shared
    let on: Bool
    let z: CGFloat
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Group {
                if let img = theme.tex("options") { Image(nsImage: img).resizable() }
                else { Image(systemName: "gearshape.fill").resizable().foregroundStyle(Color.gold) }
            }
            .frame(width: 16 * z, height: 16 * z)
            .brightness(hover || on ? 0.15 : -0.05)
            .shadow(color: on ? Color.gold.opacity(0.7) : .clear, radius: 2 * z)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Options")
    }
}

/// Scroll state of a ScrollView, shared with the scrollbar drawn in the frame's column.
@MainActor
final class ScrollModel: ObservableObject {
    @Published var position = ScrollPosition(edge: .top)
    @Published var offset: CGFloat = 0
    @Published var content: CGFloat = 0
    @Published var viewport: CGFloat = 0
    var maxOffset: CGFloat { max(0, content - viewport) }
    func scroll(to y: CGFloat) { position.scrollTo(y: min(maxOffset, max(0, y))) }
    func toTop() { position.scrollTo(edge: .top) }
}

extension View {
    /// A ScrollView without macOS scrollbars that reports its state to `model`.
    func trackedScroll(_ model: ScrollModel) -> some View {
        ScrollView(.vertical) { self }
            .scrollIndicators(.never)
            .scrollPosition(Binding(get: { model.position }, set: { model.position = $0 }))
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentOffset.y, $0.contentSize.height, $0.containerSize.height] } action: { _, v in
                model.offset = v[0]; model.content = v[1]; model.viewport = v[2]
            }
    }
}

/// Scrollbar with the game's arrow and knob art (or drawn ones), for the frame's narrow columns.
struct ScrollBar: View {
    @ObservedObject var model: ScrollModel
    @ObservedObject var theme = Theme.shared
    let z: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        let off = model.maxOffset <= 1
        VStack(spacing: 0) {
            arrow("scroll-up", up: true).onTapGesture { model.scroll(to: model.offset - 48) }
            GeometryReader { geo in
                let knob = 19 * z, room = max(1, geo.size.height - knob)
                let y = model.maxOffset > 0 ? room * model.offset / model.maxOffset : 0
                ZStack(alignment: .top) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { loc in model.scroll(to: model.offset + (loc.y < y ? -1 : 1) * model.viewport * 0.9) }
                    if !off {
                        knobView.frame(width: 20 * z, height: knob).offset(y: y)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                                if dragStart == nil { dragStart = model.offset }
                                model.scroll(to: (dragStart ?? 0) + g.translation.height / room * model.maxOffset)
                            }.onEnded { _ in dragStart = nil })
                    }
                }
            }
            arrow("scroll-down", up: false).onTapGesture { model.scroll(to: model.offset + 48) }
        }
        .opacity(off ? 0.4 : 1)
        .saturation(off ? 0 : 1)
        .allowsHitTesting(!off)
    }

    @ViewBuilder func arrow(_ name: String, up: Bool) -> some View {
        Group {
            if theme.themed, let img = theme.crop(name, CGRect(x: 6, y: 7, width: 20, height: 18)) { Image(nsImage: img).resizable() }
            else {
                RoundedRectangle(cornerRadius: 2 * z).fill(LinearGradient(colors: [Color(hex: 0x4A4540), Color(hex: 0x1C1A17)], startPoint: .top, endPoint: .bottom))
                    .overlay(Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8 * z, weight: .bold)).foregroundStyle(Color.gold))
            }
        }
        .frame(width: 20 * z, height: 18 * z)
        .contentShape(Rectangle())
    }

    @ViewBuilder var knobView: some View {
        if theme.themed, let img = theme.crop("scroll-knob", CGRect(x: 5, y: 6, width: 21, height: 19)) { Image(nsImage: img).resizable() }
        else { RoundedRectangle(cornerRadius: 2 * z).fill(LinearGradient(colors: [Color(hex: 0x5A544C), Color(hex: 0x2A2620)], startPoint: .top, endPoint: .bottom)).padding(.horizontal, 2 * z) }
    }
}

/// Small square checkbox, dark (tracker, options) or on parchment.
struct CheckBox: View {
    let on: Bool
    let z: CGFloat
    var parchment = false
    var body: some View {
        ZStack {
            Rectangle().fill(parchment ? (on ? Color(hex: 0x3F6D1C) : Color(hex: 0xFFF8E1, alpha: 0.55)) : Color(hex: 0x0A0908))
            Rectangle().strokeBorder(parchment ? Color(hex: on ? 0x1F3A09 : 0x4A2E0C) : Color(hex: 0x6A6050), lineWidth: max(1, z * 0.8))
            if on { Image(systemName: "checkmark").font(.system(size: 8 * z, weight: .heavy)).foregroundStyle(parchment ? .white : Color.gold) }
        }
        .frame(width: 11 * z, height: 11 * z)
    }
}
