// Look of the app: art extracted from the user's own World of Warcraft install (~/.questlog/theme), when it is there,
// and otherwise drawn shapes with the bundled OFL fonts (Marcellus, Almendra).
import AppKit
import CoreText
import QuestCore
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    static let gold = Color(hex: 0xFFD100)
    static let qGray = Color(hex: 0x808080)
    static let qGreen = Color(hex: 0x40C040)
    static let qYellow = Color(hex: 0xFFFF00)
    static let qOrange = Color(hex: 0xFF8040)
    static let qRed = Color(hex: 0xFF2020)
    static let ink = Color.black
    static let inkHead = Color(hex: 0x1B0E00)
    static let inkSoft = Color(hex: 0x4A3017)
    static let parchText = Color(hex: 0xBFB7A5)

    static func difficulty(_ d: Difficulty) -> Color {
        switch d { case .red: .qRed; case .orange: .qOrange; case .yellow: .qYellow; case .green: .qGreen; case .gray: .qGray }
    }
}

@MainActor
final class Theme: ObservableObject {
    static let shared = Theme()

    @Published private(set) var textures: [String: NSImage] = [:]
    @Published private(set) var uiFamily = "Marcellus"
    @Published private(set) var titleFamily = "Almendra"
    @Published private(set) var sounds: [String: URL] = [:]
    private var slices: [String: [NSImage]] = [:]
    private var registered = Set<String>()
    let store = Store()

    /// The log and quest windows use the game's frames only when the art was extracted.
    var themed: Bool { textures["questlog-frame"] != nil }

    init() {
        registerBundledFonts()
        reload()
    }

    func reload() {
        var tex: [String: NSImage] = [:]
        for (name, url) in store.themeFiles("textures", extensions: ["png", "jpg", "jpeg", "webp"]) {
            if let img = NSImage(contentsOf: url) { tex[name] = img }
        }
        textures = tex
        slices = [:]
        sounds = store.themeFiles("sounds", extensions: ["ogg", "mp3", "wav", "m4a", "caf", "aiff"])
        let fonts = store.themeFiles("fonts", extensions: ["ttf", "otf"])
        uiFamily = fonts["ui"].flatMap(register) ?? "Marcellus"
        titleFamily = fonts["title"].flatMap(register) ?? "Almendra"
    }

    func tex(_ name: String) -> NSImage? { textures[name] }

    func ui(_ size: CGFloat) -> Font { .custom(uiFamily, fixedSize: size) }
    func title(_ size: CGFloat) -> Font { .custom(titleFamily, fixedSize: size) }
    func nsUI(_ size: CGFloat) -> NSFont { NSFont(name: uiFamily, size: size) ?? .systemFont(ofSize: size) }

    /// Nine pieces of a texture for stretching: insets are top, left, bottom, right in image pixels.
    func slices(_ name: String, _ insets: (CGFloat, CGFloat, CGFloat, CGFloat)) -> [NSImage]? {
        if let s = slices[name] { return s }
        guard let img = textures[name], let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let (t, l, b, r) = insets
        let xs = [0, l, w - r, w], ys = [0, t, h - b, h]
        var parts: [NSImage] = []
        for row in 0..<3 {
            for col in 0..<3 {
                let rect = CGRect(x: xs[col], y: ys[row], width: xs[col + 1] - xs[col], height: ys[row + 1] - ys[row])
                guard let piece = cg.cropping(to: rect) else { return nil }
                parts.append(NSImage(cgImage: piece, size: rect.size))
            }
        }
        slices[name] = parts
        return parts
    }

    /// A rectangle cut out of a texture (pixels), e.g. the button art inside its 128x32 file.
    func crop(_ name: String, _ rect: CGRect) -> NSImage? {
        let key = "\(name)@\(rect)"
        if let s = slices[key]?.first { return s }
        guard let img = textures[name], let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), let piece = cg.cropping(to: rect) else { return nil }
        let out = NSImage(cgImage: piece, size: rect.size)
        slices[key] = [out]
        return out
    }

    // MARK: Fonts

    private func registerBundledFonts() {
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Fonts").standardized]
        for dir in dirs.compactMap({ $0 }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let fonts = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            if fonts.isEmpty { continue }
            fonts.forEach { _ = register($0) }
            return
        }
    }

    /// Registers a font file for this process and returns its family name.
    private func register(_ url: URL) -> String? {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descs.first else { return nil }
        if !registered.contains(url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            registered.insert(url.path)
        }
        return CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String
    }
}

/// Draws a texture stretched to fill its frame, keeping the corners and edges at `scale` times their pixel size.
struct NineSlice: View {
    let parts: [NSImage]
    let insets: (CGFloat, CGFloat, CGFloat, CGFloat)
    let scale: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let (t, l, b, r) = (insets.0 * scale, insets.1 * scale, insets.2 * scale, insets.3 * scale)
            let xs = [0, l, max(l, size.width - r), size.width], ys = [0, t, max(t, size.height - b), size.height]
            for row in 0..<3 {
                for col in 0..<3 {
                    let rect = CGRect(x: xs[col], y: ys[row], width: xs[col + 1] - xs[col], height: ys[row + 1] - ys[row])
                    if rect.width > 0, rect.height > 0 { ctx.draw(Image(nsImage: parts[row * 3 + col]).resizable(), in: rect) }
                }
            }
        }
    }
}

/// Shadowed text, like the game's outlined interface font.
extension View {
    func outlined() -> some View { shadow(color: .black, radius: 0, x: 1, y: 1) }
}
