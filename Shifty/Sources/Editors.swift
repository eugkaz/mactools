import AppKit
import SwiftUI
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - Image editor

enum Preset: String, CaseIterable, Identifiable {
    case none = "Оригинал", vivid = "Сочный", mono = "Ч/Б", noir = "Нуар", sepia = "Сепия", chrome = "Хром",
         fade = "Выцветший", instant = "Полароид", process = "Процесс", transfer = "Трансфер", tonal = "Тональный"
    var id: String { rawValue }
    var ciName: String? {
        switch self {
        case .none, .vivid: return nil
        case .mono: return "CIPhotoEffectMono"
        case .noir: return "CIPhotoEffectNoir"
        case .sepia: return "CISepiaTone"
        case .chrome: return "CIPhotoEffectChrome"
        case .fade: return "CIPhotoEffectFade"
        case .instant: return "CIPhotoEffectInstant"
        case .process: return "CIPhotoEffectProcess"
        case .transfer: return "CIPhotoEffectTransfer"
        case .tonal: return "CIPhotoEffectTonal"
        }
    }
}

enum Aspect: String, CaseIterable, Identifiable {
    case original = "Исходный", square = "1:1", r45 = "4:5", r43 = "4:3", r32 = "3:2", r169 = "16:9", r916 = "9:16"
    var id: String { rawValue }
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .r45: return 4.0 / 5
        case .r43: return 4.0 / 3
        case .r32: return 3.0 / 2
        case .r169: return 16.0 / 9
        case .r916: return 9.0 / 16
        }
    }
}

enum OutFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", heic = "HEIC", webp = "WebP", avif = "AVIF", tiff = "TIFF"
    var id: String { rawValue }
    var uti: String {
        switch self {
        case .png: return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .webp: return Imaging.webp
        case .avif: return "public.avif"
        case .tiff: return UTType.tiff.identifier
        }
    }
    var ext: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
    var lossy: Bool { self != .png && self != .tiff }
    static func guess(_ url: URL) -> OutFormat {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "heic": return .heic
        case "webp": return .webp
        case "avif": return .avif
        case "tif", "tiff": return .tiff
        default: return .png
        }
    }
}

struct EditSettings: Equatable {
    var rotation = 0
    var flipH = false
    var flipV = false
    var exposure = 0.0
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var sharpen = 0.0
    var vignette = 0.0
    var blur = 0.0
    var preset: Preset = .none
    var aspect: Aspect = .original
    var scale = 100.0
}

