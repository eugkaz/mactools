import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement
import Observation

enum Tab: String, CaseIterable, Identifiable {
    case media = "Медиа", clipboard = "Буфер", shelf = "Полка", launcher = "Запуск", dev = "Dev", system = "Система"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .media: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full"
        case .launcher: return "square.grid.2x2"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .system: return "gauge.with.dots.needle.33percent"
        }
    }
}

enum DeckMode { case closed, own }

@Observable
final class DeckState {
    var mode: DeckMode = .closed
    var isOpen: Bool { mode != .closed }
    var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .media {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }

    // Геометрия в координатах окна (x слева, y сверху)
    var windowSize = CGSize(width: 800, height: 300)
    var coucouRight: CGFloat = 120          // правый край обычного свёрнутого Coucou
    var coucouSmallRight: CGFloat = 40      // правый край «маленького» Coucou (80pt)
    /// часть островка, которую закрывает обычный Coucou (в маленьком режиме она видна и продолжает его)
    var hiddenPart: CGFloat { solo ? 0 : max(0, coucouRight - coucouSmallRight) + DeckState.overlap }
    /// Coucou не запущен — NotchDeck сам по себе: островок и панель по центру экрана
    var solo = false
    /// курсор над свёрнутым островком — показываем кнопки управления
    var peek = false
    var showRemote = false                  // открыт экран «Пульт для iPhone»
    var showSettings = false                // открыт экран настроек внешнего вида
    /// Полноэкранное приложение — островок становится кругом в правом нижнем углу
    var corner = false
    var pressing = false                    // момент нажатия на круг (для анимации)
    var morph: CGFloat = 1                  // 0 — островок «схлопнут» (смена места), 1 — виден
    static let bubble: CGFloat = 52
    static let margin: CGFloat = 22
    var bubbleRect: CGRect {
        CGRect(x: windowSize.width - DeckState.margin - DeckState.bubble, y: windowSize.height - DeckState.margin - DeckState.bubble,
               width: DeckState.bubble, height: DeckState.bubble)
    }
    var cornerPanelRect: CGRect {
        CGRect(x: windowSize.width - DeckState.margin - 500, y: windowSize.height - DeckState.margin - DeckState.panelHeight,
               width: 500, height: DeckState.panelHeight)
    }
    /// Радиус углов: у круга — половина, у раскрытой панели — 22
    var cornerRadius: CGFloat { DeckState.bubble / 2 + (22 - DeckState.bubble / 2) * min(max(progress, 0), 1) }
    var centerX: CGFloat = 400              // центр экрана/чёлки в координатах окна
    var notchWidth: CGFloat = 80
    var coucouExpandedRight: CGFloat = 450  // где правый край раскрытого Coucou (640pt по центру)
    var ownProgress: CGFloat = 0            // анимация собственного открытия
    var islandHeight: CGFloat = 24
    static let overlap: CGFloat = 14
    static let panelHeight: CGFloat = 160   // как у раскрытого Coucou
    static let gap: CGFloat = 4

    var progress: CGFloat { ownProgress }

    var playingNow: Bool { media.isPlaying && !media.title.isEmpty }
    var hasTrack: Bool { !media.title.isEmpty }
    /// островок показывает громкость/яркость
    var showHUD: Bool { hud.visible && !isOpen }
    var hasNotch = false
    var islandWidth: CGFloat {
        if showHUD { return solo ? (hasNotch ? notchWidth + 190 : 230) : 168 + hiddenPart }
        let extra: CGFloat = peek && hasTrack ? 56 : 0
        if solo { return (playingNow || (peek && hasTrack) ? max(200, notchWidth + 120) : max(96, notchWidth + 16)) + extra }
        return (playingNow || (peek && hasTrack) ? 100 : 58) + hiddenPart + extra
    }
    var panelWidth: CGFloat { corner ? 500 : (solo ? 520 : min(500, windowSize.width - panelX - 4)) }
    var islandX: CGFloat { solo ? centerX - islandWidth / 2 : coucouSmallRight - DeckState.overlap }
    /// Панель всегда правее раскрытого Coucou — никогда не залезает под него
    /// Панель растёт прямо из своего островка, вплотную к свёрнутому Coucou
    var panelX: CGFloat { solo ? centerX - panelWidth / 2 : coucouRight + DeckState.gap }

