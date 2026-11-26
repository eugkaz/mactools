import AppKit
import SwiftUI
import AVKit
import AVFoundation

@MainActor @Observable
final class EditorModel {
    let rec: Recording
    var meta: RecMeta
    var style: Style { didSet { if style != oldValue { changed() } } }
    var segs: [ZoomSeg] { didSet { if segs != oldValue { changed() } } }
    let player = AVPlayer()
    var time: Double = 0
    var duration: Double = 0
    var playing = false
    var thumbs: [NSImage] = []
    var exportProgress: Double?
    var exported: URL?
    var error: String?
    private var asset: AVURLAsset
    private var rebuild: Task<Void, Never>?
    private var observer: Any?

    init(rec: Recording) {
        self.rec = rec
        let mt = rec.loadMeta()
        meta = mt
        asset = AVURLAsset(url: rec.video)
        if let e = rec.loadEdit() { style = e.style; segs = e.segs }
        else {
            var st = Style()
            if let d = UserDefaults.standard.data(forKey: "lastStyle"), let s = try? JSONDecoder().decode(Style.self, from: d) {
                st = s; st.trimStart = 0; st.trimEnd = nil
            }
            style = st
            segs = AutoEdit.segments(mt, zoom: st.zoom)
        }
        duration = mt.duration
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = t.seconds
                self.playing = self.player.rate > 0
                let end = self.style.trimEnd ?? self.duration
                if self.playing, self.time >= end - 0.02 { self.player.pause(); self.seek(self.style.trimStart) }
            }
        }
        Task { await apply(); await makeThumbs() }
    }

    private func changed() {
        rec.saveEdit(.init(style: style, segs: segs))
        if let d = try? JSONEncoder().encode(style) { UserDefaults.standard.set(d, forKey: "lastStyle") }
        rebuild?.cancel()
        rebuild = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await apply()
        }
    }

    private func apply() async {
        do {
            let (vc, _) = try await Render.composition(asset: asset, meta: meta, style: style, segs: segs)
            player.currentItem?.videoComposition = vc
            if !playing { player.currentItem?.seek(to: player.currentTime(), completionHandler: nil) }
        } catch { self.error = error.localizedDescription }
    }

    private func makeThumbs() async {
        let g = AVAssetImageGenerator(asset: asset)
        g.maximumSize = CGSize(width: 220, height: 140)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
        var out: [NSImage] = []
        let n = 14
        for i in 0..<n {
            let t = CMTime(seconds: duration * (Double(i) + 0.5) / Double(n), preferredTimescale: 600)
            if let (img, _) = try? await g.image(at: t) { out.append(NSImage(cgImage: img, size: .zero)) }
        }
        thumbs = out
    }

    func toggle() {
        if playing { player.pause() } else {
            if time >= (style.trimEnd ?? duration) - 0.05 { seek(style.trimStart) }
            player.play()
        }
    }
    func seek(_ t: Double) {
        let c = min(max(0, t), duration)
        time = c
        player.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func resetZooms() { segs = AutoEdit.segments(meta, zoom: style.zoom) }
    func addZoom() {
        let s = max(0, time - 0.6), e = min(duration, time + 2.4)
        segs.append(ZoomSeg(start: s, end: e, scale: style.zoom)); segs.sort { $0.start < $1.start }
    }
    func setZoomAll(_ z: Double) {
        style.zoom = z
        segs = segs.map { var s = $0; s.scale = z; return s }
    }

    func export() {
        guard exportProgress == nil else { return }
        player.pause()
        let dir = Recording.root.appendingPathComponent("Готовые")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(rec.name + ".mp4")
        exportProgress = 0; exported = nil; error = nil
        let (r, m, st, sg) = (rec, meta, style, segs)
        Task {
            do {
                try await Render.export(r, meta: m, style: st, segs: sg, to: url) { p in
                    DispatchQueue.main.async { MainActor.assumeIsolated { if self.exportProgress != nil { self.exportProgress = p } } }
                }
                exportProgress = nil; exported = url
                NSSound(named: "Glass")?.play()
            } catch {
                exportProgress = nil; self.error = "Экспорт не удался: \(error.localizedDescription)"
            }
        }
    }
    func copyExported() {
        guard let u = exported else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([u as NSURL])
    }
    func close() { player.pause(); if let o = observer { player.removeTimeObserver(o) }; observer = nil }
}

// MARK: - Окно