enum ImagePipeline {
    static let ctx = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(_ input: CIImage, _ s: EditSettings, finalScale: Bool) -> CIImage {
        var img = input
        if s.flipH { img = img.oriented(.upMirrored) }
        if s.flipV { img = img.oriented(.downMirrored) }
        for _ in 0..<((s.rotation % 4 + 4) % 4) { img = img.oriented(.right) }
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))

        if let r = s.aspect.ratio {
            let e = img.extent
            var w = e.width, h = e.height
            if w / h > r { w = h * r } else { h = w / r }
            img = img.cropped(to: CGRect(x: (e.width - w) / 2, y: (e.height - h) / 2, width: w, height: h))
            img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        }
        let extent = img.extent

        if s.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(s.exposure); img = f.outputImage ?? img
        }
        let cc = CIFilter.colorControls()
        cc.inputImage = img
        cc.brightness = Float(s.brightness)
        cc.contrast = Float(s.contrast)
        cc.saturation = Float(s.saturation * (s.preset == .vivid ? 1.35 : 1))
        img = cc.outputImage ?? img
        if s.preset == .vivid {
            let v = CIFilter.vibrance(); v.inputImage = img; v.amount = 0.6; img = v.outputImage ?? img
        }
        if s.warmth != 0 {
            let t = CIFilter.temperatureAndTint()
            t.inputImage = img
            t.neutral = CIVector(x: 6500, y: 0)
            t.targetNeutral = CIVector(x: 6500 - s.warmth * 2500, y: 0)
            img = t.outputImage ?? img
        }
        if let name = s.preset.ciName, let f = CIFilter(name: name) {
            f.setValue(img, forKey: kCIInputImageKey)
            img = f.outputImage ?? img
        }
        if s.sharpen > 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = img; f.sharpness = Float(s.sharpen); img = f.outputImage ?? img
        }
        if s.blur > 0 {
            let f = CIFilter.gaussianBlur(); f.inputImage = img.clampedToExtent(); f.radius = Float(s.blur * extent.width / 400)
            img = (f.outputImage ?? img).cropped(to: extent)
        }
        if s.vignette > 0 {
            let f = CIFilter.vignette(); f.inputImage = img; f.intensity = Float(s.vignette * 2); f.radius = 2; img = f.outputImage ?? img
        }
        img = img.cropped(to: extent)
        if finalScale && s.scale != 100 {
            let f = CIFilter.lanczosScaleTransform(); f.inputImage = img; f.scale = Float(s.scale / 100); f.aspectRatio = 1
            img = f.outputImage ?? img
        }
        return img
    }

    static func render(_ img: CIImage) -> CGImage? {
        ctx.createCGImage(img, from: img.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}

struct ImageEditorView: View {
    let url: URL
    @State private var full: CIImage?
    @State private var previewBase: CIImage?
    @State private var s = EditSettings()
    @State private var format: OutFormat = .png
    @State private var quality = 0.88
    @State private var preview: NSImage?
    @State private var showOriginal = false
    @State private var status: String?
    @State private var saved: URL?
    @State private var saving = false

    var outSize: String {
        guard let full else { return "" }
        var e = ImagePipeline.apply(full, EditSettings(rotation: s.rotation, aspect: s.aspect), finalScale: false).extent
        e.size.width *= s.scale / 100; e.size.height *= s.scale / 100
        return "\(Int(e.width)) × \(Int(e.height)) px"
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let img = showOriginal ? previewOriginal : preview {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(24)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                } else {
                    ProgressView()
                }
                VStack {
                    Spacer()
                    HStack {
                        Text(outSize).font(.system(size: 11, design: .monospaced)).padding(6).background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Text("Удерживайте — оригинал").font(.system(size: 11)).padding(6).background(.ultraThinMaterial, in: Capsule())
                            .onLongPressGesture(minimumDuration: 0.05, pressing: { showOriginal = $0 }, perform: {})
                    }.padding(12)
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Поворот") {
                        HStack {
                            iconButton("rotate.left") { s.rotation -= 1 }
                            iconButton("rotate.right") { s.rotation += 1 }
                            iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right") { s.flipH.toggle() }
                            iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down") { s.flipV.toggle() }
                        }
                    }
                    section("Кадрирование") {
                        Picker("", selection: $s.aspect) { ForEach(Aspect.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    }
                    section("Фильтр") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                            ForEach(Preset.allCases) { p in
                                Button { s.preset = p } label: {
                                    Text(p.rawValue).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(s.preset == p ? Accent.shifty.b : DS.fill))
                                        .foregroundStyle(s.preset == p ? .white : .primary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    section("Свет и цвет") {
                        slider("Экспозиция", $s.exposure, -2...2, 0)
                        slider("Яркость", $s.brightness, -0.5...0.5, 0)
                        slider("Контраст", $s.contrast, 0.5...1.6, 1)
                        slider("Насыщенность", $s.saturation, 0...2, 1)
                        slider("Теплота", $s.warmth, -1...1, 0)
                    }
                    section("Детали") {
                        slider("Резкость", $s.sharpen, 0...2, 0)
                        slider("Размытие", $s.blur, 0...10, 0)
                        slider("Виньетка", $s.vignette, 0...1, 0)
                    }
                    section("Экспорт") {
                        slider("Размер, %", $s.scale, 5...100, 100)
                        Picker("Формат", selection: $format) {
                            ForEach(OutFormat.allCases.filter { Imaging.canWrite($0.uti) }) { Text($0.rawValue).tag($0) }
                        }
                        if format.lossy { slider("Качество", $quality, 0.3...1, 0.88) }
                    }
                    HStack {
                        Button("Сбросить") { s = EditSettings() }
                        Spacer()
                        Button { save() } label: {
                            if saving { ProgressView().controlSize(.small) } else { Text("Сохранить копию") }
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(saving || full == nil)
                    }
                    if let status {
                        HStack {
                            Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            if let saved { Button("Показать") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }.controlSize(.small) }
                        }
                    }
                }
                .padding(18)
                .padding(.top, 20)
            }
            .frame(width: 300)
            .background(.regularMaterial)
        }
        .onAppear(perform: load)
        .onChange(of: s) { _, _ in renderPreview() }
    }

    @State private var previewOriginal: NSImage?

    func load() {
        format = OutFormat.guess(url)
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { status = "Не удалось открыть"; return }
        full = img
        let maxSide = max(img.extent.width, img.extent.height)
        let k = min(1, 1600 / maxSide)
        let base = img.transformed(by: CGAffineTransform(scaleX: k, y: k))
        previewBase = base
        if let cg = ImagePipeline.render(base) { previewOriginal = NSImage(cgImage: cg, size: .zero) }
        renderPreview()
    }

    func renderPreview() {
        guard let previewBase else { return }
        let out = ImagePipeline.apply(previewBase, s, finalScale: false)
        if let cg = ImagePipeline.render(out) { preview = NSImage(cgImage: cg, size: .zero) }
    }

    func save() {
        guard let full else { return }
        saving = true
        let settings = s, fmt = format, q = quality
        Task {
            do {
                let img = ImagePipeline.apply(full, settings, finalScale: true)
                guard let cg = ImagePipeline.render(img) else { throw ShiftyError("Ошибка рендера") }
                let out = Files.outputURL(for: url, ext: fmt.ext, suffix: " (edited)")
                try await Imaging.write(cg, to: out, uti: fmt.uti, quality: q)
                saved = out
                status = "Сохранено: \(out.lastPathComponent)"
                NSSound(named: "Glass")?.play()
            } catch {
                status = error.localizedDescription
            }
            saving = false
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            c()
        }
    }

    func iconButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 28, height: 22) }
    }

    func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ def: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(String(format: "%.2f", v.wrappedValue)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { v.wrappedValue = def }
            }
            Slider(value: v, in: r)
        }
    }
}

