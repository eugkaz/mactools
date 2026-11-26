import Foundation
import Observation
import UserNotifications
import ServiceManagement

enum Hold: Equatable { case none, manual, timer, agents }

@MainActor @Observable
final class AwakeModel {
    // настройки
    var autoAgents = UD.bool("autoAgents", true) { didSet { UD.set("autoAgents", autoAgents); tick() } }
    var lidMode = UD.bool("lidMode", false) { didSet { UD.set("lidMode", lidMode); tick() } }
    var keepDisplay = UD.bool("keepDisplay", false) { didSet { UD.set("keepDisplay", keepDisplay); tick() } }
    var notifyDone = UD.bool("notifyDone", true) { didSet { UD.set("notifyDone", notifyDone) } }
    var graceMin = UD.int("graceMin", 5) { didSet { UD.set("graceMin", graceMin) } }
    var batteryFloor = UD.int("batteryFloor", 20) { didSet { UD.set("batteryFloor", batteryFloor) } }
    var extraNames = UserDefaults.standard.string(forKey: "extraNames") ?? "" { didSet { UD.set("extraNames", extraNames) } }

    // ручной режим
    var manualForever = false
    var manualUntil: Date?

    // состояние
    private(set) var agents: [AgentProc] = []
    private(set) var hold: Hold = .none
    private(set) var battery = Battery.read()
    private(set) var batteryBlocked = false
    private(set) var lidApplied = UD.bool("lidSetByUs", false) { didSet { UD.set("lidSetByUs", lidApplied) } }
    private(set) var lidBusy = false
    private(set) var lidClosed = false
    private(set) var passwordless = Lid.passwordless
    private(set) var awakeSince: Date?
    var lastActive: Date?
    var onChange: (() -> Void)?
    var visible = false

    private let assertion = SleepAssertion()
    private var timer: Timer?
    private var activeSince: [Int32: Date] = [:]   // когда агент начал работать
    private var idleSince: [Int32: Date] = [:]
    private var cwdCache: [Int32: String] = [:]
    private var lidRetryAfter = Date.distantPast
    private var fast = false

    static let activeCPU = 3.0

