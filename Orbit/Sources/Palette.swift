import AppKit
import SwiftUI

@MainActor @Observable
final class PaletteModel {
    var query = "" { didSet { refresh() } }
    var results: [Cmd] = []
    var sections: [(title: String, range: Range<Int>)] = []
    var selected = 0
    var close: () -> Void = {}

    func refresh() {
        let raw = Catalog.results(query)
        // группировка: лучшее совпадение → секции по порядку
        var ordered: [Cmd] = []; var secs: [(String, Range<Int>)] = []
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let recent = raw.filter { Catalog.usage($0.id) > 0 }
            let rest = raw.filter { Catalog.usage($0.id) == 0 }
            if !recent.isEmpty { secs.append(("Недавние", 0..<recent.count)); ordered += recent }
            if !rest.isEmpty { secs.append(("Быстрые действия", ordered.count..<ordered.count + rest.count)); ordered += rest }
        } else if let first = raw.first {
            ordered = [first]; secs.append(("Лучшее совпадение", 0..<1))
            var groups: [(String, [Cmd])] = []
            for c in raw.dropFirst() {
                let s = Self.section(c)
                if let i = groups.firstIndex(where: { $0.0 == s }) { groups[i].1.append(c) } else { groups.append((s, [c])) }
            }
            for (t, cs) in groups { secs.append((t, ordered.count..<ordered.count + cs.count)); ordered += cs }
        }
        results = ordered; sections = secs; selected = 0
    }
    static func section(_ c: Cmd) -> String {
        let p = c.id.split(separator: ".").first.map(String.init) ?? c.id
        switch p {
        case "app": return "Приложения"
        case "win", "layout": return "Окна"
        case "snip": return "Сниппеты"
        case "repo", "branch": return "Проекты"
        case "web", "openurl": return "В сети"
        case "focus", "focusx", "report": return "Фокус"
        case "sys": return "Система"
        case "script": return "Скрипты"
        case "kill": return "Процессы"
        default: return "Инструменты"
        }
    }
    func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + d + results.count) % results.count
    }
    func run(alt: Bool = false, index: Int? = nil) {
        let i = index ?? selected
        guard results.indices.contains(i) else { return }
        let c = results[i]
        Catalog.used(c.id)
        let outcome = (alt ? c.alt : nil)?() ?? c.run()
        switch outcome {
        case .close: close()
        case .keep: refresh()
        case .setQuery(let q): query = q
        }
    }
}

@MainActor
final class Palette: NSObject, NSWindowDelegate {
    static let shared = Palette()
    private var panel: KeyablePanel!
    let model = PaletteModel()

    func toggle() { panel?.isVisible == true ? hide() : show() }

    func show() {
        if panel == nil { build() }
        model.query = ""
        model.refresh()
        let s = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let w: CGFloat = 700, h: CGFloat = 468
        let f = CGRect(x: s.frame.midX - w / 2, y: s.frame.maxY - s.frame.height * 0.2 - h, width: w, height: h)
        panel.setFrame(f.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.16; c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1; panel.animator().setFrame(f, display: true)
        }
    }
    func hide() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.1; p.animator().alphaValue = 0 },
                                            completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
    }

    private func build() {
        let p = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = .modalPanel
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.hidesOnDeactivate = false
        p.delegate = self
        model.close = { [weak self] in self?.hide() }
        p.contentView = NSHostingView(rootView: PaletteView(m: model).environment(\.colorScheme, .dark))
        panel = p
    }
    func windowDidResignKey(_ n: Notification) { hide() }
}

// MARK: - Вид

