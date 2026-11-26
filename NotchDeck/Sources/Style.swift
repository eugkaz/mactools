import SwiftUI
import AppKit

// MARK: - Фирменный стиль NotchDeck «Signal»
// Спокойная монохромная основа; цвет — только как сигнал (LED, прогресс, активное состояние).

enum ND {
    static let mono = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let hair = Color.white.opacity(0.07)
    static let soft = Color.white.opacity(0.05)
    static let softHi = Color.white.opacity(0.09)
}

/// Точечная матрица (как LED-табло), проявляется из угла и гаснет к краям
struct DotField: View {
    var spacing: CGFloat = 9
    var center = UnitPoint(x: 0.92, y: 0)
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width * center.x, y: size.height * center.y)
            let maxD = hypot(size.width, size.height) * 0.62
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    let d = hypot(x - c.x, y - c.y) / maxD
                    let a = max(0, 1 - d)
                    if a > 0.02 {
                        let r: CGFloat = 0.55 + 0.35 * a
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(0.11 * a * a)))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// «Ушко» — вогнутое скругление, которым панель вырастает из верхнего края экрана (как у настоящей чёлки)
struct NotchEar: Shape {
    var right: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if right {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.minX, y: r.minY))
        } else {
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY))
        }
        p.closeSubpath()
        return p
    }
}

/// Светящийся LED-штрих (индикатор активного)
struct LEDDash: View {
    var width: CGFloat = 12
    var body: some View {
        let g = Prefs.shared.glow
        Capsule().fill(accent)
            .frame(width: width, height: 2)
            .shadow(color: accent.opacity(g ? 0.9 : 0), radius: 3)
            .shadow(color: accent.opacity(g ? 0.5 : 0), radius: 7)
    }
}

/// Заголовок секции: короткий акцентный штрих + моно-капс
struct DeckLabel: View {
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(accent.opacity(0.9)).frame(width: 8, height: 1.5)
            Text(text.uppercased()).font(ND.mono).tracking(1.4).foregroundStyle(DS.text3)
        }
    }
}

/// Уголки видоискателя вместо пунктирной рамки
struct CornerBrackets: Shape {
    var len: CGFloat = 14
    var radius: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = radius
        // ↖
        p.move(to: CGPoint(x: r.minX, y: r.minY + len)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + k))
        p.addQuadCurve(to: CGPoint(x: r.minX + k, y: r.minY), control: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        // ↗
        p.move(to: CGPoint(x: r.maxX - len, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - k, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + k), control: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        // ↘
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - len)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k))
        p.addQuadCurve(to: CGPoint(x: r.maxX - k, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - len, y: r.maxY))
        // ↙
        p.move(to: CGPoint(x: r.minX + len, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + k, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - k), control: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - len))
        return p
    }
}

/// Виниловая пластинка: бороздки, блик, в центре — обложка как «яблоко»
struct Vinyl: View {
    var art: NSImage?
    var tint: Color
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = size.width / 2
                var r = R * 0.95
                var i = 0
                while r > R * 0.4 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(i % 5 == 0 ? 0.09 : 0.035)), lineWidth: 0.5)
                    r -= 1.6; i += 1
                }
            }
            // блик — неподвижен относительно пластинки не нужен: он вращается вместе с ней и даёт «живость»
            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.13), .clear, .clear, .white.opacity(0.09), .clear],
                                          center: .center))
            Group {
                if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                else { tint.opacity(0.8) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(Circle())
            .padding(.horizontal, 0)
            .scaleEffect(0.36)
            Circle().fill(Color.black).frame(width: 3.5, height: 3.5)
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.6), radius: 4, x: 2)
    }
}

