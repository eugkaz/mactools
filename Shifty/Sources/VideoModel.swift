import AppKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import Observation

struct Clip: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var sourceDuration: Double
    var trimStart: Double = 0
    var trimEnd: Double
    var speed: Double = 1
    var volume: Double = 1
    var muted = false
    var natural: CGSize = CGSize(width: 1920, height: 1080)
    var transform: CGAffineTransform = .identity
    var hasAudio = true
    var duration: Double { max(0.05, (trimEnd - trimStart) / speed) }
    var oriented: CGSize {
        let r = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }
}

enum TextAnim: String, CaseIterable, Identifiable {
    case none = "Без анимации", fade = "Появление", pop = "Выпрыгивание", slide = "Снизу вверх", typewriter = "Печать"
    var id: String { rawValue }
}

struct TextOverlay: Identifiable, Equatable {
    var id = UUID()
    var text = "Текст"
    var start: Double = 0
    var end: Double = 3
    var pos = CGPoint(x: 0.5, y: 0.8)       // доли кадра, y сверху
    var size: Double = 0.07                 // доля высоты кадра
    var color: Color = .white
    var accent: Color = Color(red: 0.48, green: 0.36, blue: 1)
    var style: TextStyle = .shadow
    var bold = true
    var anim: TextAnim = .pop
}

struct MusicTrack: Equatable {
    var url: URL
    var duration: Double
    var offset: Double = 0
    var volume: Double = 0.8
    var fadeIn = true
    var fadeOut = true
}

enum CanvasAspect: String, CaseIterable, Identifiable {
    case original = "Исходный", vertical = "9:16", wide = "16:9", square = "1:1", portrait = "4:5"
    var id: String { rawValue }
}

enum FitMode: String, CaseIterable, Identifiable {
    case blur = "Вписать + размытый фон", fit = "Вписать (чёрный фон)", fill = "Заполнить (обрезать)"
    var id: String { rawValue }
}

enum VSel: Equatable { case clip(UUID), text(UUID), music }

struct VSnapshot { var clips: [Clip]; var texts: [TextOverlay]; var music: MusicTrack?; var aspect: CanvasAspect; var fit: FitMode
    var preset: Preset; var brightness: Double; var contrast: Double; var saturation: Double; var fade: Bool; var originalVolume: Double }

@Observable
final class VideoProject {
    var clips: [Clip] = []
    var texts: [TextOverlay] = []
    var music: MusicTrack?
    var aspect: CanvasAspect = .original
    var fit: FitMode = .blur
    var preset: Preset = .none
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var fade = false
    var originalVolume: Double = 1

    var selection: VSel?
    var playhead: Double = 0
    var isPlaying = false
    var thumbs: [UUID: [NSImage]] = [:]
    var exporting: Double?
    var status: String?
    let player = AVPlayer()

    @ObservationIgnored private var undoStack: [VSnapshot] = []
    @ObservationIgnored private var redoStack: [VSnapshot] = []
    @ObservationIgnored private var rebuildWork: DispatchWorkItem?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastSignature = ""

