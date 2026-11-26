import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: MenuBarPanel!
    let recorder = Recorder()
    private var tick: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        if Snapshot.dir != nil { snapshots(); return }
        if let d = ProcessInfo.processInfo.environment["REEL_EXPORT"] { headlessExport(d); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.imagePosition = .imageLeading
        let r = recorder
        panel = MenuBarPanel(width: 340) {
            HomeView(r: r, close: { [weak self] in self?.panel.close() })
        }
        recorder.onFinished = { rec in EditorWindow.open(rec) }
        Hotkeys.shared.register(15, Hotkeys.ctrlOpt) { [weak self] in self?.toggleRecording() }
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateIcon() } }
        updateIcon()
    }

    func toggleRecording() {
        panel.close()
        recorder.isBusy ? recorder.stop() : recorder.start()
    }

    @objc private func click() {
        if recorder.state == .recording { recorder.stop(); return }
        panel.toggle(from: item.button!)
    }

    private var lastState: Recorder.State?
    private func updateIcon() {
        let st = recorder.state
        if st == .recording, let s = recorder.started {
            let sec = Int(Date().timeIntervalSince(s))
            item.button?.image = Self.icon(recording: true)
            item.button?.attributedTitle = NSAttributedString(string: String(format: " %d:%02d", sec / 60, sec % 60),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
        } else if st != lastState {
            item.button?.image = Self.icon(recording: false)
            item.button?.title = ""
        }
        lastState = st
    }

    static func icon(recording: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { r in
            if recording {
                NSColor(calibratedRed: 1, green: 0.23, blue: 0.36, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: 2, width: 12, height: 12)).fill()
                NSColor.white.setFill()
                NSBezierPath(roundedRect: NSRect(x: 7.5, y: 5.5, width: 5, height: 5), xRadius: 1, yRadius: 1).fill()
            } else {
                NSColor.black.setStroke()
                let p = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 17, height: 11), xRadius: 3, yRadius: 3)
                p.lineWidth = 1.5; p.stroke()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 6.5, y: 4.5, width: 7, height: 7)).fill()
            }
            return true
        }
        img.isTemplate = !recording
        return img
    }

    private func snapshots() {
        Snapshot.save("reel_home", HomeView(r: recorder, close: {}))
        Snapshot.save("reel_pill", PillView(r: recorder))
        if let rec = Recording.all().first {
            let m = EditorModel(rec: rec)
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            Snapshot.save("reel_editor", width: 1320, height: 860, EditorView(m: m))
        }
        NSApp.terminate(nil)
    }
}

struct HomeView: View {
    @Bindable var r: Recorder
    var close: () -> Void
    @State private var recent: [Recording] = Recording.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reel").font(DS.font(20, .bold, rounded: true)).foregroundStyle(DS.text)
                    Text("Запись с автомонтажом").font(DS.font(11.5)).foregroundStyle(DS.text2)
                }
                Spacer()
                CircleIconButton(symbol: "xmark", size: 24, action: close)
            }
            recordButton
            Card {
                VStack(spacing: 10) {
                    Toggle(isOn: $r.mic) { row("mic.fill", "Микрофон") }
                    Toggle(isOn: $r.systemAudio) { row("speaker.wave.2.fill", "Звук системы") }
                    Toggle(isOn: $r.customCursor) { row("cursorarrow.motionlines", "Красивый плавный курсор") }
                    Toggle(isOn: $r.hideMenuBar) { row("menubar.rectangle", "Без строки меню и чёлки") }
                    Toggle(isOn: $r.countdown) { row("timer", "Отсчёт 3-2-1") }
                }
                .toggleStyle(GlowToggleStyle(accent: .reel))
            }
            if let e = r.error {
                Text(e).font(DS.font(11)).foregroundStyle(Accent.warn.a).fixedSize(horizontal: false, vertical: true)
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel(text: "Недавние")
                        Spacer()
                        Button("Все") { NSWorkspace.shared.open(Recording.root) }.buttonStyle(.plain)
                            .font(DS.font(11, .semibold)).foregroundStyle(Accent.reel.a)
                    }
                    ForEach(recent.prefix(3)) { rec in RecentRow(rec: rec) { close(); EditorWindow.open(rec) } }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(GlassBackground(accent: .reel))
        .onAppear { recent = Recording.all() }
    }

    private var recordButton: some View {
        Button { close(); r.start() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.25)).frame(width: 40, height: 40)
                    Circle().fill(.white).frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Начать запись").font(DS.font(16, .bold, rounded: true))
                    Text("Весь экран · стоп — ⌃⌥R или клик по значку").font(DS.font(10.5)).opacity(0.8)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 66)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Accent.reel.gradient)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.25))))
            .shadow(color: Accent.reel.b.opacity(0.55), radius: 14, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(r.isBusy)
    }

    private func row(_ s: String, _ t: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text2).frame(width: 16)
            Text(t).font(DS.font(12.5)).foregroundStyle(DS.text)
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed ? 0.97 : 1).animation(DS.snappy, value: c.isPressed)
    }
}

struct RecentRow: View {
    let rec: Recording
    var open: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let t = rec.thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) } else { DS.fill }
            }
            .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.lineHi))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.name.replacingOccurrences(of: "Запись ", with: "")).font(DS.font(12, .medium)).foregroundStyle(DS.text).lineLimit(1)
                let d = rec.loadMeta()
                Text("\(Int(d.duration) / 60):\(String(format: "%02d", Int(d.duration) % 60)) · \(d.clicks.count) кликов")
                    .font(DS.font(10.5)).foregroundStyle(DS.text3)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(hover ? DS.text : DS.text3)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hover ? DS.fillHi : DS.fill))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(DS.snappy) { hover = h } }
        .onTapGesture(perform: open)
    }
}

extension AppDelegate {
    /// REEL_EXPORT=<path to .reel> — пересобрать готовое видео без интерфейса.
    func headlessExport(_ path: String) {
        let rec = Recording(dir: URL(fileURLWithPath: path))
        let m = EditorModel(rec: rec)
        m.export()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                if m.exportProgress == nil {
                    print(m.exported?.path ?? (m.error ?? "fail"))
                    exit(m.exported == nil ? 1 : 0)
                }
            }
        }
    }
}