    var isAwake: Bool { hold != .none }
    var anyActive: Bool { agents.contains { $0.cpu >= Self.activeCPU } }

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // если в прошлый раз приложение упало с отключённым сном — вернуть как было
        if lidApplied, !lidMode { setLid(false) }
        schedule()
        tick()
    }

    func setFast(_ on: Bool) { fast = on; schedule() }
    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 2 : 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: ручное управление
    func keep(minutes: Int?) {      // nil = бесконечно
        if let m = minutes { manualForever = false; manualUntil = Date().addingTimeInterval(Double(m) * 60) }
        else { manualForever = true; manualUntil = nil }
        batteryBlocked = false
        tick()
    }
    func stopManual() { manualForever = false; manualUntil = nil; tick() }
    var manualOn: Bool { manualForever || (manualUntil.map { $0 > Date() } ?? false) }

    // MARK: главный цикл
    func tick() {
        let now = Date()
        let b = Battery.read(); if b != battery { battery = b }
        let lc = Lid.isClosed; if lc != lidClosed { lidClosed = lc }
        let extra = extraNames.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        var list = AgentScanner.scan(extra: extra)
        for i in list.indices {
            let pid = list[i].id; if cwdCache[pid] == nil { cwdCache[pid] = AgentScanner.cwd(pid) }; list[i].dir = cwdCache[pid] ?? ""
        }
        trackFinishes(list, now)
        let sorted = list.sorted { $0.cpu > $1.cpu }
        if sorted != agents { agents = sorted }
        if anyActive { lastActive = now }

        // батарея: защита от разрядки в сумке
        if battery.present, !battery.onAC, battery.percent <= batteryFloor {
            if !batteryBlocked, hold != .none {
                notify("Awake: заряд \(battery.percent)%", "Отпускаю Mac в сон, чтобы не разрядился в ноль.")
            }
            batteryBlocked = true
        } else if battery.onAC { batteryBlocked = false }

        if let u = manualUntil, u <= now { manualUntil = nil }
        let agentHold = autoAgents && !agents.isEmpty && (lastActive.map { now.timeIntervalSince($0) < Double(graceMin) * 60 } ?? false)
        let newHold: Hold = batteryBlocked ? .none
            : manualForever ? .manual : manualUntil != nil ? .timer : agentHold ? .agents : .none

        if hold == .agents, newHold == .none, notifyDone {
            notify("ИИ-агенты затихли", "Активности не было \(graceMin) мин — Mac снова может спать.")
        }
        if newHold != .none, awakeSince == nil { awakeSince = now }
        if newHold == .none { awakeSince = nil }
        if hold != newHold { hold = newHold }
        assertion.apply(system: isAwake, display: keepDisplay)

        // крышка
        let wantLid = isAwake && lidMode
        if wantLid != lidApplied, !lidBusy, now >= lidRetryAfter { setLid(wantLid) }
        onChange?()
    }

    private func setLid(_ on: Bool) {
        // без пароля — молча; иначе спросим пароль, но не когда крышка закрыта (некому ответить)
        let interactive = !Lid.isClosed
        lidBusy = true
        DispatchQueue.global().async {
            let ok = Lid.set(on, interactive: interactive)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.lidBusy = false
                    if ok { self.lidApplied = on }
                    else if on && interactive { self.lidMode = false }          // отменили ввод пароля
                    else { self.lidRetryAfter = Date().addingTimeInterval(on ? 600 : 30) }
                    self.onChange?()
                }
            }
        }
    }

    func setupPasswordless() {
        lidBusy = true
        DispatchQueue.global().async {
            _ = Lid.installPasswordless()
            let ok = Lid.passwordless
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self.lidBusy = false; self.passwordless = ok; self.onChange?()
            } }
        }
    }
    func removePasswordless() {
        DispatchQueue.global().async {
            _ = Lid.removePasswordless()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.passwordless = Lid.passwordless; self.onChange?() } }
        }
    }

    /// Вызывается при выходе: вернуть обычный сон
    func shutdown() {
        assertion.apply(system: false, display: false)
        if lidApplied, Lid.set(false, interactive: true) { lidApplied = false }
    }

    // MARK: уведомления «агент закончил»
    private func trackFinishes(_ list: [AgentProc], _ now: Date) {
        let alive = Set(list.map(\.id))
        for a in list {
            if a.cpu >= Self.activeCPU {
                if activeSince[a.id] == nil { activeSince[a.id] = now }
                idleSince[a.id] = nil
            } else if let start = activeSince[a.id] {
                let idle = idleSince[a.id] ?? now
                idleSince[a.id] = idle
                // работал хотя бы 20 с и затих на 20 с — значит ответил и ждёт тебя
                if idle.timeIntervalSince(start) >= 20, now.timeIntervalSince(idle) >= 20 {
                    activeSince[a.id] = nil; idleSince[a.id] = nil
                    if notifyDone {
                        let mins = Int(idle.timeIntervalSince(start) / 60)
                        notify("\(a.name) закончил", (a.dir.isEmpty ? "" : a.dir + " · ") + (mins > 0 ? "работал \(mins) мин" : "ждёт тебя"))
                    }
                }
            }
        }
        for pid in activeSince.keys where !alive.contains(pid) { activeSince[pid] = nil; idleSince[pid] = nil }
        for pid in cwdCache.keys where !alive.contains(pid) { cwdCache[pid] = nil }
    }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: автозапуск
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); onChange?() }
    }
}

enum UD {
    static func bool(_ k: String, _ d: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? d }
    static func int(_ k: String, _ d: Int) -> Int { UserDefaults.standard.object(forKey: k) as? Int ?? d }
    static func set(_ k: String, _ v: Any) { UserDefaults.standard.set(v, forKey: k) }
}