    var total: Double { clips.reduce(0) { $0 + $1.duration } }

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            guard let self, self.player.rate != 0 else { return }
            self.playhead = t.seconds
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
            self.isPlaying = false
        }
    }

    // MARK: Undo

    var snap: VSnapshot { VSnapshot(clips: clips, texts: texts, music: music, aspect: aspect, fit: fit, preset: preset, brightness: brightness,
                                    contrast: contrast, saturation: saturation, fade: fade, originalVolume: originalVolume) }
    func restore(_ s: VSnapshot) {
        clips = s.clips; texts = s.texts; music = s.music; aspect = s.aspect; fit = s.fit; preset = s.preset
        brightness = s.brightness; contrast = s.contrast; saturation = s.saturation; fade = s.fade; originalVolume = s.originalVolume
        scheduleRebuild()
    }
    func checkpoint() { undoStack.append(snap); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll() }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() { guard let s = undoStack.popLast() else { return }; redoStack.append(snap); restore(s) }
    func redo() { guard let s = redoStack.popLast() else { return }; undoStack.append(snap); restore(s) }

    // MARK: Медиа

    func addClip(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration).seconds, dur.isFinite, dur > 0,
              let vt = try? await asset.loadTracks(withMediaType: .video).first else { status = "Не удалось открыть \(url.lastPathComponent)"; return }
        let (nat, tr) = (try? await vt.load(.naturalSize, .preferredTransform)) ?? (CGSize(width: 1920, height: 1080), .identity)
        let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        let c = Clip(url: url, sourceDuration: dur, trimEnd: dur, natural: nat, transform: tr, hasAudio: hasAudio)
        checkpoint()
        clips.append(c)
        if selection == nil { selection = .clip(c.id) }
        scheduleRebuild()
        await makeThumbs(c)
    }

    func makeThumbs(_ c: Clip) async {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: c.url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let n = max(2, min(24, Int(c.sourceDuration / 1.5)))
        var imgs: [NSImage] = []
        for i in 0..<n {
            let t = CMTime(seconds: c.sourceDuration * (Double(i) + 0.5) / Double(n), preferredTimescale: 600)
            if let (cg, _) = try? await gen.image(at: t) { imgs.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))) }
        }
        thumbs[c.id] = imgs
    }

    func addMusic(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration).seconds, dur.isFinite, dur > 0 else { status = "Не удалось открыть аудио"; return }
        checkpoint()
        music = MusicTrack(url: url, duration: dur)
        selection = .music
        scheduleRebuild()
    }

    func addText(_ preset: String) {
        checkpoint()
        var t = TextOverlay()
        t.start = playhead
        t.end = min(max(total, playhead + 0.5), playhead + 3)
        switch preset {
        case "title": t.text = "Заголовок"; t.size = 0.1; t.pos = CGPoint(x: 0.5, y: 0.45); t.anim = .pop
        case "sub": t.text = "Субтитры"; t.size = 0.055; t.pos = CGPoint(x: 0.5, y: 0.85); t.style = .pill; t.accent = .black.opacity(0.6); t.anim = .fade
        case "neon": t.text = "НЕОН"; t.size = 0.11; t.style = .neon; t.accent = Color(red: 0.2, green: 0.95, blue: 1); t.pos = CGPoint(x: 0.5, y: 0.4)
        case "type": t.text = "Печатаю текст…"; t.size = 0.06; t.anim = .typewriter; t.style = .shadow
        case "outline": t.text = "ВАУ!"; t.size = 0.13; t.style = .outline; t.accent = .black; t.anim = .pop; t.pos = CGPoint(x: 0.5, y: 0.3)
        default: break
        }
        texts.append(t)
        selection = .text(t.id)
        scheduleRebuild()
    }

    // MARK: Правка

    func clipIndex(at time: Double) -> (Int, Double)? {
        var acc = 0.0
        for (i, c) in clips.enumerated() {
            if time < acc + c.duration - 0.001 { return (i, time - acc) }
            acc += c.duration
        }
        return nil
    }

    func clipStart(_ id: UUID) -> Double {
        var acc = 0.0
        for c in clips { if c.id == id { return acc }; acc += c.duration }
        return acc
    }

    func split() {
        guard let (i, local) = clipIndex(at: playhead), local > 0.1, clips[i].duration - local > 0.1 else { NSSound.beep(); return }
        checkpoint()
        var a = clips[i], b = clips[i]
        let cut = a.trimStart + local * a.speed
        a.trimEnd = cut
        b.id = UUID(); b.trimStart = cut
        clips[i] = a
        clips.insert(b, at: i + 1)
        thumbs[b.id] = thumbs[a.id]
        selection = .clip(b.id)
        scheduleRebuild()
    }

    func deleteSelection() {
        guard let s = selection else { return }
        checkpoint()
        switch s {
        case .clip(let id): clips.removeAll { $0.id == id }
        case .text(let id): texts.removeAll { $0.id == id }
        case .music: music = nil
        }
        selection = nil
        playhead = min(playhead, total)
        scheduleRebuild()
    }

    func duplicateClip() {
        guard case .clip(let id) = selection, let i = clips.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        var c = clips[i]; c.id = UUID()
        clips.insert(c, at: i + 1)
        thumbs[c.id] = thumbs[id]
        selection = .clip(c.id)
        scheduleRebuild()
    }

    func moveClip(_ d: Int) {
        guard case .clip(let id) = selection, let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let j = i + d
        guard clips.indices.contains(j) else { return }
        checkpoint()
        clips.swapAt(i, j)
        scheduleRebuild()
    }

    func updateClip(_ id: UUID, _ f: (inout Clip) -> Void) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        f(&clips[i]); scheduleRebuild()
    }
    func updateText(_ id: UUID, _ f: (inout TextOverlay) -> Void) {
        guard let i = texts.firstIndex(where: { $0.id == id }) else { return }
        f(&texts[i]); scheduleRebuild()
    }

    // MARK: Плеер

    func togglePlay() {
        if isPlaying { player.pause(); isPlaying = false; return }
        if playhead >= total - 0.05 { seek(0) }
        player.play(); isPlaying = true
    }

    func seek(_ t: Double) {
        playhead = max(0, min(t, total))
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func scheduleRebuild() {
        rebuildWork?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.rebuildPreview() } }
        rebuildWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: w)
    }

    @MainActor
    func rebuildPreview() async {
        guard !clips.isEmpty else { player.replaceCurrentItem(with: nil); return }
        guard let built = await VideoComposer.build(self, scale: 0.6) else { return }
        let item = AVPlayerItem(asset: built.0)
        item.videoComposition = built.1
        item.audioMix = built.2
        item.audioTimePitchAlgorithm = .spectral
        let wasPlaying = isPlaying
        player.replaceCurrentItem(with: item)
        await player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.play() }
    }

    var renderSize: CGSize {
        let o = clips.first?.oriented ?? CGSize(width: 1920, height: 1080)
        switch aspect {
        case .original:
            let k = min(1, 1920 / max(o.width, o.height))
            return CGSize(width: (o.width * k / 2).rounded() * 2, height: (o.height * k / 2).rounded() * 2)
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .wide: return CGSize(width: 1920, height: 1080)
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        }
    }

    // MARK: Экспорт

    func export(format: String, height: Int) async {
        guard !clips.isEmpty else { return }
        let base = renderSize
        let k = height > 0 ? min(1, CGFloat(height) / min(base.width, base.height)) : 1
        guard let built = await VideoComposer.build(self, scale: k) else { status = "Ошибка сборки"; return }
        let first = clips[0].url
        let isGIF = format == "gif"
        let ext = format == "mov" ? "mov" : "mp4"
        let out = Files.outputURL(for: first, ext: isGIF ? "gif" : ext, suffix: " (Shifty)")
        let tmp = isGIF ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4") : out
        guard let s = AVAssetExportSession(asset: built.0, presetName: AVAssetExportPresetHighestQuality) else { status = "Экспорт недоступен"; return }
        s.videoComposition = built.1
        s.audioMix = built.2
        s.audioTimePitchAlgorithm = .spectral
        exporting = 0
        let poll = Task { @MainActor in
            while !Task.isCancelled { exporting = Double(s.progress) * (isGIF ? 0.7 : 1); try? await Task.sleep(nanoseconds: 150_000_000) }
        }
        do {
            try await s.export(to: tmp, as: format == "mov" ? .mov : .mp4)
            poll.cancel()
            if isGIF {
                exporting = 0.8
                try await Tools.ffmpeg(["-i", tmp.path, "-filter_complex", Media.gifFilter, "-loop", "0", out.path])
                try? FileManager.default.removeItem(at: tmp)
            }
            exporting = nil
            status = "Сохранено: \(out.lastPathComponent)"
            NSSound(named: "Glass")?.play()
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            poll.cancel()
            exporting = nil
            status = "Ошибка экспорта: \(error.localizedDescription)"
        }
    }
}

