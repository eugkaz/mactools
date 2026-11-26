import AppKit
import ScreenCaptureKit
import AVFoundation
import SwiftUI

@MainActor @Observable
final class Recorder: NSObject {
    enum State: Equatable { case idle, countdown(Int), recording, finishing }
    private(set) var state: State = .idle
    private(set) var started: Date?
    var error: String?

    // настройки
    var mic = UserDefaults.standard.bool(forKey: "mic") { didSet { UserDefaults.standard.set(mic, forKey: "mic") } }
    var systemAudio = UserDefaults.standard.bool(forKey: "sysAudio") { didSet { UserDefaults.standard.set(systemAudio, forKey: "sysAudio") } }
    var customCursor = UserDefaults.standard.object(forKey: "customCursor") as? Bool ?? true { didSet { UserDefaults.standard.set(customCursor, forKey: "customCursor") } }
    var countdown = UserDefaults.standard.object(forKey: "countdown") as? Bool ?? true { didSet { UserDefaults.standard.set(countdown, forKey: "countdown") } }
    /// Не записывать строку меню (чёлку, островки, значок записи, часы)
    var hideMenuBar = UserDefaults.standard.object(forKey: "hideMenuBar") as? Bool ?? true { didSet { UserDefaults.standard.set(hideMenuBar, forKey: "hideMenuBar") } }

    /// Приложения, чьи окна никогда не попадают в запись
    static let hiddenApps: Set<String> = ["fr.louisraille.NotchBuddy", "com.mystery.notchdeck", "com.mystery.orbit", "com.mystery.awake"]

    var onFinished: ((Recording) -> Void)?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var rec: Recording?
    private var meta = RecMeta()
    private var t0: Double?
    private var pending: [[Double]] = []      // события до первого кадра (абсолютное время)
    private var pendingClicks: [[Double]] = []
    private var sampleTimer: Timer?
    private var clickMonitor: Any?
    private var screenFrame = CGRect.zero
    private var finishCont: CheckedContinuation<Void, Never>?
    private var cancelled = false
    private let overlay = CountdownOverlay()
    let pill = RecordingPill()

    var isBusy: Bool { state != .idle }

    // MARK: старт
    func start() {
        guard state == .idle else { return }
        error = nil
        Task { await begin() }
    }

    private func begin() async {
        // экран под курсором
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let did = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            self.error = "Нужно разрешение «Запись экрана»: Системные настройки → Конфиденциальность → Запись экрана и системного звука → Reel"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            return
        }
        guard let display = content.displays.first(where: { $0.displayID == did }) ?? content.displays.first else { error = "Не нашёл экран"; return }

        if countdown {
            for n in [3, 2, 1] {
                state = .countdown(n)
                overlay.show(n, on: screen)
                try? await Task.sleep(for: .milliseconds(800))
                if state == .idle { overlay.hide(); return }      // отменили
            }
            overlay.hide()
        }