struct PaletteView: View {
    @Bindable var m: PaletteModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            search
            Rectangle().fill(DS.line).frame(height: 1)
            if m.query.isEmpty { suggestions.padding(.top, 12) }
            list
            actionBar
        }
        .background(GlassBackground(accent: .orbit, radius: 20, glow: 0.55))
        .onAppear { focused = true }
    }

    private var search: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Accent.orbit.gradient)
            TextField("", text: $m.query, prompt: Text("Что сделать? Приложение, команда, 2+2…").foregroundStyle(DS.text3))
                .textFieldStyle(.plain).font(.system(size: 21, weight: .regular)).foregroundStyle(DS.text)
                .focused($focused)
                .onSubmit { m.run() }
                .onKeyPress(.upArrow) { m.move(-1); return .handled }
                .onKeyPress(.downArrow) { m.move(1); return .handled }
                .onKeyPress(.escape) { m.close(); return .handled }
                .onKeyPress(keys: [.return], phases: .down) { p in
                    if p.modifiers.contains(.command) { m.run(alt: true); return .handled }
                    return .ignored
                }
                .onKeyPress(keys: [.tab], phases: .down) { _ in
                    if m.results.indices.contains(m.selected) { m.query = m.results[m.selected].title }
                    return .handled
                }
            Keycap(text: "esc")
        }
        .padding(.horizontal, 20).frame(height: 62)
    }

    /// Подсказки-чипы, когда поле пустое
    private var suggestions: some View {
        let chips: [(String, String, String)] = [("plusminus", "2*(3+4)", "2*(3+4)"), ("network", "port 3000", "port "),
            ("paintpalette", "#ff8800", "#ff8800"), ("curlybraces", "json", "json"), ("target", "focus 50", "focus 50"),
            ("arrow.triangle.branch", "git …", "git "), ("square.grid.2x2", "save Работа", "save ")]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.1) { s, t, q in
                    Button { m.query = q } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s).font(.system(size: 10, weight: .semibold)).foregroundStyle(Accent.orbit.a)
                            Text(t).font(DS.font(11.5, .medium, rounded: true)).foregroundStyle(DS.text2)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(DS.fill).overlay(Capsule().strokeBorder(DS.line)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(m.sections.enumerated()), id: \.offset) { _, sec in
                        SectionLabel(text: sec.title).padding(.leading, 12).padding(.top, 10).padding(.bottom, 4)
                        ForEach(Array(sec.range), id: \.self) { i in
                            PRow(c: m.results[i], selected: i == m.selected).id(i)
                                .onTapGesture { m.run(index: i) }
                                .onHover { if $0 { m.selected = i } }
                        }
                    }
                    if m.results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkle.magnifyingglass").font(.system(size: 28)).foregroundStyle(DS.text3)
                            Text("Ничего не нашлось").font(DS.font(13, .medium)).foregroundStyle(DS.text2)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 70)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: m.selected) { _, v in withAnimation(DS.snappy) { proxy.scrollTo(v, anchor: .center) } }
        }
    }

    private var actionBar: some View {
        let cur = m.results.indices.contains(m.selected) ? m.results[m.selected] : nil
        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Accent.orbit.gradient).frame(width: 9, height: 9).shadow(color: Accent.orbit.b, radius: 4)
                Text("Orbit").font(DS.font(12, .semibold, rounded: true)).foregroundStyle(DS.text2)
            }
            Spacer()
            if let cur {
                Text(cur.hint.isEmpty || cur.hint.contains("⌥") || cur.hint.contains("⌘") ? "Выполнить" : cur.hint.prefix(1).uppercased() + cur.hint.dropFirst())
                    .font(DS.font(11.5, .medium)).foregroundStyle(DS.text)
                Keycap(text: "↵")
                if cur.alt != nil {
                    Rectangle().fill(DS.line).frame(width: 1, height: 16)
                    Text(cur.altHint.prefix(1).uppercased() + cur.altHint.dropFirst()).font(DS.font(11.5, .medium)).foregroundStyle(DS.text2)
                    Keycap(text: "⌘"); Keycap(text: "↵")
                }
            }
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }
}

private struct PRow: View {
    let c: Cmd
    let selected: Bool
    var accent: Accent {
        switch c.tint { case "blue": .sky; case "orange": .orbit; case "red": .danger; case "green": .mint; case "pink": .shifty
        case "purple": .awake; case "gray": .gray; default: .orbit }
    }
    var body: some View {
        HStack(spacing: 12) {
            if let i = c.icon { Image(nsImage: i).resizable().interpolation(.high).frame(width: 30, height: 30) }
            else { IconTile(symbol: c.symbol, accent: accent, size: 28).padding(1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.system(size: 14, weight: .medium)).foregroundStyle(DS.text).lineLimit(1)
                if !c.subtitle.isEmpty { Text(c.subtitle).font(.system(size: 11.5)).foregroundStyle(DS.text3).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if !c.hint.isEmpty {
                if c.hint.contains("⌃") || c.hint.contains("⌥") || c.hint.contains("⌘") { Keycap(text: c.hint) }
                else { Text(c.hint).font(DS.font(11, .medium)).foregroundStyle(selected ? DS.text2 : DS.text3) }
            }
        }
        .padding(.horizontal, 10).frame(height: 48)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [accent.a.opacity(0.22), accent.b.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(accent.a.opacity(0.35), lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
    }
}