// MARK: - Video / audio editor

final class PlayerHolder: ObservableObject {
    weak var view: AVPlayerView?
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let holder: PlayerHolder
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .floating
        v.showsFrameSteppingButtons = true
        v.showsSharingServiceButton = false
        holder.view = v
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

enum MediaFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4 (H.264)", hevc = "MP4 (HEVC)", mov = "MOV", webm = "WebM", gif = "GIF", m4a = "M4A (звук)", mp3 = "MP3 (звук)", wav = "WAV (звук)", flac = "FLAC (звук)"
    var id: String { rawValue }
    var ext: String {
        switch self {
        case .mp4, .hevc: return "mp4"
        case .mov: return "mov"
        case .webm: return "webm"
        case .gif: return "gif"
        case .m4a: return "m4a"
        case .mp3: return "mp3"
        case .wav: return "wav"
        case .flac: return "flac"
        }
    }
    var audioOnly: Bool { [.m4a, .mp3, .wav, .flac].contains(self) }
    var codecArgs: [String] {
        switch self {
        case .mp4, .mov: return ["-c:v", "libx264", "-preset", "fast", "-crf", "21", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        case .hevc: return Media.hevcArgs
        case .webm: return Media.webmArgs
        case .gif: return ["-loop", "0"]
        case .m4a: return ["-vn", "-c:a", "aac", "-b:a", "256k"]
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-q:a", "0"]
        case .wav: return ["-vn", "-c:a", "pcm_s16le"]
        case .flac: return ["-vn", "-c:a", "flac"]
        }
    }
}

struct MediaEditorView: View {
    let url: URL
    let isAudio: Bool
    @State private var player: AVPlayer
    @StateObject private var holder = PlayerHolder()
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var duration: Double = 0
    @State private var format: MediaFormat
    @State private var height = 0
    @State private var mute = false
    @State private var speed = 1.0
    @State private var busy = false
    @State private var status: String?
    @State private var saved: URL?

    init(url: URL, isAudio: Bool) {
        self.url = url
        self.isAudio = isAudio
        _player = State(initialValue: AVPlayer(url: url))
        _format = State(initialValue: isAudio ? .m4a : .mp4)
    }

