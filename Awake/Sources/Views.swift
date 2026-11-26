import SwiftUI

struct AwakeView: View {
    @Bindable var m: AwakeModel
    var quit: () -> Void
    var close: () -> Void
    @State private var showSettings = false

    private var accent: Accent { m.batteryBlocked ? .warn : m.isAwake ? .awakeOn : .awake }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            stats
            durations
            agentsCard
            lidCard
            if showSettings { settingsCard.transition(.opacity.combined(with: .move(edge: .top))) }
            footer
        }
        .padding(16)
        .frame(width: 348)
        .background(GlassBackground(accent: accent, glow: m.isAwake ? 1 : 0.6))
        .animation(DS.spring, value: showSettings)
        .animation(DS.spring, value: m.isAwake)
        .environment(\.accent, accent)
    }

    // MARK: шапка с «живой» сферой
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Orb(accent: accent, awake: m.isAwake, working: m.anyActive && m.isAwake, animate: m.visible)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.batteryBlocked ? "Бережёт батарею" : m.isAwake ? "Mac не уснёт" : "Mac может спать")
                    .font(DS.font(21, .bold, rounded: true)).foregroundStyle(DS.text)
                    .contentTransition(.opacity)
                Text(reason).font(DS.font(12)).foregroundStyle(DS.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack { CircleIconButton(symbol: "xmark", size: 24, action: close); Spacer() }
        }
    }

    private var reason: String {
        if m.batteryBlocked { return "Заряд \(m.battery.percent)% — подключи зарядку, и всё вернётся" }
        var s: String
        switch m.hold {
        case .none: s = m.agents.isEmpty ? "ИИ-агентов не видно — обычный сон" : "Агенты отдыхают — обычный сон"
        case .manual: s = "Включено вручную, без ограничения"
        case .timer:
            let left = max(0, Int((m.manualUntil ?? Date()).timeIntervalSinceNow / 60))
            s = "Ещё " + (left >= 60 ? "\(left / 60) ч \(left % 60) мин" : "\(left) мин")
        case .agents:
            let act = m.agents.filter { $0.cpu >= AwakeModel.activeCPU }.map(\.name)
            s = act.isEmpty ? "Жду агентов ещё до \(m.graceMin) мин" : "Работает " + act.joined(separator: ", ")
        }
        if m.isAwake && m.lidApplied { s += " · крышку можно закрыть" }
        return s
    }

    // MARK: мини-статистика
    private var stats: some View {
        HStack(spacing: 8) {
            stat("cpu", "\(m.agents.filter { $0.cpu >= AwakeModel.activeCPU }.count)/\(m.agents.count)", "агентов")
            stat("clock", m.awakeSince.map { Self.short(Date().timeIntervalSince($0)) } ?? "—", "не спит")
            stat(m.battery.onAC ? "bolt.fill" : "battery.75percent", "\(m.battery.percent)%", m.battery.onAC ? "от сети" : "батарея")
        }
    }
    private func stat(_ sym: String, _ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: sym).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent.a)
            Text(v).font(DS.font(15, .semibold, rounded: true)).foregroundStyle(DS.text).monospacedDigit()
            Text(t).font(DS.font(10)).foregroundStyle(DS.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.fill)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line)))
    }

    // MARK: ручной режим
    private var durations: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Не спать вручную")
            Segmented(items: [(0, "Выкл"), (30, "30м"), (60, "1ч"), (120, "2ч"), (240, "4ч"), (-1, "∞")],
                      selection: manualSel, accent: .awakeOn) { v in
                if v == 0 { m.stopManual() } else { m.keep(minutes: v < 0 ? nil : v) }
            }
        }
    }
    private var manualSel: Int {
        if m.manualForever { return -1 }
        guard let u = m.manualUntil else { return 0 }
        let left = u.timeIntervalSinceNow / 60
        return [30, 60, 120, 240].first { left <= Double($0) + 0.5 } ?? 240
    }

    // MARK: агенты
    private var agentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $m.autoAgents) {
                    HStack(spacing: 10) {
                        IconTile(symbol: "sparkles", accent: .awake, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Пока работает ИИ").font(DS.font(13, .semibold)).foregroundStyle(DS.text)
                            Text("Claude, Codex, Cursor, Ollama").font(DS.font(10.5)).foregroundStyle(DS.text3)
                        }
                    }
                }
                .toggleStyle(GlowToggleStyle(accent: .awakeOn))
                if !m.agents.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(m.agents.prefix(4)) { a in AgentRow(a: a) }
                    }
                    if m.agents.count > 4 {
                        Text("и ещё \(m.agents.count - 4)").font(DS.font(10.5)).foregroundStyle(DS.text3).padding(.leading, 4)
                    }
                }
            }
        }
    }

    // MARK: крышка
    private var lidCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $m.lidMode) {
                    HStack(spacing: 10) {
                        IconTile(symbol: "laptopcomputer", accent: .sky, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("С закрытой крышкой").font(DS.font(13, .semibold)).foregroundStyle(DS.text)
                            Text(m.lidMode ? "Закрывай — ИИ не остановится" : "Иначе Mac уснёт с крышкой")
                                .font(DS.font(10.5)).foregroundStyle(DS.text3)
                        }
                    }
                }
                .toggleStyle(GlowToggleStyle(accent: .sky))
                .disabled(m.lidBusy)
                if m.lidMode && !m.passwordless {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").font(.system(size: 10)).foregroundStyle(Accent.warn.a)
                        Text("Пароль спрашивается при каждом переключении").font(DS.font(10.5)).foregroundStyle(DS.text2)
                        Spacer()
                        Button("Убрать") { m.setupPasswordless() }.buttonStyle(PillButtonStyle(accent: .warn, height: 22)).disabled(m.lidBusy)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: настройки
    private var settingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $m.keepDisplay) { label("Не гасить экран", "sun.max") }
                Toggle(isOn: $m.notifyDone) { label("Уведомлять, когда агент закончил", "bell.badge") }
                Toggle(isOn: Binding(get: { m.launchAtLogin }, set: { m.launchAtLogin = $0 })) { label("Запускать при входе", "power") }
                Divider().overlay(DS.line)
                stepper("Ждать после активности", "\(m.graceMin) мин", $m.graceMin, 1...60, 1)
                stepper("Спать при заряде ниже", "\(m.batteryFloor)%", $m.batteryFloor, 5...80, 5)
                HStack(spacing: 8) {
                    label("Свои процессы", "plus.rectangle.on.rectangle")
                    TextField("", text: $m.extraNames, prompt: Text("myagent, ffmpeg").foregroundStyle(DS.text3))
                        .textFieldStyle(.plain).font(DS.font(12)).foregroundStyle(DS.text)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                }
            }
            .toggleStyle(GlowToggleStyle(accent: .awakeOn))
        }
    }
    private func label(_ t: String, _ s: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: s).font(.system(size: 11, weight: .medium)).foregroundStyle(DS.text2).frame(width: 16)
            Text(t).font(DS.font(12.5)).foregroundStyle(DS.text)
        }
    }
    private func stepper(_ t: String, _ v: String, _ b: Binding<Int>, _ r: ClosedRange<Int>, _ st: Int) -> some View {
        HStack(spacing: 8) {
            Text(t).font(DS.font(12.5)).foregroundStyle(DS.text)
            Spacer()
            HStack(spacing: 0) {
                Button { b.wrappedValue = max(r.lowerBound, b.wrappedValue - st) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                Text(v).font(DS.font(12, .semibold, rounded: true)).monospacedDigit().foregroundStyle(DS.text).frame(minWidth: 46)
                Button { b.wrappedValue = min(r.upperBound, b.wrappedValue + st) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
            }
            .buttonStyle(.plain).font(.system(size: 10, weight: .bold)).foregroundStyle(DS.text2)
            .background(Capsule().fill(Color.white.opacity(0.07)))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(m.isAwake ? "Правый клик по значку — выключить" : "Правый клик по значку — включить")
                .font(DS.font(10.5)).foregroundStyle(DS.text3)
            Spacer()
            CircleIconButton(symbol: "gearshape.fill", size: 26, active: showSettings, accent: accent) { showSettings.toggle() }
            Menu {
                if m.passwordless { Button("Вернуть запрос пароля для крышки") { m.removePasswordless() } }
                Button("Выйти и вернуть обычный сон", action: quit)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.text2)
                    .frame(width: 26, height: 26).background(Circle().fill(DS.fill)).overlay(Circle().strokeBorder(DS.line))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    static func short(_ t: TimeInterval) -> String {
        let m = Int(t / 60); return m >= 60 ? "\(m / 60)ч \(m % 60)м" : "\(m) мин"
    }
}

/// Светящаяся сфера-статус
struct Orb: View {
    var accent: Accent
    var awake: Bool
    var working: Bool
    var animate: Bool
    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(accent.b.opacity(awake ? 0.45 : 0.18)).blur(radius: 14)
                .scaleEffect(breathe ? 1.15 : 0.9)
            Circle().fill(RadialGradient(colors: [accent.a, accent.b, accent.b.opacity(0.6)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
            if working {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(AngularGradient(colors: [.white.opacity(0), .white], center: .center), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .padding(-4).rotationEffect(.degrees(spin ? 360 : 0))
            }
            Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)).padding(5).blur(radius: 1.5)
            Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.8)
            Image(systemName: awake ? (working ? "sparkles" : "eye.fill") : "moon.zzz.fill")
                .font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .onAppear { start() }
        .onChange(of: animate) { _, _ in start() }
    }
    private func start() {
        guard animate else { breathe = false; spin = false; return }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
    }
}

struct AgentRow: View {
    let a: AgentProc
    var active: Bool { a.cpu >= AwakeModel.activeCPU }
    var body: some View {
        HStack(spacing: 10) {
            LiveDot(color: Accent.awakeOn.a, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name).font(DS.font(12.5, .medium)).foregroundStyle(DS.text)
                if !a.dir.isEmpty, a.dir != "/" {
                    Text(a.dir == "~" ? "домашняя папка" : a.dir).font(DS.font(10.5)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(active ? "работает" : "ждёт").font(DS.font(10, .semibold, rounded: true))
                    .foregroundStyle(active ? Accent.awakeOn.a : DS.text3)
                GlowBar(value: a.cpu / 100, accent: active ? .awakeOn : .gray, height: 3).frame(width: 44)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.035)))
    }
}