@MainActor
enum EditorWindow {
    private static var windows: [NSWindow] = []
    static func open(_ rec: Recording) {
        let m = EditorModel(rec: rec)
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 860),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua); w.backgroundColor = NSColor(DS.bg0)
        w.isReleasedWhenClosed = false; w.minSize = NSSize(width: 1080, height: 700)
        w.contentView = NSHostingView(rootView: EditorView(m: m))
        w.center()
        let d = CloseWatcher(m: m) { [weak w] in windows.removeAll { $0 === w }; if windows.isEmpty { NSApp.setActivationPolicy(.accessory) } }
        w.delegate = d
        objc_setAssociatedObject(w, "d", d, .OBJC_ASSOCIATION_RETAIN)
        windows.append(w)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
    final class CloseWatcher: NSObject, NSWindowDelegate {
        let m: EditorModel; let done: () -> Void
        init(m: EditorModel, done: @escaping () -> Void) { self.m = m; self.done = done }
        func windowWillClose(_ n: Notification) { MainActor.assumeIsolated { m.close(); done() } }
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; v.videoGravity = .resizeAspect
        v.wantsLayer = true; v.layer?.backgroundColor = .clear
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
}

struct EditorView: View {
    @Bindable var m: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                preview
                transport
                TimelineStrip(m: m).frame(height: 132).padding(.horizontal, 18).padding(.bottom, 16)
            }
            .background(EditorBackdrop())
            Inspector(m: m).frame(width: 312)
                .background(DS.bg1)
                .overlay(alignment: .leading) { Rectangle().fill(DS.line).frame(width: 1) }
        }
        .environment(\.colorScheme, .dark)
        .tint(Accent.reel.b)
        .background(KeySpace(m: m))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(m.rec.name).font(DS.font(13, .semibold)).foregroundStyle(DS.text)
            Text(fmt(m.duration)).font(DS.font(11, .semibold, rounded: true)).foregroundStyle(DS.text3)
                .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(DS.fill))
            Spacer()
            if let e = m.error { Text(e).font(DS.font(11)).foregroundStyle(Accent.warn.a).lineLimit(1) }
        }
        .padding(.leading, 86).padding(.trailing, 18).frame(height: 44)
    }

    private var preview: some View {
        PlayerSurface(player: m.player)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { m.toggle() }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Text(fmt(m.time)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(DS.text).frame(width: 56, alignment: .trailing)
            CircleIconButton(symbol: "gobackward.5", size: 30) { m.seek(m.time - 5) }
            Button { m.toggle() } label: {
                Image(systemName: m.playing ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Accent.reel.gradient)).overlay(Circle().strokeBorder(.white.opacity(0.25)))
                    .shadow(color: Accent.reel.b.opacity(0.6), radius: 10)
                    .contentTransition(.symbolEffect(.replace))
            }.buttonStyle(.plain).help("Пробел")
            CircleIconButton(symbol: "goforward.5", size: 30) { m.seek(m.time + 5) }
            Text(fmt(m.duration)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(DS.text3).frame(width: 56, alignment: .leading)
        }
        .padding(.bottom, 12)
    }

    func fmt(_ t: Double) -> String { let s = max(0, Int(t)); return String(format: "%d:%02d", s / 60, s % 60) }
}