/// Прогресс-шкала из засечек (как линейка/плёнка). Перетаскивается.
struct TickScrub: View {
    let value: Double
    let change: (Double) -> Void
    let commit: (Double) -> Void
    @State private var hover = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = min(max(value, 0), 1)
            let active = hover || dragging
            let a = accent
            Canvas { ctx, size in
                let step: CGFloat = 3.5
                let n = Int(size.width / step)
                let mid = size.height / 2
                for i in 0...n {
                    let x = CGFloat(i) * step + 0.5
                    let major = i % 8 == 0
                    let h: CGFloat = (major ? 7 : 4) * (active ? 1.25 : 1)
                    let passed = x <= size.width * v
                    let rect = CGRect(x: x - 0.5, y: mid - h / 2, width: 1, height: h)
                    ctx.fill(Path(rect), with: .color(passed ? a.opacity(major ? 1 : 0.85) : .white.opacity(major ? 0.22 : 0.12)))
                }
            }
            .overlay(alignment: .leading) {   // головка
                Capsule().fill(.white).frame(width: 2, height: active ? 13 : 11)
                    .shadow(color: a.opacity(0.9), radius: 3)
                    .offset(x: w * v - 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in dragging = true; change(min(max(e.location.x / w, 0), 1)) }
                .onEnded { e in dragging = false; commit(min(max(e.location.x / w, 0), 1)) })
            .onHover { h in withAnimation(DS.snappy) { hover = h } }
        }
        .frame(height: 14)
    }
}

/// Сегментный LED-индикатор (10 делений)
struct LEDMeter: View {
    var value: Double
    var segments = 12
    var body: some View {
        let lit = Int((min(max(value, 0), 1) * Double(segments)).rounded(.up))
        let warn = value > 0.85 ? Accent.danger.a : (value > 0.65 ? Accent.warn.a : accent)
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < lit ? warn : Color.white.opacity(0.08))
                    .shadow(color: i < lit ? warn.opacity(0.7) : .clear, radius: 2)
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: lit)
    }
}

/// Сегменты-«вкладки» с LED-штрихом снизу (без заливок)
struct FlatSegmented<T: Hashable>: View {
    var items: [(T, String)]
    var selection: T
    var spacing: CGFloat = 14
    var onSelect: (T) -> Void
    @Namespace private var ns
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.0) { v, title in
                let on = v == selection
                VStack(spacing: 4) {
                    Text(title).font(.system(size: 11.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? DS.text : DS.text3)
                        .lineLimit(1).fixedSize()
                    ZStack { if on { LEDDash(width: 14).matchedGeometryEffect(id: "seg", in: ns) } }.frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(DS.spring) { onSelect(v) } }
            }
        }
    }
}

/// Ровная кнопка-иконка без рамки
struct GhostIcon: View {
    let icon: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(hover ? DS.text : DS.text2)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? ND.softHi : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale()).help(help)
        .onHover { h in withAnimation(DS.snappy) { hover = h } }
    }
}

