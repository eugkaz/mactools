import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    struct PKey { let key: Int; let mods: UInt32; let label: String }
    static let paletteKeys = [
        PKey(key: 49, mods: UInt32(cmdKey | shiftKey), label: "⇧⌘Space"),
        PKey(key: 49, mods: UInt32(optionKey), label: "⌥Space"),
        PKey(key: 41, mods: UInt32(cmdKey), label: "⌘;"),
        PKey(key: 31, mods: UInt32(controlKey | optionKey), label: "⌃⌥O"),
    ]
    static var paletteIndex: Int { min(max(0, UserDefaults.standard.integer(forKey: "paletteKey")), paletteKeys.count - 1) }

    private var item: NSStatusItem!
    private var icon: OrbitIcon!
    private var paletteHK: UInt32?
    private var secTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        if Snapshot.dir != nil { snapshots(); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        icon = OrbitIcon(button: item.button!)
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu(); menu.delegate = self; item.menu = menu

        Index.shared.refresh()
        registerPalette()
        for a in WinAction.allCases {
            if let (k, m) = a.hotkey { Hotkeys.shared.register(k, m) { [weak self] in WindowManager.shared.perform(a); self?.icon.pulse() } }
        }
        Hotkeys.shared.register(35, Hotkeys.ctrlOpt) { [weak self] in self?.toggleFocus() }
        SnapController.shared.start()

        FocusTracker.shared.onTick = { [weak self] in self?.focusChanged() }
        focusChanged()

        if !AX.trusted {
            AX.prompt()
            Toast.show("Orbit: дай доступ в «Универсальном доступе», чтобы двигать окна")
        } else {
            Toast.show("🪐 Orbit: \(Self.paletteKeys[Self.paletteIndex].label) — палитра, ⌃⌥←/→ — окна, ⌃⌥P — фокус")
        }
    }

    func registerPalette() {
        if let id = paletteHK { Hotkeys.shared.unregister(id) }
        let k = Self.paletteKeys[Self.paletteIndex]
        paletteHK = Hotkeys.shared.register(k.key, k.mods) { Palette.shared.toggle() }
    }

    private func toggleFocus() {
        let f = FocusTracker.shared
        if f.phase == .idle { f.startFocus() } else { f.stop(); Toast.show("Фокус остановлен") }
        icon.pulse()
    }

    /// Обратный отсчёт в строке меню (таймер только во время фокуса)
    private func focusChanged() {
        let f = FocusTracker.shared
        if f.phase == .idle {
            secTimer?.invalidate(); secTimer = nil
            icon.progress = nil; item.button?.title = ""
            return
        }
        if secTimer == nil {
            secTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCountdown() }
            }
        }
        updateCountdown()
    }
    private func updateCountdown() {
        let f = FocusTracker.shared
        guard f.phase != .idle else { focusChanged(); return }
        icon.resting = f.phase == .rest
        icon.progress = f.progress
        item.button?.attributedTitle = NSAttributedString(string: " " + f.remaining,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }

    // MARK: меню
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let f = FocusTracker.shared
        let pk = Self.paletteKeys[Self.paletteIndex]
        add(menu, "Палитра команд", "sparkle.magnifyingglass", key: pk.label) { Palette.shared.show() }
        menu.addItem(.separator())

        if f.phase == .idle {
            add(menu, "Начать фокус \(f.focusMin) мин", "target", key: "⌃⌥P") { f.startFocus() }
            let more = NSMenuItem(title: "Фокус на…", action: nil, keyEquivalent: ""); more.image = sym("timer")
            let sub = NSMenu()
            for m in [15, 45, 60, 90] { add(sub, "\(m) мин", nil) { f.startFocus(minutes: m) } }
            more.submenu = sub; menu.addItem(more)
        } else {
            add(menu, (f.phase == .focus ? "Остановить фокус" : "Закончить перерыв") + " · \(f.remaining)", "stop.circle", key: "⌃⌥P") { f.stop() }
        }
        let info = NSMenuItem(title: "Сегодня: " + Catalog.summaryLine(), action: nil, keyEquivalent: ""); info.isEnabled = false
        menu.addItem(info)
        add(menu, "Отчёт за день…", "chart.bar.xaxis") { ReportWindow.show() }
        menu.addItem(.separator())

        // окна
        let wi = NSMenuItem(title: "Окна", action: nil, keyEquivalent: ""); wi.image = sym("macwindow.on.rectangle")
        let ws = NSMenu()
        let groups: [[WinAction]] = [[.leftHalf, .rightHalf, .topHalf, .bottomHalf], [.maximize, .almostMaximize, .center, .restore],
                                     [.topLeft, .topRight, .bottomLeft, .bottomRight], [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
                                     [.larger, .smaller, .nextDisplay, .prevDisplay]]
        for (gi, g) in groups.enumerated() {
            if gi > 0 { ws.addItem(.separator()) }
            for a in g { add(ws, a.title, a.symbol, key: a.hotkeyLabel) { WindowManager.shared.perform(a) } }
        }
        wi.submenu = ws; menu.addItem(wi)

        let li = NSMenuItem(title: "Наборы окон", action: nil, keyEquivalent: ""); li.image = sym("square.grid.2x2")
        let ls = NSMenu()
        for l in Layouts.all {
            add(ls, l.name, nil) { Layouts.apply(l) }
        }
        if !Layouts.all.isEmpty { ls.addItem(.separator()) }
        add(ls, "Сохранить текущие окна…", "square.and.arrow.down") { Palette.shared.show(); Palette.shared.model.query = "save " }
        if !Layouts.all.isEmpty {
            let del = NSMenuItem(title: "Удалить", action: nil, keyEquivalent: ""); let ds = NSMenu()
            for l in Layouts.all { add(ds, l.name, nil) { Layouts.delete(l) } }
            del.submenu = ds; ls.addItem(del)
        }
        li.submenu = ls; menu.addItem(li)

        let snap = add(menu, "Прилипание к краям экрана", nil) { SnapController.shared.enabled.toggle() }
        snap.state = SnapController.shared.enabled ? .on : .off
        menu.addItem(.separator())

        if !AX.trusted {
            add(menu, "⚠️ Дать доступ к окнам…", nil) {
                AX.prompt()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        add(menu, "Настройки…", "gearshape", key: "⌘,") { SettingsWindow.show() }
        add(menu, "Выйти", nil, key: "⌘Q") { NSApp.terminate(nil) }
    }

    @discardableResult
    private func add(_ m: NSMenu, _ title: String, _ symbol: String?, key: String = "", _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let it = ClosureItem(title: title, action: action)
        if let symbol { it.image = sym(symbol) }
        if !key.isEmpty {
            // подпись сочетания справа (без реального keyEquivalent, чтобы не конфликтовать)
            let a = NSMutableAttributedString(string: title)
            a.append(NSAttributedString(string: "    " + key, attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 12)]))
            it.attributedTitle = a
        }
        m.addItem(it); return it
    }
    private func sym(_ n: String) -> NSImage? { NSImage(systemSymbolName: n, accessibilityDescription: nil) }

    private func snapshots() {
        Index.shared.refresh()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let m = Palette.shared.model
        m.query = ""; Snapshot.save("palette_empty", width: 700, height: 468, PaletteView(m: m))
        m.query = "saf"; Snapshot.save("palette_saf", width: 700, height: 468, PaletteView(m: m))
        m.query = "2*(3+4)^2"; Snapshot.save("palette_calc", width: 700, height: 468, PaletteView(m: m))
        Snapshot.save("report", width: 760, height: 760, ReportView(t: FocusTracker.shared))
        Snapshot.save("toast", ToastView(text: "🌿 Orbit: ветка main"))
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ n: Notification) { FocusTracker.shared.save() }
}

final class ClosureItem: NSMenuItem {
    private let block: @MainActor () -> Void
    init(title: String, action: @escaping @MainActor () -> Void) {
        block = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { MainActor.assumeIsolated { block() } }
}
