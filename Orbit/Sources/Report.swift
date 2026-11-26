import AppKit
import SwiftUI
import Charts

@MainActor
enum ReportWindow {
    private static var win: NSWindow?
    static func show() {
        FocusTracker.shared.save()
        if win == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 720),
                             styleMask: [.titled, .closable, .fullSizeContentView, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua); w.backgroundColor = NSColor(DS.bg0)
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: ReportView(t: FocusTracker.shared))
            w.minSize = NSSize(width: 680, height: 560)
            w.center(); win = w
        }
        NSApp.activate(); win?.makeKeyAndOrderFront(nil)
    }
}

struct ReportView: View {
    var t: FocusTracker
    @State private var week = FocusTracker.days(7)

    var body: some View {
        let d = t.today
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(d)
                HStack(spacing: 10) {
                    Tile(title: "Фокус-сессий", value: "\(d.focusSessions)", symbol: "target", accent: .orbit)
                    Tile(title: "В фокусе", value: Catalog.dur(d.focusSeconds), symbol: "timer", accent: .warn)
                    Tile(title: "Код и ИИ", value: Catalog.dur(d.cat(.code) + d.cat(.ai)), symbol: "chevron.left.forwardslash.chevron.right", accent: .sky)
                    Tile(title: "Отвлечения", value: Catalog.dur(d.cat(.fun)), symbol: "play.rectangle.fill", accent: .danger)
                }
                HStack(alignment: .top, spacing: 12) {
                    panel("Распределение", "chart.pie.fill") { donut(d) }.frame(width: 270)
                    panel("Неделя", "calendar") { weekChart }
                }
                HStack(alignment: .top, spacing: 12) {
                    panel("Приложения", "square.grid.2x2.fill") { top(d.apps) }
                    panel("Сайты", "globe") { top(d.domains) }
                }
            }
            .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 26)
        }
        .background(GlassBackground(accent: .orbit, radius: 0, glow: 0.8).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { week = FocusTracker.days(7) }
    }

    private func header(_ d: DayStats) -> some View {
        let p = d.total > 0 ? (d.cat(.code) + d.cat(.ai)) / d.total : 0
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(DS.font(12, .semibold)).foregroundStyle(Accent.orbit.a)
                Text("Твой день").font(DS.font(34, .bold, rounded: true)).foregroundStyle(DS.text)
                Text("За Маком \(Catalog.dur(d.total)) · \(verdict(p))").font(DS.font(13)).foregroundStyle(DS.text2)
            }
            Spacer()
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 10)
                Circle().trim(from: 0, to: max(0.001, p))
                    .stroke(AngularGradient(colors: [Accent.orbit.a, Accent.orbit.b, Accent.orbit.a], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Accent.orbit.b.opacity(0.6), radius: 8)
                VStack(spacing: 0) {
                    Text("\(Int(p * 100))%").font(DS.font(24, .bold, rounded: true)).foregroundStyle(DS.text)
                    Text("продуктивно").font(DS.font(9.5, .medium)).foregroundStyle(DS.text3)
                }
            }
            .frame(width: 104, height: 104)
        }
    }
    private func verdict(_ p: Double) -> String {
        p > 0.7 ? "огонь 🔥" : p > 0.45 ? "хороший темп" : p > 0.2 ? "можно лучше" : "день только начался"
    }

    private func panel<C: View>(_ title: String, _ sym: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: sym).font(.system(size: 11, weight: .semibold)).foregroundStyle(Accent.orbit.a)
                Text(title).font(DS.font(13, .semibold)).foregroundStyle(DS.text)
            }
            c()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.fill)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.line)))
    }

    private func donut(_ d: DayStats) -> some View {
        let cats = Cat.allCases.filter { d.cat($0) > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Chart(cats, id: \.self) { c in
                    SectorMark(angle: .value("t", d.cat(c)), innerRadius: .ratio(0.66), angularInset: 2)
                        .foregroundStyle(c.color.gradient).cornerRadius(4)
                }
                .chartLegend(.hidden)
                VStack(spacing: 0) {
                    Text(Catalog.dur(d.total)).font(DS.font(17, .bold, rounded: true)).foregroundStyle(DS.text)
                    Text("всего").font(DS.font(10)).foregroundStyle(DS.text3)
                }
            }
            .frame(height: 150)
            if cats.isEmpty { Text("Данные появятся через пару минут").font(DS.font(11)).foregroundStyle(DS.text3) }
            VStack(spacing: 6) {
                ForEach(cats.sorted { d.cat($0) > d.cat($1) }, id: \.self) { c in
                    HStack(spacing: 8) {
                        Circle().fill(c.color).frame(width: 7, height: 7)
                        Text(c.title).font(DS.font(12)).foregroundStyle(DS.text2)
                        Spacer()
                        Text(Catalog.dur(d.cat(c))).font(DS.font(12, .semibold, rounded: true)).foregroundStyle(DS.text).monospacedDigit()
                    }
                }
            }
        }
    }

    private var weekChart: some View {
        let maxH = week.map { $0.1.total }.max() ?? 0
        let inMin = maxH < 2 * 3600
        let div: Double = inMin ? 60 : 3600
        return Chart {
            ForEach(week, id: \.0) { day, s in
                ForEach(Cat.allCases, id: \.self) { c in
                    BarMark(x: .value("день", day, unit: .day), y: .value("t", s.cat(c) / div), width: .ratio(0.55))
                        .foregroundStyle(by: .value("кат", c.title)).cornerRadius(3)
                }
            }
        }
        .chartForegroundStyleScale(domain: Cat.allCases.map(\.title), range: Cat.allCases.map(\.color))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(DS.text3)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(DS.line)
                AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))\(inMin ? "м" : "ч")").foregroundStyle(DS.text3) } }
            }
        }
        .chartLegend(position: .bottom, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Cat.allCases, id: \.self) { c in
                    HStack(spacing: 4) { Circle().fill(c.color).frame(width: 6, height: 6); Text(c.title).font(DS.font(10)).foregroundStyle(DS.text3) }
                }
            }
        }
        .frame(height: 230)
    }

    private func top(_ dict: [String: Double]) -> some View {
        let items = dict.sorted { $0.value > $1.value }.prefix(7)
        let mx = items.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty { Text("пока пусто").font(DS.font(11)).foregroundStyle(DS.text3) }
            ForEach(Array(items), id: \.key) { k, v in
                let cat = Classifier.browsers[k] != nil ? Cat.browser : (k.contains(".") ? Classifier.domain(k) : Classifier.app(k))
                HStack(spacing: 10) {
                    appIcon(k).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(k).font(DS.font(12, .medium)).foregroundStyle(DS.text).lineLimit(1)
                            Spacer()
                            Text(Catalog.dur(v)).font(DS.font(11.5, .semibold, rounded: true)).foregroundStyle(DS.text2).monospacedDigit()
                        }
                        GeometryReader { g in
                            Capsule().fill(cat.color.gradient).frame(width: max(5, g.size.width * v / mx), height: 4)
                                .shadow(color: cat.color.opacity(0.5), radius: 3)
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    @ViewBuilder private func appIcon(_ name: String) -> some View {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }), let i = app.icon {
            Image(nsImage: i).resizable()
        } else if name.contains(".") {
            Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(DS.text2)
                .frame(width: 22, height: 22).background(Circle().fill(DS.fillHi))
        } else {
            Image(systemName: "app.dashed").font(.system(size: 14)).foregroundStyle(DS.text3)
        }
    }
}

private struct Tile: View {
    var title: String, value: String, symbol: String, accent: Accent
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: symbol, accent: accent, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(DS.font(20, .bold, rounded: true)).foregroundStyle(DS.text).monospacedDigit()
                Text(title).font(DS.font(11)).foregroundStyle(DS.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.fill)
                RadialGradient(colors: [accent.a.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.line))
        )
    }
}