/// Тонкая разделительная линия, гаснущая к краям
struct HairDivider: View {
    var vertical = false
    var body: some View {
        let g = LinearGradient(colors: [.clear, .white.opacity(0.09), .clear],
                               startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
        Rectangle().fill(g).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Настройки внешнего вида (общие для Mac и пульта)

@Observable
final class Prefs {
    static let shared = Prefs()
    private static let d = UserDefaults.standard

    /// cover — по обложке; иначе фиксированная палитра
    var palette = d.string(forKey: "ui.palette") ?? "cover" { didSet { save() } }
    /// vinyl · cassette · plain
    var medium = d.string(forKey: "ui.medium") ?? "vinyl" { didSet { save() } }
    /// ticks · wave · line
    var progress = d.string(forKey: "ui.progress") ?? "ticks" { didSet { save() } }
    /// dots · grid · scan · none
    var pattern = d.string(forKey: "ui.pattern") ?? "dots" { didSet { save() } }
    var glow = d.object(forKey: "ui.glow") as? Bool ?? true { didSet { save() } }
    var showIndex = d.object(forKey: "ui.index") as? Bool ?? true { didSet { save() } }
    var sweep = d.object(forKey: "ui.sweep") as? Bool ?? true { didSet { save() } }

    static let palettes: [(id: String, name: String, accent: Accent)] = [
        ("cyan", "Циан", Accent.deck),
        ("violet", "Фиалка", Accent(a: Color(hex: 0xB46CFF), b: Color(hex: 0x6C5BFF))),
        ("mint", "Мята", Accent.mint),
        ("amber", "Янтарь", Accent(a: Color(hex: 0xFFC14D), b: Color(hex: 0xFF8A3D))),
        ("rose", "Роза", Accent(a: Color(hex: 0xFF5A8A), b: Color(hex: 0xFF3D6E))),
        ("mono", "Моно", Accent(a: Color(white: 0.93), b: Color(white: 0.62))),
    ]
    var fixedAccent: Accent? { Prefs.palettes.first { $0.id == palette }?.accent }

    var json: [String: Any] {
        ["palette": palette, "medium": medium, "progress": progress, "pattern": pattern, "glow": glow]
    }

    private func save() {
        let d = Prefs.d
        d.set(palette, forKey: "ui.palette"); d.set(medium, forKey: "ui.medium"); d.set(progress, forKey: "ui.progress")
        d.set(pattern, forKey: "ui.pattern"); d.set(glow, forKey: "ui.glow"); d.set(showIndex, forKey: "ui.index")
        d.set(sweep, forKey: "ui.sweep")
        RemoteServer.shared.changed()      // пульт подхватит новый стиль
    }
}

// MARK: - Фоновые узоры

/// Узор фона по настройке: точечная матрица, чертёжная сетка, ЭЛТ-развёртка
struct PatternField: View {
    var kind = Prefs.shared.pattern
    var body: some View {
        switch kind {
        case "dots": DotField()
        case "grid": GridField()
        case "scan": ScanField()
        default: EmptyView()
        }
    }
}

/// Чертёжная сетка с крестиками на пересечениях, гаснет от угла
struct GridField: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width * 0.92, y: 0)
            let maxD = hypot(size.width, size.height) * 0.7
            let step: CGFloat = 18
            func a(_ p: CGPoint) -> Double { max(0, 1 - hypot(p.x - c.x, p.y - c.y) / maxD) }
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let k = a(CGPoint(x: x, y: y))
                    if k > 0.02 {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + step, y: y))
                        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + step))
                        ctx.stroke(p, with: .color(.white.opacity(0.045 * k)), lineWidth: 0.5)
                        // крестик на каждом 4-м пересечении
                        if Int(x / step) % 4 == 0 && Int(y / step) % 4 == 0 {
                            var cr = Path()
                            cr.move(to: CGPoint(x: x - 3, y: y)); cr.addLine(to: CGPoint(x: x + 3, y: y))
                            cr.move(to: CGPoint(x: x, y: y - 3)); cr.addLine(to: CGPoint(x: x, y: y + 3))
                            ctx.stroke(cr, with: .color(.white.opacity(0.22 * k)), lineWidth: 0.7)
                        }
                    }
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// ЭЛТ-развёртка: тонкие горизонтальные линии + мягкое «свечение люминофора»
struct ScanField: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [accent.opacity(0.10), .clear], center: UnitPoint(x: 0.9, y: 0), startRadius: 0, endRadius: 300)
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(.white.opacity(0.035)))
                    y += 3
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Световая развёртка при смене вкладки: акцентная линия пробегает слева направо
struct ScanSweep<T: Equatable>: View {
    let trigger: T
    @State private var x: CGFloat = 1.3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [.clear, accent.opacity(0.10)], startPoint: .leading, endPoint: .trailing).frame(width: 60)
                Rectangle().fill(accent).frame(width: 1.5).shadow(color: accent, radius: 4)
            }
            .frame(width: 62, height: g.size.height)
            .offset(x: g.size.width * x - 62)
            .opacity(x > 1.05 || x < 0 ? 0 : 1)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard Prefs.shared.sweep else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { x = 0 }
            withAnimation(.easeOut(duration: 0.45)) { x = 1.2 }
        }
    }
}

