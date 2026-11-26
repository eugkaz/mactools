import SwiftUI
import AppKit

// MARK: - Дизайн-система «Midnight Glass» — общая для всех приложений

enum DS {
    // поверхности
    static let bg0 = Color(hex: 0x0B0C10)
    static let bg1 = Color(hex: 0x121319)
    static let bg2 = Color(hex: 0x1A1B22)
    static let line = Color.white.opacity(0.08)
    static let lineHi = Color.white.opacity(0.14)
    static let fill = Color.white.opacity(0.045)
    static let fillHi = Color.white.opacity(0.085)
    // текст
    static let text = Color.white.opacity(0.94)
    static let text2 = Color.white.opacity(0.58)
    static let text3 = Color.white.opacity(0.34)

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.85)

    static func font(_ size: CGFloat, _ w: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(size: size, weight: w, design: rounded ? .rounded : .default)
    }
}

/// Фирменная палитра приложения
struct Accent: Equatable {
    var a: Color, b: Color
    var gradient: LinearGradient { LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static let shifty = Accent(a: Color(hex: 0xB46CFF), b: Color(hex: 0xFF4FA3))
    static let deck = Accent(a: Color(hex: 0x3EE6FF), b: Color(hex: 0x5B7CFF))
    static let awake = Accent(a: Color(hex: 0x9D7BFF), b: Color(hex: 0x5B5FFF))
    static let awakeOn = Accent(a: Color(hex: 0x5CF2B5), b: Color(hex: 0x1FB8FF))
    static let orbit = Accent(a: Color(hex: 0xFFB547), b: Color(hex: 0xFF3D6E))
    static let reel = Accent(a: Color(hex: 0xFF5A7A), b: Color(hex: 0x9B4DFF))
    static let warn = Accent(a: Color(hex: 0xFFC14D), b: Color(hex: 0xFF7A3D))
    static let danger = Accent(a: Color(hex: 0xFF6B6B), b: Color(hex: 0xE5266B))
    static let mint = Accent(a: Color(hex: 0x5CF2B5), b: Color(hex: 0x19C99A))
    static let sky = Accent(a: Color(hex: 0x6CC8FF), b: Color(hex: 0x4A7BFF))
    static let gray = Accent(a: Color(hex: 0x8A8F9C), b: Color(hex: 0x5D6170))
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Accent.orbit }
extension EnvironmentValues { var accent: Accent { get { self[AccentKey.self] } set { self[AccentKey.self] = newValue } } }

extension Color {
    init(hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: alpha)
    }
}

// MARK: - Фон окна: глубокий тёмный + свечение акцента

struct GlassBackground: View {
    var accent: Accent
    var radius: CGFloat = 22
    var glow: Double = 1
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.bg0)
            // свечение сверху
            RadialGradient(colors: [accent.a.opacity(0.32 * glow), .clear], center: UnitPoint(x: 0.15, y: -0.05), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [accent.b.opacity(0.20 * glow), .clear], center: UnitPoint(x: 1.0, y: 0.0), startRadius: 0, endRadius: 260)
            LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: .center)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
    }
}

// MARK: - Карточка

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var radius: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.fill)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
            )
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(DS.text3)
    }
}

// MARK: - Иконка-плитка с градиентом и бликом

struct IconTile: View {
    var symbol: String
    var accent: Accent
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(accent.gradient)
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: accent.b.opacity(0.35), radius: 6, y: 3)
    }
}

// MARK: - Переключатель

struct GlowToggleStyle: ToggleStyle {
    var accent: Accent
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 10) {
            c.label
            Spacer(minLength: 6)
            ZStack(alignment: c.isOn ? .trailing : .leading) {
                Capsule().fill(c.isOn ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(c.isOn ? 0.25 : 0.08), lineWidth: 0.7))
                    .shadow(color: c.isOn ? accent.b.opacity(0.5) : .clear, radius: 6)
                Circle().fill(.white).padding(2.5).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: 36, height: 21)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(DS.spring) { c.isOn.toggle() } }
        }
    }
}

// MARK: - Кнопки

struct PillButtonStyle: ButtonStyle {
    var accent: Accent? = nil      // nil — стеклянная
    var height: CGFloat = 30
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent == nil ? DS.text : .white)
            .padding(.horizontal, 14).frame(height: height)
            .background(
                Capsule().fill(accent.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(DS.fillHi))
                    .overlay(Capsule().strokeBorder(.white.opacity(accent == nil ? 0.1 : 0.25), lineWidth: 0.7))
                    .shadow(color: accent?.b.opacity(0.4) ?? .clear, radius: 8, y: 3)
            )
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .brightness(c.isPressed ? -0.05 : 0)
            .animation(DS.snappy, value: c.isPressed)
    }
}

/// Круглая кнопка-иконка (закрыть, шестерёнка…)
struct CircleIconButton: View {
    var symbol: String
    var size: CGFloat = 26
    var active = false
    var accent: Accent = .gray
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(active ? .white : (hover ? DS.text : DS.text2))
                .frame(width: size, height: size)
                .background(Circle().fill(active ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(hover ? DS.fillHi : DS.fill)))
                .overlay(Circle().strokeBorder(DS.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DS.snappy) { hover = h } }
    }
}