        let hidden = Self.hiddenApps.union([Bundle.main.bundleIdentifier ?? ""])
        let me = content.applications.filter { hidden.contains($0.bundleIdentifier) }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let cfg = SCStreamConfiguration()
        // область записи: весь экран или без строки меню (в точках, начало — левый верхний угол)
        let full = filter.contentRect.size
        let mb: CGFloat = hideMenuBar ? max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness) : 0
        let area = CGRect(x: 0, y: mb, width: full.width, height: full.height - mb)
        if mb > 0 { cfg.sourceRect = area }
        cfg.width = Int(area.width * scale) / 2 * 2
        cfg.height = Int(area.height * scale) / 2 * 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.showsCursor = !customCursor
        cfg.capturesAudio = systemAudio
        cfg.excludesCurrentProcessAudio = true
        cfg.captureMicrophone = mic
        cfg.queueDepth = 6

        let r = Recording.new()
        rec = r
        meta = RecMeta(pixelW: cfg.width, pixelH: cfg.height, customCursor: customCursor)
        // та же область в координатах AppKit — для курсора и кликов
        screenFrame = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - mb)
        t0 = nil; pending = []; pendingClicks = []; cancelled = false

        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = r.video
        rc.outputFileType = .mov
        rc.videoCodecType = .hevc
        let out = SCRecordingOutput(configuration: rc, delegate: self)
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        do {
            try s.addRecordingOutput(out)
            startTracking()
            try await s.startCapture()
        } catch {
            stopTracking()
            self.error = "Не удалось начать запись: \(error.localizedDescription)"
            state = .idle
            return
        }
        stream = s; output = out
        state = .recording
        started = Date()
        pill.show(recorder: self, on: screen)
    }

    // MARK: курсор и клики
    private func startTracking() {
        sampleTimer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.click(p) }
        }
    }
    private func stopTracking() {
        sampleTimer?.invalidate(); sampleTimer = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m) }; clickMonitor = nil
    }
    private func norm(_ p: CGPoint) -> (Double, Double) {
        (Double((p.x - screenFrame.minX) / screenFrame.width), Double((screenFrame.maxY - p.y) / screenFrame.height))
    }
    private func sample() {
        let (x, y) = norm(NSEvent.mouseLocation)
        let now = CACurrentMediaTime()
        if let t0 { meta.samples.append([now - t0, x, y]) } else { pending.append([now, x, y]) }
    }
    private func click(_ p: CGPoint) {
        guard screenFrame.contains(p) else { return }
        let (x, y) = norm(p)
        let now = CACurrentMediaTime()
        if let t0 { meta.clicks.append([now - t0, x, y]) } else { pendingClicks.append([now, x, y]) }
    }
    fileprivate func didStartWriting() {
        let now = CACurrentMediaTime()
        t0 = now
        meta.samples = pending.map { [max(0, $0[0] - now), $0[1], $0[2]] }
        meta.clicks = pendingClicks.map { [max(0, $0[0] - now), $0[1], $0[2]] }
    }

    // MARK: стоп
    func stop() {
        guard state == .recording, let s = stream else {
            if case .countdown = state { state = .idle; overlay.hide() }
            return
        }
        state = .finishing
        pill.hide()
        stopTracking()
        Task {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                finishCont = c
                Task { try? await s.stopCapture() }
                // страховка, если делегат не ответит
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { MainActor.assumeIsolated { self.resumeFinish() } }
            }
            await finalize()
        }
    }
    func cancel() {
        cancelled = true
        stop()
    }
    fileprivate func resumeFinish() { finishCont?.resume(); finishCont = nil }

    private func finalize() async {
        stream = nil; output = nil
        guard let r = rec else { state = .idle; return }
        if cancelled {
            try? FileManager.default.removeItem(at: r.dir)
            state = .idle; return
        }
        let dur = (try? await AVURLAsset(url: r.video).load(.duration).seconds) ?? 0
        meta.duration = dur
        r.saveMeta(meta)
        await r.makeThumbnail()
        state = .idle
        started = nil
        if dur > 0.3 { onFinished?(r) } else { error = "Запись получилась пустой"; try? FileManager.default.removeItem(at: r.dir) }
    }
}

extension Recorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.didStartWriting() } }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.resumeFinish() } }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.error = error.localizedDescription; self.resumeFinish() } }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { MainActor.assumeIsolated { if self.state == .recording { self.stop() } } }
    }
}

// MARK: - Отсчёт 3-2-1

@MainActor
final class CountdownOverlay {
    private var panel: NSPanel?
    func show(_ n: Int, on screen: NSScreen) {
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .screenSaver; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        let p = panel!
        p.contentView = NSHostingView(rootView: CountdownView(n: n))
        let s: CGFloat = 220
        p.setFrame(CGRect(x: screen.frame.midX - s / 2, y: screen.frame.midY - s / 2, width: s, height: s), display: true)
        p.orderFrontRegardless()
        NSSound(named: "Tink")?.play()
    }
    func hide() { panel?.orderOut(nil) }
}

struct CountdownView: View {
    let n: Int
    @State private var pop = false
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.55)).overlay(Circle().strokeBorder(Accent.reel.gradient, lineWidth: 3))
                .shadow(color: Accent.reel.b.opacity(0.6), radius: 20)
            Text("\(n)").font(.system(size: 96, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .scaleEffect(pop ? 1 : 1.6).opacity(pop ? 1 : 0)
        }
        .padding(20)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pop = true } }
    }
}

// MARK: - Плашка во время записи (её нет на видео)

@MainActor
final class RecordingPill {
    private var panel: NSPanel?
    func show(recorder: Recorder, on screen: NSScreen) {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PillView(r: recorder).environment(\.colorScheme, .dark))
        p.contentView = host
        let size = host.fittingSize
        p.setFrame(CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 28, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        panel = p
    }
    func hide() { panel?.orderOut(nil); panel = nil }
}

struct PillView: View {
    let r: Recorder
    @State private var blink = false
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: 0xFF3B5C)).frame(width: 10, height: 10)
                .shadow(color: Color(hex: 0xFF3B5C), radius: blink ? 6 : 2).opacity(blink ? 1 : 0.5)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let s = Int(Date().timeIntervalSince(r.started ?? Date()))
                Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(DS.text)
            }
            Rectangle().fill(DS.line).frame(width: 1, height: 18)
            Button { r.stop() } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 10, height: 10)
                    Text("Готово").font(.system(size: 12.5, weight: .semibold))
                }
            }
            .buttonStyle(PillButtonStyle(accent: .reel, height: 30))
            .help("Остановить и открыть редактор (⌃⌥R)")
            CircleIconButton(symbol: "xmark", size: 28) { r.cancel() }.help("Отменить запись")
        }
        .padding(.leading, 16).padding(.trailing, 7).frame(height: 44)
        .background(Capsule().fill(DS.bg0.opacity(0.95)).overlay(Capsule().strokeBorder(DS.lineHi)))
        .padding(8)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { blink = true } }
    }
}
