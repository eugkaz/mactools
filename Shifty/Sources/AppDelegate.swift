import AVFoundation
import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    let model = ShiftyModel()
    var panel: DropPanel!
    let watcher = DragWatcher()
    var editors: [NSWindow] = []
    var enabledItem: NSMenuItem!
    var icon: StatusIcon!
    var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        if let v = ProcessInfo.processInfo.environment["SHIFTY_VTEST"] { headlessVideoTest(v); return }
        if let dir = Snapshot.dir { MainActor.assumeIsolated { snapshots(dir) }; return }
        panel = DropPanel(model: model)
        model.onEdit = { [weak self] url in self?.openEditor(url) }
        model.onClose = { [weak self] in self?.panel.hide() }
        watcher.enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        watcher.onShiftDrag = { [weak self] urls in self?.show(urls, pinned: false); self?.icon.state = .hover }
        model.onPhase = { [weak self] ph in
            switch ph {
            case .working: self?.icon.state = .scanning
            case .done: self?.icon.state = .idle; self?.icon.pulse()
            default: self?.icon.state = .idle
            }
        }
        watcher.onMouseUp = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let self else { return }
                if self.icon.state == .hover { self.icon.state = .idle }
                guard !self.model.pinned, !self.model.isBusy else { return }
                self.panel.hide()
            }
        }
        watcher.start()
        // Клик мимо меню (когда оно открыто из строки меню или показывает результат) — закрыть
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if case .working = self.model.phase { return }
            if !self.panel.frame.contains(NSEvent.mouseLocation) { self.panel.hide() }
        }
        setupMenu()
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            showHelp()
        }
    }

    func show(_ urls: [URL], pinned: Bool) {
        model.load(urls, pinned: pinned)
        let p = pinned ? NSPoint(x: NSScreen.main!.frame.midX, y: NSScreen.main!.frame.midY) : NSEvent.mouseLocation
        panel.show(near: p)
    }

    // MARK: Menu

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        icon = StatusIcon(button: statusItem.button!, kind: .shifty)
        let menu = NSMenu()
        menu.addItem(withTitle: "Конвертировать файл…", action: #selector(pickFile), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Открыть в редакторе…", action: #selector(pickEdit), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Новый дизайн (как Canva)", action: #selector(newDesign), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Видеоредактор (как CapCut)", action: #selector(newVideo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        enabledItem = menu.addItem(withTitle: "Shift + перетаскивание", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = watcher.enabled ? .on : .off
        loginItem = menu.addItem(withTitle: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Как пользоваться", action: #selector(showHelp), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func pick() -> [URL]? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        return p.runModal() == .OK ? p.urls : nil
    }

    @objc func pickFile() { if let u = pick() { show(u, pinned: true) } }
    @objc func pickEdit() { if let u = pick()?.first { openEditor(u) } }

    @objc func toggleEnabled() {
        watcher.enabled.toggle()
        UserDefaults.standard.set(watcher.enabled, forKey: "enabled")
        enabledItem.state = watcher.enabled ? .on : .off
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Shifty"
        a.informativeText = """
        1. Начните перетаскивать файл (из Finder, с рабочего стола, из браузера).
        2. Зажмите ⇧ Shift — вокруг курсора раскроется круговое меню.
        3. Потяните к нужному пузырю и отпустите — готовый файл появится рядом с исходным.
           Отпустите в центре — отмена.

        «Редактор» — фото: фильтры, яркость, кадрирование, поворот, размер. Видео/аудио: обрезка, без звука, скорость, разрешение.
        Работает и с несколькими файлами сразу. Иконка ✨ в строке меню — настройки.
        """
        a.runModal()
    }

    // MARK: Editors

    func openEditor(_ url: URL) {
        let kind = Files.kind(url)
        let view: AnyView
        let size: NSSize
        switch kind {
        case .image: view = AnyView(PhotoStudioView(url: url)); size = NSSize(width: 1440, height: 880)
        case .video: view = AnyView(VideoStudioView(url: url)); size = NSSize(width: 1440, height: 900)
        case .audio: view = AnyView(MediaEditorView(url: url, isAudio: true)); size = NSSize(width: 980, height: 640)
        case .text where Files.isPlainText(url): view = AnyView(TextFileEditorView(url: url)); size = NSSize(width: 820, height: 640)
        default: NSWorkspace.shared.open(url); return
        }
        present(view, size: size, title: url.lastPathComponent)
    }

    @objc func newDesign() { present(AnyView(PhotoStudioView(url: nil)), size: NSSize(width: 1440, height: 880), title: "Новый дизайн") }
    @objc func newVideo() { present(AnyView(VideoStudioView(url: nil)), size: NSSize(width: 1440, height: 900), title: "Видеоредактор") }

    @MainActor private func snapshots(_ dir: String) {
        let img = URL(fileURLWithPath: dir).appendingPathComponent("sample.png")
        model.load([img], pinned: true)
        Snapshot.save("shifty_radial", RadialView(model: model).padding(30).background(Color(white: 0.7)))
        model.hovered = model.actions.first
        Snapshot.save("shifty_radial_hover", RadialView(model: model).padding(30).background(Color(white: 0.7)))
        Snapshot.save("shifty_photo", width: 1440, height: 880, PhotoStudioView(url: img))
        Snapshot.save("shifty_video", width: 1440, height: 900, VideoStudioView(url: nil))
        NSApp.terminate(nil)
    }

    func present(_ view: AnyView, size: NSSize, title: String) {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title
        w.minSize = NSSize(width: 1100, height: 700)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(DS.bg0)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.delegate = self
        editors.append(w)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        editors.removeAll { $0 === w }
        if editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

extension AppDelegate {
    /// SHIFTY_VTEST=<video> — проверка экспорта видеоредактора без интерфейса.
    @MainActor func headlessVideoTest(_ path: String) {
        Task { @MainActor in
            let p = VideoProject()
            await p.addClip(URL(fileURLWithPath: path))
            print("clips:", p.clips.count, p.status ?? "")
            for f in ["mp4", "mov", "gif"] {
                await p.export(format: f, height: f == "gif" ? 480 : 1080)
                print(f, "→", p.status ?? "nil")
            }
            let u = URL(fileURLWithPath: path)
            for (n, pr, t, e) in [("mp4", AVAssetExportPresetHighestQuality, AVFileType.mp4, "mp4"), ("hevc", AVAssetExportPresetHEVCHighestQuality, .mp4, "mp4"),
                                  ("720p", AVAssetExportPreset1280x720, .mp4, "mp4"), ("m4a", AVAssetExportPresetAppleM4A, .m4a, "m4a")] {
                do { let o = try await Media.av(u, preset: pr, type: t, ext: e, suffix: " q-\(n)"); print(n, "→", o.lastPathComponent) }
                catch { print(n, "✗", error.localizedDescription) }
            }
            exit(0)
        }
    }
}
