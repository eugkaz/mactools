import AppKit
import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct PreviewPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

enum VTab: String, CaseIterable, Identifiable {
    case media = "Медиа", text = "Текст", audio = "Аудио", filters = "Фильтры", format = "Формат", export = "Экспорт"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .media: return "film.stack"
        case .text: return "textformat"
        case .audio: return "music.note"
        case .filters: return "camera.filters"
        case .format: return "aspectratio"
        case .export: return "square.and.arrow.up"
        }
    }
}

struct VideoStudioView: View {
    @State var p = VideoProject()
    @State private var tab: VTab = .media
    @State private var pps: CGFloat = 60          // пикселей на секунду
    @State private var exportFormat = "mp4"
    @State private var exportHeight = 1080
    let url: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                ScrollView { leftPanel.padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollIndicators(.never)
                    .frame(width: 262).background(DS.bg1)
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.line).frame(width: 1) }
                VStack(spacing: 0) {
                    preview
                    transport
                }
                .background(StudioBackdrop(accent: .shifty))
                VideoInspector(p: p).frame(width: 262).background(DS.bg1)
                    .overlay(alignment: .leading) { Rectangle().fill(DS.line).frame(width: 1) }
            }
            TimelineView2(p: p, pps: $pps).frame(height: 214)
                .background(DS.bg0)
                .overlay(alignment: .top) { Rectangle().fill(DS.lineHi).frame(height: 1) }
        }
        .background(DS.bg0)
        .environment(\.colorScheme, .dark)
        .tint(Accent.shifty.b)
        .overlay { if let e = p.exporting { exportOverlay(e) } }
        .task {
            if let url {
                await p.addClip(url)
                fitTimeline()
            }
        }
        .background(VideoKeys(p: p))
        .onDisappear { p.player.pause() }
    }

    func fitTimeline() { pps = max(8, min(200, 700 / max(1, p.total))) }

    var rail: some View {
        StudioRail(items: VTab.allCases.map { ($0, $0.rawValue, $0.icon) }, selection: $tab, accent: .shifty)
    }

    var preview: some View {
        ZStack {
            if p.clips.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Accent.shifty.b.opacity(0.25)).frame(width: 110, height: 110).blur(radius: 20)
                        IconTile(symbol: "film.stack", accent: .shifty, size: 64)
                    }
                    Text("Перетащи видео сюда").font(DS.font(18, .bold, rounded: true)).foregroundStyle(DS.text)
                    Text("или открой вкладку «Медиа» слева").font(DS.font(12)).foregroundStyle(DS.text2)
                }
            } else {
                let R = p.renderSize
                PreviewPlayer(player: p.player)
                    .aspectRatio(R.width / R.height, contentMode: .fit)
                    .overlay(TextDragLayer(p: p))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 28)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for pr in providers {
                _ = pr.loadObject(ofClass: URL.self) { u, _ in
                    guard let u else { return }
                    Task { @MainActor in
                        if Files.kind(u) == .audio { await p.addMusic(u) } else { await p.addClip(u); fitTimeline() }
                    }
                }
            }
            return true
        }
    }

    var transport: some View {
        HStack(spacing: 10) {
            CircleIconButton(symbol: "arrow.uturn.backward", size: 28) { p.undo() }.disabled(!p.canUndo).opacity(p.canUndo ? 1 : 0.4).help("⌘Z")
            CircleIconButton(symbol: "arrow.uturn.forward", size: 28) { p.redo() }.disabled(!p.canRedo).opacity(p.canRedo ? 1 : 0.4).help("⇧⌘Z")
            Spacer()
            CircleIconButton(symbol: "backward.end.fill", size: 30) { p.seek(0) }
            Button { p.togglePlay() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Accent.shifty.gradient)).overlay(Circle().strokeBorder(.white.opacity(0.25)))
                    .shadow(color: Accent.shifty.b.opacity(0.6), radius: 10)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).help("Пробел")
            CircleIconButton(symbol: "forward.end.fill", size: 30) { p.seek(p.total) }
            HStack(spacing: 3) {
                Text(fmt(p.playhead)).foregroundStyle(DS.text)
                Text("/ " + fmt(p.total)).foregroundStyle(DS.text3)
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(DS.fill))
            Spacer()
            Button { p.split() } label: { Label("Разрезать", systemImage: "scissors") }.buttonStyle(PillButtonStyle()).help("S")
            CircleIconButton(symbol: "trash", size: 30) { p.deleteSelection() }.disabled(p.selection == nil).opacity(p.selection == nil ? 0.4 : 1).help("⌫")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    func fmt(_ t: Double) -> String {
        let s = max(0, t)
        return String(format: "%02d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    func header(_ s: String) -> some View { SectionLabel(text: s).padding(.top, 8) }

    @ViewBuilder var leftPanel: some View {
        switch tab {
        case .media:
            VStack(alignment: .leading, spacing: 8) {
                header("Клипы")
                Button { pick([.movie, .video, .mpeg4Movie, .quickTimeMovie]) { u in Task { await p.addClip(u); fitTimeline() } } } label: {
                    Label("Добавить видео…", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(PillButtonStyle(accent: .shifty, height: 38))
                ForEach(p.clips) { c in
                    HStack(spacing: 8) {
                        if let t = p.thumbs[c.id]?.first { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 28).clipped().cornerRadius(4) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.url.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                            Text(String(format: "%.1f с%@", c.duration, c.speed != 1 ? String(format: " · %.2g×", c.speed) : "")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(p.selection == .clip(c.id) ? Accent.shifty.b.opacity(0.2) : DS.fill))
                    .onTapGesture { p.selection = .clip(c.id); p.seek(p.clipStart(c.id)) }
                }
                Text("Перетаскивайте края клипа на таймлайне, чтобы обрезать. S — разрезать по курсору.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        case .text:
            VStack(alignment: .leading, spacing: 8) {
                header("Добавить текст в позицию курсора")
                tpl("Заголовок", "title", Font.system(size: 20, weight: .heavy))
                tpl("Субтитры", "sub", Font.system(size: 13, weight: .semibold))
                tpl("НЕОН", "neon", Font.system(size: 18, weight: .black))
                tpl("ВАУ! с обводкой", "outline", Font.system(size: 16, weight: .black))
                tpl("Печатная машинка…", "type", Font.system(size: 13, design: .monospaced))
                Text("Текст можно двигать мышью прямо на превью").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        case .audio:
            VStack(alignment: .leading, spacing: 8) {
                header("Музыка")
                Button { pick([.audio, .mp3, .mpeg4Audio, .wav]) { u in Task { await p.addMusic(u) } } } label: {
                    Label(p.music == nil ? "Добавить музыку…" : "Заменить музыку…", systemImage: "music.note").frame(maxWidth: .infinity)
                }.buttonStyle(PillButtonStyle(accent: .shifty, height: 38))
                if let m = p.music {
                    Text(m.url.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                    Button("Настроить музыку") { p.selection = .music }
                }
                header("Звук видео")
                HStack { Text("Громкость"); Slider(value: Binding(get: { p.originalVolume }, set: { p.originalVolume = $0; p.scheduleRebuild() }), in: 0...2) }
                Button("Выключить звук всех клипов") { p.checkpoint(); for i in p.clips.indices { p.clips[i].muted = true }; p.scheduleRebuild() }
            }
        case .filters:
            VStack(alignment: .leading, spacing: 8) {
                header("Фильтр")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                    ForEach(Preset.allCases) { pr in
                        Button { p.checkpoint(); p.preset = pr; p.scheduleRebuild() } label: {
                            Text(pr.rawValue).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 7).fill(p.preset == pr ? Accent.shifty.b : DS.fill))
                                .foregroundStyle(p.preset == pr ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                header("Коррекция")
                adj("Яркость", \.brightness, -0.4...0.4)
                adj("Контраст", \.contrast, 0.5...1.6)
                adj("Насыщенность", \.saturation, 0...2)
                Toggle("Плавное появление и затухание", isOn: Binding(get: { p.fade }, set: { p.fade = $0; p.scheduleRebuild() }))
            }
        case .format:
            VStack(alignment: .leading, spacing: 8) {
                header("Формат кадра")
                ForEach(CanvasAspect.allCases) { a in
                    Button { p.checkpoint(); p.aspect = a; p.scheduleRebuild() } label: {
                        HStack {
                            Text(a.rawValue).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(a == .vertical ? "TikTok, Reels, Shorts" : a == .wide ? "YouTube" : a == .square ? "Пост" : a == .portrait ? "Instagram" : "")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(8).background(RoundedRectangle(cornerRadius: 7).fill(p.aspect == a ? Accent.shifty.b.opacity(0.2) : DS.fill))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                header("Заполнение")
                Picker("", selection: Binding(get: { p.fit }, set: { p.fit = $0; p.scheduleRebuild() })) {
                    ForEach(FitMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.radioGroup).labelsHidden()
            }
        case .export:
            VStack(alignment: .leading, spacing: 10) {
                header("Экспорт")
                Picker("Формат", selection: $exportFormat) { Text("MP4").tag("mp4"); Text("MOV").tag("mov"); Text("GIF").tag("gif") }
                    .pickerStyle(.segmented)
                Picker("Качество", selection: $exportHeight) { Text("720p").tag(720); Text("1080p").tag(1080); Text("Макс.").tag(0) }
                    .pickerStyle(.segmented)
                let R = p.renderSize
                Text("Кадр: \(Int(R.width))×\(Int(R.height)) · \(String(format: "%.1f", p.total)) с").font(.system(size: 11)).foregroundStyle(.secondary)
                Button { Task { await p.export(format: exportFormat, height: exportFormat == "gif" ? 480 : exportHeight) } } label: {
                    Label("Экспортировать", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(PillButtonStyle(accent: .shifty, height: 38)).disabled(p.clips.isEmpty || p.exporting != nil)
                    .keyboardShortcut("e", modifiers: .command)
                if exportFormat == "gif" && Tools.ffmpegPath == nil { Text("Для GIF нужен ffmpeg").font(.system(size: 10)).foregroundStyle(.orange) }
                if let s = p.status { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
    }

    func adj(_ t: String, _ kp: ReferenceWritableKeyPath<VideoProject, Double>, _ r: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 11))
            Slider(value: Binding(get: { p[keyPath: kp] }, set: { p[keyPath: kp] = $0; p.scheduleRebuild() }), in: r)
        }
    }

    func tpl(_ title: String, _ key: String, _ font: Font) -> some View {
        Button { p.addText(key) } label: {
            Text(title).font(font).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    func pick(_ types: [UTType], _ f: @escaping (URL) -> Void) {
        let o = NSOpenPanel()
        o.allowedContentTypes = types
        o.allowsMultipleSelection = true
        if o.runModal() == .OK { o.urls.forEach(f) }
    }

    func exportOverlay(_ e: Double) -> some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                Text("Экспорт…").font(.system(size: 16, weight: .bold))
                ProgressView(value: e).frame(width: 260)
                Text("\(Int(e * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }.padding(28).background(GlassBackground(accent: .shifty, radius: 20))
        }
    }
}

/// Перетаскивание текстов прямо на превью
struct TextDragLayer: View {
    let p: VideoProject
    @State private var start: CGPoint?
    var body: some View {
        GeometryReader { g in
            ForEach(p.texts.filter { p.playhead >= $0.start && p.playhead <= $0.end }) { t in
                let sel = p.selection == .text(t.id)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(sel ? Accent.shifty.a : Color.white.opacity(0.0001), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .frame(width: max(60, g.size.width * CGFloat(t.size) * CGFloat(max(3, t.text.count)) * 0.55 * g.size.height / g.size.width),
                           height: g.size.height * CGFloat(t.size) * 1.5)
                    .contentShape(Rectangle())
                    .position(x: t.pos.x * g.size.width, y: t.pos.y * g.size.height)
                    .gesture(DragGesture().onChanged { v in
                        if start == nil { start = t.pos; p.checkpoint(); p.selection = .text(t.id) }
                        guard let s = start else { return }
                        p.updateText(t.id) {
                            $0.pos = CGPoint(x: min(1, max(0, s.x + v.translation.width / g.size.width)), y: min(1, max(0, s.y + v.translation.height / g.size.height)))
                        }
                    }.onEnded { _ in start = nil })
                    .onTapGesture { p.selection = .text(t.id) }
            }
        }
    }
}

struct VideoKeys: NSViewRepresentable {
    let p: VideoProject
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.m = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak v] e in
            guard let w = v?.window, w.isKeyWindow, !(w.firstResponder is NSTextView) else { return e }
            let cmd = e.modifierFlags.contains(.command)
            switch (e.keyCode, cmd) {
            case (49, false): p.togglePlay(); return nil                                   // пробел
            case (1, false): p.split(); return nil                                         // S
            case (51, false), (117, false): p.deleteSelection(); return nil
            case (6, true): e.modifierFlags.contains(.shift) ? p.redo() : p.undo(); return nil
            case (2, true): p.duplicateClip(); return nil
            case (123, false): p.seek(p.playhead - (e.modifierFlags.contains(.shift) ? 1 : 1.0 / 30)); return nil
            case (124, false): p.seek(p.playhead + (e.modifierFlags.contains(.shift) ? 1 : 1.0 / 30)); return nil
            default: return e
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> C { C() }
    final class C { var m: Any?; deinit { if let m { NSEvent.removeMonitor(m) } } }
}