struct EditorBackdrop: View {
    var body: some View {
        ZStack {
            DS.bg0
            RadialGradient(colors: [Accent.reel.b.opacity(0.14), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 650)
        }
    }
}

/// Пробел — play/pause, стрелки — ±1 с
struct KeySpace: NSViewRepresentable {
    let m: EditorModel
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak v] e in
            guard let w = v?.window, w.isKeyWindow, !(w.firstResponder is NSTextView) else { return e }
            switch e.keyCode {
            case 49: MainActor.assumeIsolated { m.toggle() }; return nil
            case 123: MainActor.assumeIsolated { m.seek(m.time - 1) }; return nil
            case 124: MainActor.assumeIsolated { m.seek(m.time + 1) }; return nil
            default: return e
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> C { C() }
    final class C { var mon: Any?; deinit { if let m = mon { NSEvent.removeMonitor(m) } } }
}

// MARK: - Таймлайн

struct TimelineStrip: View {
    @Bindable var m: EditorModel
    @State private var hoverSeg: UUID?

    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let D = max(m.duration, 0.01)
            let x = { (t: Double) -> CGFloat in CGFloat(t / D) * W }
            VStack(alignment: .leading, spacing: 8) {
                // зумы
                HStack(spacing: 8) {
                    SectionLabel(text: "Приближения")
                    Spacer()
                    Button { m.addZoom() } label: { Label("Зум здесь", systemImage: "plus.magnifyingglass") }.buttonStyle(PillButtonStyle(height: 24))
                    Button { m.resetZooms() } label: { Label("Заново по кликам", systemImage: "wand.and.stars") }.buttonStyle(PillButtonStyle(height: 24))
                }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.fill).frame(height: 30)
                    ForEach(m.segs) { s in
                        let on = s.enabled
                        HStack(spacing: 4) {
                            Image(systemName: "plus.magnifyingglass").font(.system(size: 9, weight: .bold))
                            if x(s.end) - x(s.start) > 46 { Text(String(format: "%.1f×", s.scale)).font(DS.font(10, .bold, rounded: true)) }
                        }
                        .foregroundStyle(on ? .white : DS.text3)
                        .frame(width: max(14, x(s.end) - x(s.start)), height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? AnyShapeStyle(Accent.reel.gradient) : AnyShapeStyle(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(hoverSeg == s.id ? 0.6 : 0.15))))
                        .shadow(color: on ? Accent.reel.b.opacity(0.4) : .clear, radius: 5)
                        .offset(x: x(s.start))
                        .onHover { hoverSeg = $0 ? s.id : nil }
                        .onTapGesture { if let i = m.segs.firstIndex(where: { $0.id == s.id }) { m.segs[i].enabled.toggle() } }
                        .contextMenu {
                            ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { z in
                                Button(String(format: "Зум %.1f×", z)) { if let i = m.segs.firstIndex(where: { $0.id == s.id }) { m.segs[i].scale = z } }
                            }
                            Divider()
                            Button("Перейти сюда") { m.seek(s.start) }
                            Button("Удалить") { m.segs.removeAll { $0.id == s.id } }
                        }
                        .help("Клик — вкл/выкл, правый клик — сила и удаление")
                    }
                }
                // кадры + клики
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(Array(m.thumbs.enumerated()), id: \.offset) { _, i in
                            Image(nsImage: i).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: W / CGFloat(max(m.thumbs.count, 1)), height: 52).clipped()
                        }
                    }
                    .frame(width: W, height: 52, alignment: .leading)
                    .background(DS.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DS.lineHi))
                    // обрезка
                    Rectangle().fill(.black.opacity(0.6)).frame(width: x(m.style.trimStart), height: 52)
                    Rectangle().fill(.black.opacity(0.6)).frame(width: W - x(m.style.trimEnd ?? D), height: 52).offset(x: x(m.style.trimEnd ?? D))
                    TrimHandle().offset(x: x(m.style.trimStart) - 5)
                        .gesture(DragGesture().onChanged { v in
                            m.style.trimStart = min(max(0, Double(v.location.x / W) * D), (m.style.trimEnd ?? D) - 0.5)
                        })
                    TrimHandle().offset(x: x(m.style.trimEnd ?? D) - 5)
                        .gesture(DragGesture().onChanged { v in
                            let e = min(D, max(Double(v.location.x / W) * D, m.style.trimStart + 0.5))
                            m.style.trimEnd = e >= D - 0.05 ? nil : e
                        })
                    ForEach(Array(m.meta.clicks.enumerated()), id: \.offset) { _, c in
                        Circle().fill(.white).frame(width: 6, height: 6).shadow(color: Accent.reel.a, radius: 3)
                            .offset(x: x(c[0]) - 3, y: 30)
                    }
                    // курсор времени
                    VStack(spacing: 0) {
                        Circle().fill(.white).frame(width: 11, height: 11).shadow(color: .black.opacity(0.5), radius: 2)
                        Rectangle().fill(.white).frame(width: 2, height: 64)
                    }
                    .offset(x: x(m.time) - 5.5, y: -6)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in m.seek(Double(v.location.x / W) * D) })
            }
        }
    }
}

struct TrimHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 10, height: 58)
            .overlay(Capsule().fill(Color.black.opacity(0.35)).frame(width: 2, height: 18))
            .shadow(color: .black.opacity(0.5), radius: 3)
            .contentShape(Rectangle().inset(by: -6))
            .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
    }
}

// MARK: - Правая панель