// MARK: - Кассета: катушки крутятся, плёнка перематывается с левой на правую по ходу трека

struct Cassette: View {
    var art: NSImage?
    var title: String
    var progress: Double      // 0…1
    var angle: Double         // поворот втулок, градусы

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                // корпус
                RoundedRectangle(cornerRadius: h * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: h * 0.08, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
                // наклейка: обложка + название
                ZStack(alignment: .topLeading) {
                    Group {
                        if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                        else { LinearGradient(colors: [accent.opacity(0.7), accentB.opacity(0.5)], startPoint: .leading, endPoint: .trailing) }
                    }
                    .frame(width: w * 0.86, height: h * 0.62).clipped()
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                    HStack(spacing: 3) {
                        Text("A").font(.system(size: max(6, h * 0.09), weight: .heavy, design: .monospaced)).foregroundStyle(accent)
                        Text(title.uppercased()).font(.system(size: max(5.5, h * 0.075), weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    .padding(.horizontal, 5).padding(.top, 3)
                }
                .frame(width: w * 0.86, height: h * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.top, h * 0.07)
                // окно с катушками
                let ww = w * 0.56, wh = h * 0.3
                ZStack {
                    Capsule().fill(Color.black.opacity(0.85))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                    HStack {
                        reel(wh, tape: 1 - progress)
                        Spacer(minLength: 0)
                        reel(wh, tape: progress)
                    }
                    .padding(.horizontal, wh * 0.22)
                    .clipShape(Capsule())          // плёнка видна только в окошке
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                }
                .frame(width: ww, height: wh)
                .padding(.top, h * 0.37)
                // нижняя трапеция с винтиками
                Trapezoid().fill(Color(white: 0.13))
                    .overlay(Trapezoid().stroke(.white.opacity(0.08), lineWidth: 0.5))
                    .overlay(HStack(spacing: w * 0.32) { screw(h); screw(h) })
                    .frame(width: w * 0.62, height: h * 0.16)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 6, x: 2, y: 3)
    }

    func reel(_ wh: CGFloat, tape: Double) -> some View {
        let hub = wh * 0.52
        let full = wh * 1.25
        let d = hub + (full - hub) * CGFloat(tape)
        return ZStack {
            Circle().fill(Color(red: 0.24, green: 0.17, blue: 0.13)).frame(width: d, height: d)     // намотанная плёнка
            Circle().fill(Color(white: 0.88)).frame(width: hub, height: hub)
            ForEach(0..<6, id: \.self) { i in                                                      // зубцы втулки
                Capsule().fill(Color(white: 0.3)).frame(width: hub * 0.12, height: hub * 0.3)
                    .offset(y: -hub * 0.3).rotationEffect(.degrees(Double(i) * 60 + angle))
            }
            Circle().fill(Color(white: 0.2)).frame(width: hub * 0.3, height: hub * 0.3)
        }
        .frame(width: hub, height: hub)
    }

    func screw(_ h: CGFloat) -> some View {
        Circle().fill(Color(white: 0.3)).frame(width: h * 0.06, height: h * 0.06)
            .overlay(Rectangle().fill(Color(white: 0.12)).frame(width: h * 0.05, height: 0.6))
    }
}

struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.08, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Прогресс «волна»: силуэт трека из столбиков (стабилен для каждого трека)

struct WaveScrub: View {
    let value: Double
    let seed: String
    let change: (Double) -> Void
    let commit: (Double) -> Void
    @State private var hover = false
    @State private var dragging = false

    static func level(_ i: Int, _ s: Double) -> CGFloat {
        let x = Double(i)
        let v = abs(sin(x * 0.31 + s) * 0.6 + sin(x * 0.083 + s * 1.7) * 0.4)
        return CGFloat(0.18 + 0.82 * min(1, v))
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = min(max(value, 0), 1)
            let a = accent
            let s = Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 100_003 }) / 37   // стабильно для трека
            let active = hover || dragging
            Canvas { ctx, size in
                let step: CGFloat = 3
                let n = Int(size.width / step)
                for i in 0..<n {
                    let x = CGFloat(i) * step
                    let h = size.height * Self.level(i, s) * (active ? 1 : 0.85)
                    let passed = x <= size.width * v
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: 1.8, height: h), cornerRadius: 0.9),
                             with: .color(passed ? a : .white.opacity(0.16)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in dragging = true; change(min(max(e.location.x / w, 0), 1)) }
                .onEnded { e in dragging = false; commit(min(max(e.location.x / w, 0), 1)) })
            .onHover { h in withAnimation(DS.snappy) { hover = h } }
        }
        .frame(height: 16)
    }
}