/// Клавиша-подсказка
struct Keycap: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(DS.text2)
            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 19)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
            )
    }
}

/// Сегменты со скользящим выделением
struct Segmented<T: Hashable>: View {
    var items: [(T, String)]
    var selection: T?
    var accent: Accent
    var onSelect: (T) -> Void
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { v, title in
                let on = v == selection
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(on ? .white : DS.text2)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background {
                        if on {
                            Capsule().fill(accent.gradient).matchedGeometryEffect(id: "sel", in: ns)
                                .shadow(color: accent.b.opacity(0.45), radius: 6, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(DS.spring) { onSelect(v) } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)).overlay(Capsule().strokeBorder(DS.line, lineWidth: 1)))
    }
}

/// Тонкая полоса прогресса с градиентом
struct GlowBar: View {
    var value: Double
    var accent: Accent
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(accent.gradient).frame(width: max(height, g.size.width * min(1, max(0, value))))
                    .shadow(color: accent.b.opacity(0.6), radius: 3)
            }
        }
        .frame(height: height)
    }
}

/// Пульсирующая точка «живое»
struct LiveDot: View {
    var color: Color
    var active: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            if active {
                Circle().fill(color.opacity(0.35)).scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 1)
            }
            Circle().fill(active ? color : DS.text3)
        }
        .frame(width: 7, height: 7)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

extension View {
    /// Подсветка при наведении
    func hoverHighlight(radius: CGFloat = 10) -> some View { modifier(HoverHL(radius: radius)) }
}
private struct HoverHL: ViewModifier {
    var radius: CGFloat
    @State private var h = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(h ? DS.fill : .clear))
            .onHover { v in withAnimation(DS.snappy) { h = v } }
    }
}

// MARK: - Своя «выпадашка» из строки меню вместо стандартного поповера

@MainActor
final class MenuBarPanel: NSObject {
    private(set) var panel: NSPanel!
    private var monitors: [Any] = []
    var onClose: (() -> Void)?
    var isShown: Bool { panel?.isVisible == true }

    init<V: View>(width: CGFloat, @ViewBuilder content: () -> V) {
        super.init()
        let p = KeyablePanel(contentRect: CGRect(x: 0, y: 0, width: width, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isMovable = false
        let host = NSHostingView(rootView: content().environment(\.colorScheme, .dark))
        host.sizingOptions = [.preferredContentSize]
        p.contentView = host
        panel = p
    }

    func toggle(from button: NSStatusBarButton) { isShown ? close() : show(from: button) }

    func show(from button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let screen = bw.screen ?? NSScreen.main!
        var x = r.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let top = r.minY - 6
        let f = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(f, display: true)
        panel.alphaValue = 0
        panel.contentView?.layer?.anchorPoint = .zero
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.16; c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // закрытие по клику мимо и Esc
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.close() }; return nil }
            return e
        } as Any)
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll()
        guard isShown else { return }
        let p = panel!
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.12; p.animator().alphaValue = 0 },
                                            completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
        onClose?()
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Снимки интерфейса для проверки дизайна (SNAPSHOT_DIR=… ./App)

@MainActor
enum Snapshot {
    static var dir: String? { ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] }

    /// Рендерит SwiftUI-вид в PNG через настоящее окно (видны и AppKit-контролы)
    static func save<V: View>(_ name: String, width: CGFloat? = nil, height: CGFloat? = nil, _ view: V) {
        guard let dir else { return }
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        var size = host.fittingSize
        if let width { size.width = width }
        if let height { size.height = height }
        let w = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: 0), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = NSColor(white: 0.5, alpha: 1)
        w.contentView = host
        w.orderFront(nil)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        w.orderOut(nil)
    }
}

// MARK: - Свой слайдер (тонкий, со свечением, утолщается при наведении)

struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var accent: Accent
    var onCommit: ((Double) -> Void)? = nil
    @State private var hover = false
    @State private var drag: Double?

    var body: some View {
        GeometryReader { g in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let v = drag ?? value
            let p = CGFloat((v - range.lowerBound) / span).clamped(0, 1)
            let h: CGFloat = hover || drag != nil ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: h)
                Capsule().fill(accent.gradient).frame(width: max(h, g.size.width * p), height: h)
                    .shadow(color: accent.b.opacity(0.6), radius: 4)
                Circle().fill(.white).frame(width: 11, height: 11).shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: g.size.width * p - 5.5)
                    .opacity(hover || drag != nil ? 1 : 0)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    let nv = range.lowerBound + Double((e.location.x / g.size.width).clamped(0, 1)) * span
                    drag = nv
                    if onCommit == nil { value = nv }
                }
                .onEnded { _ in
                    if let d = drag { value = d; onCommit?(d) }
                    drag = nil
                })
            .animation(DS.snappy, value: hover)
        }
        .frame(height: 14)
        .onHover { hover = $0 }
    }
}

extension CGFloat {
    func clamped(_ a: CGFloat, _ b: CGFloat) -> CGFloat { Swift.min(Swift.max(self, a), b) }
}