// MARK: - Сборка композиции

struct Segment { let start: Double; let duration: Double; let orientation: CGImagePropertyOrientation }

struct TextSprite { let image: CIImage; let overlay: TextOverlay; let center: CGPoint; let chars: Int }

enum VideoComposer {
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.d == -1 { return .down }
        return .up
    }

    @MainActor
    static func renderText(_ t: TextOverlay, size R: CGSize, partial: String? = nil) -> CIImage? {
        var l = Layer(type: .text, frame: .zero)
        l.text = partial ?? t.text
        l.fontSize = R.height * t.size
        l.bold = t.bold
        l.color = t.color
        l.accent = t.accent
        l.textStyle = t.style
        l.fontName = "Helvetica Neue"
        let r = ImageRenderer(content: TextLayerView(l: l).fixedSize().padding(l.fontSize * 0.6))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }

    struct FrameCtx {
        let segments: [Segment]; let sprites: [UUID: [CIImage]]; let texts: [TextOverlay]
        let fit: FitMode; let preset: Preset; let fade: Bool; let br: Double; let ct: Double; let sat: Double
        let R: CGSize; let total: Double
    }

    static func frame(_ source: CIImage, at t: Double, _ fc: FrameCtx) -> CIImage {
        let segments = fc.segments, sprites = fc.sprites, texts = fc.texts, fit = fc.fit, preset = fc.preset
        let fade = fc.fade, br = fc.br, ct = fc.ct, sat = fc.sat, R = fc.R, total = fc.total
        let seg = segments.last { $0.start <= t + 0.0005 } ?? segments[0]
        var img = source.oriented(seg.orientation)
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let w = img.extent.width, h = img.extent.height
        let fitK = min(R.width / w, R.height / h), fillK = max(R.width / w, R.height / h)
        let frame = CGRect(origin: .zero, size: R)
        func place(_ k: CGFloat) -> CIImage {
            img.transformed(by: CGAffineTransform(scaleX: k, y: k))
                .transformed(by: CGAffineTransform(translationX: (R.width - w * k) / 2, y: (R.height - h * k) / 2))
        }
        var out: CIImage
        switch fit {
        case .fill: out = place(fillK)
        case .fit: out = place(fitK).composited(over: CIImage(color: .black).cropped(to: frame))
        case .blur:
            let bg = place(fillK).clampedToExtent().applyingGaussianBlur(sigma: Double(R.height) * 0.03)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.12, kCIInputSaturationKey: 1.1]).cropped(to: frame)
            out = place(fitK).composited(over: bg)
        }
        // цвет
        if br != 0 || ct != 1 || sat != 1 || preset == .vivid {
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: br, kCIInputContrastKey: ct,
                                                                     kCIInputSaturationKey: sat * (preset == .vivid ? 1.35 : 1)])
        }
        if let name = preset.ciName, let f = CIFilter(name: name) { f.setValue(out, forKey: kCIInputImageKey); out = f.outputImage ?? out }
        // текст
        for tx in texts where t >= tx.start && t <= tx.end {
            guard let frames = sprites[tx.id], !frames.isEmpty else { continue }
            let local = t - tx.start, remain = tx.end - t
            var s = frames[0]
            var alpha: CGFloat = 1, k: CGFloat = 1, dy: CGFloat = 0
            switch tx.anim {
            case .none: break
            case .fade: alpha = CGFloat(min(1, local / 0.35, remain / 0.35))
            case .pop:
                let p = min(1, local / 0.28)
                k = CGFloat(0.4 + 0.6 * (1 - pow(1 - p, 3)) + (p < 1 ? sin(p * .pi) * 0.12 : 0))
                alpha = CGFloat(min(1, local / 0.12, remain / 0.25))
            case .slide:
                let p = min(1, local / 0.4)
                dy = -CGFloat(1 - (1 - pow(1 - p, 3))) * R.height * 0.08
                alpha = CGFloat(min(1, local / 0.3, remain / 0.3))
            case .typewriter:
                let dur = max(0.4, min(tx.end - tx.start - 0.3, Double(tx.text.count) * 0.06))
                let i = min(frames.count - 1, Int(Double(frames.count) * local / dur))
                s = frames[i]
            }
            let c = CGPoint(x: tx.pos.x * R.width, y: (1 - tx.pos.y) * R.height + dy)
            var spr = s.transformed(by: CGAffineTransform(scaleX: k, y: k))
            spr = spr.transformed(by: CGAffineTransform(translationX: c.x - spr.extent.midX, y: c.y - spr.extent.midY))
            if alpha < 1 { spr = spr.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, alpha))]) }
            out = spr.composited(over: out)
        }
        // затемнение в начале и конце
        if fade {
            let a = 1 - min(1, t / 0.6, (total - t) / 0.6)
            if a > 0 { out = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: a)).cropped(to: frame).composited(over: out) }
        }
        return out.cropped(to: frame)
    }

    @MainActor
    static func build(_ p: VideoProject, scale: CGFloat) async -> (AVMutableComposition, AVVideoComposition, AVAudioMix)? {
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        var segments: [Segment] = []
        var cursor = CMTime.zero
        let audioParams = AVMutableAudioMixInputParameters(track: aTrack)
        var anyAudio = false
        for c in p.clips {
            let asset = AVURLAsset(url: c.url)
            guard let sv = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = CMTimeRange(start: CMTime(seconds: c.trimStart, preferredTimescale: 600), end: CMTime(seconds: c.trimEnd, preferredTimescale: 600))
            do { try vTrack.insertTimeRange(range, of: sv, at: cursor) } catch { continue }
            if let sa = try? await asset.loadTracks(withMediaType: .audio).first,
               (try? aTrack.insertTimeRange(range, of: sa, at: cursor)) != nil {
                anyAudio = true
            } else {
                aTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: range.duration))
            }
            let scaled = CMTime(seconds: c.duration, preferredTimescale: 600)
            if c.speed != 1 { comp.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: scaled) }
            audioParams.setVolume(c.muted ? 0 : Float(c.volume * p.originalVolume), at: cursor)
            segments.append(Segment(start: cursor.seconds, duration: c.duration, orientation: orientation(c.transform)))
            cursor = cursor + scaled
        }
        guard !segments.isEmpty else { return nil }
        let total = cursor.seconds
        // Пустая звуковая дорожка (клипы без звука, напр. записи экрана) ломает экспорт — убираем её.
        var params: [AVMutableAudioMixInputParameters] = []
        if anyAudio { params.append(audioParams) } else { comp.removeTrack(aTrack) }
        if let m = p.music, let src = try? await AVURLAsset(url: m.url).loadTracks(withMediaType: .audio).first,
           let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let len = min(m.duration - m.offset, total)
            if len > 0, (try? mTrack.insertTimeRange(CMTimeRange(start: CMTime(seconds: m.offset, preferredTimescale: 600), duration: CMTime(seconds: len, preferredTimescale: 600)),
                                            of: src, at: .zero)) != nil {
                let mp = AVMutableAudioMixInputParameters(track: mTrack)
                let v = Float(m.volume)
                if m.fadeIn {
                    mp.setVolumeRamp(fromStartVolume: 0, toEndVolume: v, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: min(1.5, len / 3), preferredTimescale: 600)))
                } else { mp.setVolume(v, at: .zero) }
                if m.fadeOut {
                    let d = min(2.5, len / 3)
                    mp.setVolumeRamp(fromStartVolume: v, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: len - d, preferredTimescale: 600), duration: CMTime(seconds: d, preferredTimescale: 600)))
                }
                params.append(mp)
            } else { comp.removeTrack(mTrack) }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params

        let base = p.renderSize
        let R = CGSize(width: (base.width * scale / 2).rounded() * 2, height: (base.height * scale / 2).rounded() * 2)
        // текстовые спрайты (для «печати» — по кадру на каждые несколько символов)
        var sprites: [UUID: [CIImage]] = [:]
        for t in p.texts {
            if t.anim == .typewriter {
                let chars = Array(t.text)
                let steps = min(chars.count, 40)
                sprites[t.id] = (1...max(1, steps)).compactMap { i in
                    renderText(t, size: R, partial: String(chars.prefix(Int(ceil(Double(chars.count) * Double(i) / Double(steps))))))
                }
            } else if let img = renderText(t, size: R) { sprites[t.id] = [img] }
        }
        let fc = FrameCtx(segments: segments, sprites: sprites, texts: p.texts, fit: p.fit, preset: p.preset, fade: p.fade,
                          br: p.brightness, ct: p.contrast, sat: p.saturation, R: R, total: total)
        let vc = AVMutableVideoComposition(asset: comp, applyingCIFiltersWithHandler: { (req: AVAsynchronousCIImageFilteringRequest) -> Void in
            req.finish(with: VideoComposer.frame(req.sourceImage, at: req.compositionTime.seconds, fc), context: nil)
        })
        vc.renderSize = R
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        return (comp, vc, mix)
    }
}