// MARK: - Экран настроек внешнего вида

struct SettingsView: View {
    @Bindable var p = Prefs.shared
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                row("Цвет", 64) {
                    HStack(spacing: 5) {
                        swatch("cover", AnyShapeStyle(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .purple, .pink], center: .center)))
                        ForEach(Prefs.palettes, id: \.id) { pal in swatch(pal.id, AnyShapeStyle(pal.accent.gradient)) }
                    }
                }
                row("Носитель", 64) {
                    FlatSegmented(items: [("vinyl", "Винил"), ("cassette", "Кассета"), ("plain", "Обложка")], selection: p.medium, spacing: 10) { p.medium = $0 }
                }
                row("Прогресс", 64) {
                    FlatSegmented(items: [("ticks", "Шкала"), ("wave", "Волна"), ("line", "Линия")], selection: p.progress, spacing: 10) { p.progress = $0 }
                }
            }
            HairDivider(vertical: true).frame(height: 96)
            VStack(alignment: .leading, spacing: 8) {
                row("Фон", 34) {
                    FlatSegmented(items: [("dots", "Точки"), ("grid", "Сетка"), ("scan", "Скан"), ("none", "Нет")], selection: p.pattern, spacing: 10) { p.pattern = $0 }
                }
                HStack(alignment: .top, spacing: 10) {
                    Text("ЕЩЁ").font(ND.mono).tracking(1.3).foregroundStyle(DS.text3).frame(width: 34, alignment: .leading).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        chip("Свечение", $p.glow)
                        chip("Номер вкладки", $p.showIndex)
                        chip("Развёртка при смене", $p.sweep)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    func row<C: View>(_ title: String, _ w: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased()).font(ND.mono).tracking(1.3).foregroundStyle(DS.text3).frame(width: w, alignment: .leading)
            c()
            Spacer(minLength: 0)
        }
    }

    func swatch(_ id: String, _ fill: AnyShapeStyle) -> some View {
        let on = p.palette == id
        return Circle().fill(fill).frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.5))
            .padding(2)
            .overlay(Circle().strokeBorder(.white.opacity(on ? 0.9 : 0), lineWidth: 1.2))
            .scaleEffect(on ? 1.08 : 1)
            .contentShape(Circle())
            .onTapGesture { withAnimation(DS.spring) { p.palette = id } }
            .help(id == "cover" ? "По обложке трека" : (Prefs.palettes.first { $0.id == id }?.name ?? ""))
    }

    func chip(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 5) {
            Circle().fill(on.wrappedValue ? accent : Color.white.opacity(0.18)).frame(width: 5, height: 5)
                .shadow(color: on.wrappedValue && p.glow ? accent : .clear, radius: 3)
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(on.wrappedValue ? DS.text : DS.text3)
        }
        .padding(.horizontal, 8).frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on.wrappedValue ? ND.softHi : ND.soft))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(DS.snappy) { on.wrappedValue.toggle() } }
    }
}