struct Inspector: View {
    @Bindable var m: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Фон", "paintpalette.fill") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(0..<Backdrops.all.count, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Backdrops.swatch(i))
                                    .frame(height: 38)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(m.style.bg == i ? Color.white : Color.white.opacity(0.1), lineWidth: m.style.bg == i ? 2 : 1))
                                    .shadow(color: m.style.bg == i ? .white.opacity(0.3) : .clear, radius: 5)
                                    .onTapGesture { withAnimation(DS.snappy) { m.style.bg = i } }
                                    .help(Backdrops.all[i].name)
                            }
                        }
                    }
                    section("Рамка", "rectangle.inset.filled") {
                        slider("Поля", $m.style.padding, 0...0.16, pct: true)
                        slider("Скругление", $m.style.radius, 0...0.04, pct: true)
                        slider("Тень", $m.style.shadow, 0...1, pct: true)
                    }
                    section("Приближение", "plus.magnifyingglass") {
                        Toggle(isOn: $m.style.autoZoom) { Text("Наезжать на клики").font(DS.font(12.5)).foregroundStyle(DS.text) }
                            .toggleStyle(GlowToggleStyle(accent: .reel))
                        Segmented(items: [(1.5, "1.5×"), (2.0, "2×"), (2.5, "2.5×"), (3.0, "3×")], selection: m.style.zoom, accent: .reel) { m.setZoomAll($0) }
                        Text("Найдено \(m.segs.count) \(plural(m.segs.count)) по \(m.meta.clicks.count) кликам").font(DS.font(10.5)).foregroundStyle(DS.text3)
                    }
                    section("Курсор", "cursorarrow") {
                        if m.meta.customCursor {
                            slider("Размер", $m.style.cursorSize, 0.8...3, pct: false)
                            Toggle(isOn: $m.style.smoothCursor) { Text("Плавное движение").font(DS.font(12.5)).foregroundStyle(DS.text) }
                                .toggleStyle(GlowToggleStyle(accent: .reel))
                        } else {
                            Text("Записан системный курсор").font(DS.font(11)).foregroundStyle(DS.text3)
                        }
                        Toggle(isOn: $m.style.ripple) { Text("Подсветка кликов").font(DS.font(12.5)).foregroundStyle(DS.text) }
                            .toggleStyle(GlowToggleStyle(accent: .reel))
                    }
                    section("Качество", "sparkles.tv") {
                        Segmented(items: [(1280, "720p"), (1920, "1080p"), (2560, "1440p"), (3840, "4K")], selection: m.style.outWidth, accent: .reel) { m.style.outWidth = $0 }
                    }
                }
                .padding(18).padding(.top, 26)
            }
            .scrollIndicators(.never)
            exportBar
        }
    }

    private var exportBar: some View {
        VStack(spacing: 10) {
            if let p = m.exportProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Собираю видео…").font(DS.font(12, .semibold)); Spacer(); Text("\(Int(p * 100))%").font(DS.font(12, .bold, rounded: true)).monospacedDigit() }
                        .foregroundStyle(DS.text)
                    GlowBar(value: p, accent: .reel, height: 6)
                }
            } else if let u = m.exported {
                HStack(spacing: 10) {
                    ZStack { Circle().fill(Accent.mint.gradient).frame(width: 28, height: 28); Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Готово!").font(DS.font(13, .bold)).foregroundStyle(DS.text)
                        Text(u.lastPathComponent).font(DS.font(10.5)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("В Finder", systemImage: "folder") }
                        .buttonStyle(PillButtonStyle(height: 30)).frame(maxWidth: .infinity)
                    Button { m.copyExported() } label: { Label("Копировать", systemImage: "doc.on.doc") }
                        .buttonStyle(PillButtonStyle(height: 30)).frame(maxWidth: .infinity)
                        .help("Скопировать файл — вставь в Telegram, Slack, почту")
                }
            }
            Button { m.export() } label: {
                HStack { Image(systemName: "square.and.arrow.up.fill"); Text(m.exported == nil ? "Экспорт MP4" : "Экспортировать снова") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(accent: .reel, height: 42))
            .disabled(m.exportProgress != nil)
            .keyboardShortcut("e", modifiers: .command)
        }
        .padding(16)
        .background(DS.bg0.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }

    private func section<C: View>(_ t: String, _ s: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Accent.reel.gradient)
                Text(t).font(DS.font(13, .semibold)).foregroundStyle(DS.text)
            }
            c()
        }
    }
    private func slider(_ t: String, _ b: Binding<Double>, _ r: ClosedRange<Double>, pct: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(t).font(DS.font(12)).foregroundStyle(DS.text2)
                Spacer()
                Text(pct ? "\(Int((b.wrappedValue - r.lowerBound) / (r.upperBound - r.lowerBound) * 100))%" : String(format: "%.1f×", b.wrappedValue))
                    .font(DS.font(11, .semibold, rounded: true)).foregroundStyle(DS.text3).monospacedDigit()
            }
            GlowSlider(value: b, range: r, accent: .reel)
        }
    }
    private func plural(_ n: Int) -> String {
        let a = n % 10, b = n % 100
        if a == 1 && b != 11 { return "наезд" }
        if (2...4).contains(a) && !(12...14).contains(b) { return "наезда" }
        return "наездов"
    }
}