    /// Текущий прямоугольник (интерполяция между островком и панелью)
    var shapeRect: CGRect {
        let t = progress
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        if corner {
            let a = bubbleRect, b = cornerPanelRect
            return CGRect(x: lerp(a.minX, b.minX), y: lerp(a.minY, b.minY), width: lerp(a.width, b.width), height: lerp(a.height, b.height))
        }
        let h = lerp(islandHeight, DeckState.panelHeight)
        return CGRect(x: lerp(islandX, panelX), y: 0,
                      width: max(islandWidth * 0.5, lerp(islandWidth, panelWidth)),
                      height: max(islandHeight, h))
    }

    let media = MediaController()
    let clipboard = ClipboardStore()
    let shelf = ShelfStore()
    let launcher = LauncherStore()
    let ports = PortsStore()
    let snippets = SnippetStore()
    let system = SystemMonitor()
    let hud = HUDController()
}

final class DeckPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let deck = DeckState()
    var panel: DeckPanel!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        if ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil { MainActor.assumeIsolated { snapshots() }; return }
        panel = DeckPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // на уровень ниже Coucou: его островок всегда поверх нашего
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DeckView(deck: deck).environment(\.colorScheme, .dark))
        panel.ignoresMouseEvents = true
        position()
        panel.orderFrontRegardless()
        deck.media.active = true
        RemoteServer.shared.media = deck.media
        deck.hud.start()
        if RemoteServer.shared.enabled { RemoteServer.shared.start() }

        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Полноэкранное приложение → круг в углу
        for n in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkFullscreen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self?.checkFullscreen() }   // после анимации смены стола
                }
            }
        }
        let fsTimer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkFullscreen() } }
        fsTimer.tolerance = 0.5
        RunLoop.main.add(fsTimer, forMode: .common)
        // Coucou запустили/закрыли — переезжаем к нему или в центр
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == AppDelegate.coucouID else { return }
                MainActor.assumeIsolated { withAnimation(openSpring) { self?.position() } }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.deck.isOpen else { return e }
            if e.keyCode == UInt16(kVK_Escape) { self.close(); return nil }
            // Медиа с клавиатуры: пробел, ←/→ ±15 с, ↑/↓ громкость
            if self.deck.tab == .media, !(self.panel.firstResponder is NSTextView),
               e.modifierFlags.intersection([.command, .control, .option]).isEmpty, self.deck.media.source != nil {
                let m = self.deck.media
                switch Int(e.keyCode) {
                case kVK_Space: m.command("playpause"); return nil
                case kVK_LeftArrow: m.skip(-15); return nil
                case kVK_RightArrow: m.skip(15); return nil
                case kVK_UpArrow: m.setVolume(min(100, m.volume + 10)); return nil
                case kVK_DownArrow: m.setVolume(max(0, m.volume - 10)); return nil
                default: break
                }
            }
            if !(self.panel.firstResponder is NSTextView), e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...Tab.allCases.count).contains(n) {
                self.deck.tab = Tab.allCases[n - 1]
                return nil
            }
            return e
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.updateHitTesting() }
        RunLoop.main.add(timer!, forMode: .common)
        registerHotKey()
        installClickMonitors()
        setupMenu()
    }

    // MARK: Geometry

    @MainActor private func snapshots() {
        deck.media.active = true
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        for t in Tab.allCases {
            deck.tab = t
            let v = ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous).fill(Color.black)
                DotField()
                VStack(spacing: 0) {
                    TopBar(deck: deck)
                    Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                    DeckView(deck: deck).content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .frame(width: 500, height: DeckState.panelHeight)
            .foregroundStyle(.white).tint(accent)
            .padding(20).background(Color(white: 0.75))
            Snapshot.save("deck_\(Tab.allCases.firstIndex(of: t)!)", width: 540, height: 200, v)
        }
        // открытая панель целиком (с «ушками») и плеер с винилом — на фейковом треке
        if ProcessInfo.processInfo.environment["SNAPSHOT_FAKE"] != nil {
            let m = deck.media
            m.source = "Spotify"; m.title = "Midnight City"; m.artist = "M83"; m.isPlaying = true
            m.duration = 243; m.position = 97
            let img = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { r in
                NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.55, alpha: 1), NSColor(red: 0.25, green: 0.2, blue: 0.7, alpha: 1)])?.draw(in: r, angle: -45)
                return true
            }
            m.artwork = img
        }
        deck.tab = .media
        deck.windowSize = CGSize(width: 800, height: 230); deck.centerX = 400; deck.solo = true
        deck.mode = .own; deck.ownProgress = 1
        Snapshot.save("panel_open", width: 800, height: 230, DeckView(deck: deck).background(Color(white: 0.75)))
        let pr = Prefs.shared
        pr.medium = "cassette"; pr.progress = "wave"; pr.pattern = "grid"; pr.palette = "amber"
        Snapshot.save("panel_cassette", width: 800, height: 230, DeckView(deck: deck).background(Color(white: 0.75)))
        pr.pattern = "scan"; pr.palette = "violet"
        deck.showSettings = true
        Snapshot.save("panel_settings", width: 800, height: 230, DeckView(deck: deck).background(Color(white: 0.75)))
        deck.showSettings = false
        pr.medium = "vinyl"; pr.progress = "ticks"; pr.pattern = "dots"; pr.palette = "cover"
        deck.mode = .closed; deck.ownProgress = 0
        // круг в углу: обычный, при наведении, раскрытый
        deck.tab = .media
        deck.windowSize = CGSize(width: 620, height: 280)
        deck.corner = true
        for (name, peek, open) in [("corner_idle", false, false), ("corner_hover", true, false), ("corner_open", false, true)] {
            deck.peek = peek
            deck.mode = open ? .own : .closed
            deck.ownProgress = open ? 1 : 0
            let v = DeckView(deck: deck).background(Color(white: 0.55))
            Snapshot.save(name, width: 620, height: 280, v)
        }
        // HUD громкости/яркости: круг и островок
        deck.mode = .closed; deck.ownProgress = 0; deck.peek = false
        for (name, kind, lvl) in [("hud_bubble_vol", HUDController.Kind.volume, 0.62), ("hud_bubble_bri", .brightness, 0.31)] {
            deck.hud.kind = kind; deck.hud.level = lvl; deck.hud.visible = true
            Snapshot.save(name, width: 620, height: 280, DeckView(deck: deck).background(Color(white: 0.55)))
        }
        deck.corner = false
        deck.windowSize = CGSize(width: 800, height: 120); deck.centerX = 400; deck.islandHeight = 24
        for (name, solo) in [("hud_island_solo", true), ("hud_island_coucou", false)] {
            deck.solo = solo; deck.coucouRight = 480; deck.coucouSmallRight = 440
            deck.hud.kind = .volume; deck.hud.level = 0.75
            Snapshot.save(name, width: 800, height: 120, DeckView(deck: deck).background(Color(white: 0.55)))
        }
        NSApp.terminate(nil)
    }

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Как IslandScreenGeometry у Coucou: без чёлки — 80 × min(24, высота меню)
    var notchGeometry: (mid: CGFloat, w: CGFloat, h: CGFloat) {
        let s = screen
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            let w = s.frame.width - l.width - r.width
            return (s.frame.minX + l.width + w / 2, w > 0 ? w : 184, s.safeAreaInsets.top)
        }
        let menuH = s.frame.maxY - s.visibleFrame.maxY
        return (s.frame.midX, 80, min(24, menuH > 0 ? menuH : 24))
    }

    var windowX: CGFloat { screen.frame.minX }
    static let coucouID = "fr.louisraille.NotchBuddy"

    @objc func position() {
        let f = screen.frame
        let g = notchGeometry
        deck.islandHeight = g.h
        deck.hasNotch = screen.safeAreaInsets.top > 0
        deck.solo = !isRunning(AppDelegate.coucouID)
        deck.centerX = g.mid - windowX
        deck.notchWidth = g.w
        deck.windowSize = f.size
        deck.coucouExpandedRight = g.mid + 320 - windowX
        deck.coucouRight = g.mid + (g.w + 160) / 2 - windowX   // край свёрнутого Coucou
        deck.coucouSmallRight = g.mid + g.w / 2 - windowX     // край маленького Coucou
        // окно прозрачное на весь экран: островок может переезжать в угол; пустое место не рисуется и пропускает клики
        panel.setFrame(f, display: true)
    }

    /// Полноэкранное приложение в macOS — это отдельный рабочий стол особого типа.
    /// Спрашиваем у системы (SkyLight) тип текущего стола: 0 — обычный, 4 — полноэкранный.
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SpaceFn = @convention(c) (Int32) -> UInt64
    private typealias TypeFn = @convention(c) (Int32, UInt64) -> Int32
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let conn: ConnFn? = dlsym(sky, "SLSMainConnectionID").map { unsafeBitCast($0, to: ConnFn.self) }
    private static let activeSpace: SpaceFn? = dlsym(sky, "SLSGetActiveSpace").map { unsafeBitCast($0, to: SpaceFn.self) }
    private static let spaceType: TypeFn? = dlsym(sky, "SLSSpaceGetType").map { unsafeBitCast($0, to: TypeFn.self) }

    func isFullscreenActive() -> Bool {
        guard let conn = Self.conn, let active = Self.activeSpace, let type = Self.spaceType else { return false }
        let cid = conn()
        return type(cid, active(cid)) == 4
    }

    func checkFullscreen() {
        let fs = isFullscreenActive()
        guard fs != deck.corner, !morphing else { return }
        morphing = true
        if deck.isOpen { close() }
        // Не едем через весь экран: схлопываемся на месте, мгновенно меняем место, «выпрыгиваем» на новом
        deck.peek = false
        withAnimation(.easeIn(duration: 0.14)) { deck.morph = 0 } completion: { [weak self] in
            guard let self else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { self.deck.corner = fs }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.64)) { self.deck.morph = 1 }
            self.morphing = false
            self.checkFullscreen()          // пока анимировали, могли уже вернуться на обычный стол
        }
    }

    /// local (окно, y сверху) → глобальные координаты
    func toScreen(_ r: CGRect) -> NSRect {
        NSRect(x: windowX + r.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
    }

    var currentRect: NSRect { toScreen(deck.shapeRect) }

    var clickableIsland: NSRect {
        if deck.corner { return toScreen(deck.bubbleRect) }
        // весь островок: там, где сверху лежит Coucou, клики и так достанутся ему
        return deck.solo ? toScreen(CGRect(x: deck.islandX, y: 0, width: deck.islandWidth, height: deck.islandHeight))
            : toScreen(CGRect(x: deck.islandX + DeckState.overlap, y: 0, width: deck.islandWidth - DeckState.overlap, height: deck.islandHeight))
    }

    // MARK: Hit testing & clicks

    var icon: StatusIcon?
    var dragBase = NSPasteboard(name: .drag).changeCount
    var dragHover = 0.0
    var peekTimer = 0.0
    var morphing = false
    /// правая часть выдвинутого островка — там кнопки, клик не открывает панель
    var islandControls: NSRect {
        toScreen(CGRect(x: deck.islandX + deck.islandWidth - 66, y: 0, width: 66, height: deck.islandHeight))
    }

    func updateHitTesting() {
        let m = NSEvent.mouseLocation
        icon?.state = deck.isOpen && !closing ? .open : (deck.media.isPlaying ? .playing : .idle)
        let accept = deck.isOpen ? currentRect.contains(m) : clickableIsland.contains(m)
        // наведение на свёрнутый островок: выдвигаем кнопки (с небольшим запасом, чтобы не дрожало)
        let over = !deck.isOpen && clickableIsland.insetBy(dx: -4, dy: -3).contains(m)
        if over != deck.peek {
            if over { peekTimer += 0.03; if peekTimer > (deck.corner ? 0.02 : 0.12) { withAnimation(DS.snappy) { deck.peek = true } } }
            else { peekTimer = 0; withAnimation(DS.snappy) { deck.peek = false } }
        } else if !over { peekTimer = 0 }
        if panel.ignoresMouseEvents == accept { panel.ignoresMouseEvents = !accept }
        // Тащат файл и задержали над островком — открываем «Полку»
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        let dragCount = NSPasteboard(name: .drag).changeCount
        if !pressed { dragBase = dragCount; dragHover = 0; return }
        if !deck.isOpen, dragCount != dragBase, clickableIsland.insetBy(dx: -6, dy: -6).contains(m) {
            dragHover += 0.03
            if dragHover > 0.25 { deck.tab = .shelf; openOwn() }
        } else { dragHover = 0 }
        // Подстраховка: если macOS всё же спрятала приложение — вернуть островок
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
    }

    func installClickMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self else { return e }
            let p = NSEvent.mouseLocation
            if !self.deck.corner && self.deck.peek && self.deck.hasTrack && self.islandControls.contains(p) { return e }
            if (!self.deck.isOpen || self.closing), self.clickableIsland.contains(p) {
                if self.deck.corner {
                    // круг коротко «вжимается», затем раскрывается панелью
                    withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) { self.deck.pressing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                        self.deck.pressing = false; self.deck.peek = false; self.openOwn()
                    }
                } else { self.deck.peek = false; self.openOwn() }
                return nil
            }
            return e
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let m = NSEvent.mouseLocation
            if self.deck.isOpen, !self.currentRect.contains(m) { self.close() }
        }
    }

    // MARK: Open / close (собственное — та же пружина, что у Coucou)

    var closing = false
    var previousApp: NSRunningApplication?

    func openOwn(hotkey: Bool = false) {
        if deck.isOpen && !closing { return }
        closing = false
        if !deck.isOpen { deck.ownProgress = 0 }
        deck.mode = .own
        deck.media.detailed = true
        deck.media.refresh()
        panel.ignoresMouseEvents = false
        if hotkey { previousApp = NSWorkspace.shared.frontmostApplication }
        deck.system.active = true
        withAnimation(openSpring) { deck.ownProgress = 1 }
        if hotkey { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
    }

    func close() {
        guard deck.isOpen, !closing else { return }
        closing = true
        withAnimation(closeEase) { deck.ownProgress = 0 } completion: { [weak self] in
            guard let self, self.closing else { return }     // успели открыть снова — не трогаем
            self.finishClose()
        }
        // Вернуть фокус приложению, где пользователь был. НЕ NSApp.hide — он прячет и сам островок.
        if NSApp.isActive {
            panel.resignKey()
            if let prev = previousApp, prev != NSRunningApplication.current { prev.activate() } else { NSApp.deactivate() }
        }
        previousApp = nil
    }

    func finishClose() {
        closing = false
        deck.showRemote = false
        deck.showSettings = false
        deck.media.detailed = false
        deck.mode = .closed
        deck.ownProgress = 0
        deck.system.active = false
        panel.ignoresMouseEvents = true
    }

    func toggle() { deck.isOpen && !closing ? close() : openOwn(hotkey: true) }

    // MARK: Hotkey ⌃⌥Space

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared?.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4E44_4B31), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: Menu

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        icon = StatusIcon(button: statusItem.button!, kind: .deck)
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть / закрыть  (⌃⌥ Пробел)", action: #selector(menuToggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Пульт для iPhone…", action: #selector(showRemote), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Папка данных", action: #selector(openData), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc func menuToggle() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.toggle() } }
    @objc func showRemote() {
        deck.tab = .media
        deck.showRemote = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.openOwn(hotkey: true) }
    }
    @objc func openData() { NSWorkspace.shared.open(Persist.dir) }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTitle: "Запускать при входе")?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