    var formats: [MediaFormat] {
        let all = isAudio ? MediaFormat.allCases.filter(\.audioOnly) : MediaFormat.allCases
        return Tools.ffmpegPath != nil ? all : all.filter { [.mp4, .hevc, .mov, .m4a].contains($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            PlayerView(player: player, holder: holder)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            VStack(alignment: .leading, spacing: 14) {
                Text("ОБРЕЗКА").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Button { trim() } label: { Label("Выбрать фрагмент", systemImage: "scissors") }
                HStack {
                    Text("с \(fmt(start))").monospacedDigit()
                    Spacer()
                    Text("по \(fmt(end))").monospacedDigit()
                }.font(.system(size: 12))
                HStack {
                    Button("Старт = сейчас") { start = player.currentTime().seconds }.controlSize(.small)
                    Button("Конец = сейчас") { end = player.currentTime().seconds }.controlSize(.small)
                }
                Divider()
                Text("ЭКСПОРТ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Формат", selection: $format) { ForEach(formats) { Text($0.rawValue).tag($0) } }
                if Tools.ffmpegPath != nil {
                    if !isAudio && !format.audioOnly {
                        Picker("Высота", selection: $height) {
                            Text("Исходная").tag(0); Text("1080p").tag(1080); Text("720p").tag(720); Text("480p").tag(480)
                        }
                        if format != .gif { Toggle("Без звука", isOn: $mute) }
                    }
                    Picker("Скорость", selection: $speed) {
                        Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0)
                    }.pickerStyle(.segmented)
                } else {
                    Text("Установите ffmpeg для GIF, WebM, MP3, скорости и разрешения").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let status {
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                    if let saved { Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }.controlSize(.small) }
                }
                Button { export() } label: {
                    HStack { if busy { ProgressView().controlSize(.small) }; Text(busy ? "Экспорт…" : "Сохранить копию") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(busy || end <= start)
            }
            .padding(18)
            .padding(.top, 20)
            .frame(width: 290)
            .background(.regularMaterial)
        }
        .task {
            let d = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            duration = d.isFinite ? d : 0
            end = duration
        }
        .onDisappear { player.pause() }
    }

    func fmt(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d.%d", s / 60, s % 60, Int((t - Double(s)) * 10))
    }

    func trim() {
        guard let v = holder.view, v.canBeginTrimming else { return }
        v.beginTrimming { result in
            guard result == .okButton, let item = player.currentItem else { return }
            let r = item.reversePlaybackEndTime, f = item.forwardPlaybackEndTime
            start = r.isValid ? r.seconds : 0
            end = f.isValid ? f.seconds : duration
        }
    }

    func export() {
        busy = true
        status = nil
        player.pause()
        let fmt = format, h = height, m = mute, sp = speed, st = start, en = end, dur = duration
        Task {
            do {
                let out: URL
                if Tools.ffmpegPath != nil {
                    var args: [String] = []
                    if st > 0.01 { args += ["-ss", String(format: "%.3f", st)] }
                    if en < dur - 0.01 { args += ["-to", String(format: "%.3f", en)] }
                    var vf: [String] = []
                    if h > 0 && !fmt.audioOnly { vf.append("scale=-2:'min(\(h),ih)'") }
                    if sp != 1 && !fmt.audioOnly { vf.append("setpts=PTS/\(sp)") }
                    if fmt == .gif {
                        let pre = (vf + ["fps=12", "scale='min(560,iw)':-2:flags=lanczos"]).joined(separator: ",")
                        args += ["-filter_complex", "\(pre),split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4"]
                    } else if !vf.isEmpty {
                        args += ["-vf", vf.joined(separator: ",")]
                    }
                    if m && !fmt.audioOnly { args.append("-an") } else if sp != 1 && fmt != .gif { args += ["-af", "atempo=\(sp)"] }
                    args += fmt.codecArgs
                    out = try await Media.ff(url, ext: fmt.ext, args, suffix: " (edited)")
                } else {
                    let range = CMTimeRange(start: CMTime(seconds: st, preferredTimescale: 600), end: CMTime(seconds: en, preferredTimescale: 600))
                    switch fmt {
                    case .m4a: out = try await Media.av(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a", suffix: " (edited)", range: range)
                    case .hevc: out = try await Media.av(url, preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4, ext: "mp4", suffix: " (edited)", range: range)
                    case .mov: out = try await Media.av(url, preset: AVAssetExportPresetHighestQuality, type: .mov, ext: "mov", suffix: " (edited)", range: range)
                    default: out = try await Media.av(url, preset: AVAssetExportPresetHighestQuality, type: .mp4, ext: "mp4", suffix: " (edited)", range: range)
                    }
                }
                saved = out
                status = "Сохранено: \(out.lastPathComponent)"
                NSSound(named: "Glass")?.play()
            } catch {
                status = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Text editor

struct TextFileEditorView: View {
    let url: URL
    @State private var text = ""
    @State private var original = ""
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.top, 28)
                .padding(8)
            HStack {
                Text(status ?? "\(text.count) символов · \(text.split(separator: "\n", omittingEmptySubsequences: false).count) строк")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Отменить изменения") { text = original }.disabled(text == original)
                Button("Сохранить") { save() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent).disabled(text == original)
            }
            .padding(10)
            .background(.regularMaterial)
        }
        .onAppear {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .windowsCP1251)) ?? ""
            original = text
        }
    }

    func save() {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            original = text
            status = "Сохранено"
        } catch { status = error.localizedDescription }
    }
}
