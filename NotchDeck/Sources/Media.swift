import AppKit
import SwiftUI
import Observation
import CoreImage

/// «Сейчас играет» для любого источника — Spotify, Музыка, YouTube в браузере, VLC, подкасты…
/// С macOS 15.4 системный MediaRemote отвечает только процессам Apple, поэтому маленькая библиотека
/// (Resources/libnp.dylib) загружается в системный /usr/bin/perl и пересылает события JSON-строками.
/// Работает по уведомлениям системы — без опроса, почти без нагрузки.
@Observable
final class MediaController {
    var source: String?            // название приложения-источника
    var bundleID: String?
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    var duration: Double = 0
    var position: Double = 0
    var artwork: NSImage?
    var artBlur: NSImage?
    @ObservationIgnored var artData: Data?          // исходная обложка — для пульта на iPhone
    @ObservationIgnored var artKey = ""           // заранее размытая обложка для фона (дёшево рисовать)
    var tint: Color = Accent.deck.a // доминирующий цвет обложки — для фона плеера
    var volume: Double = 50

    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var stamp: Double = 0
    @ObservationIgnored private var rate: Double = 0
    @ObservationIgnored private var artID = ""
    @ObservationIgnored private var bridgeElapsed = -1.0
    @ObservationIgnored private var gen = 0          // поколение событий — для отложенных сбросов
    @ObservationIgnored private var bridgeStamp = -1.0
    @ObservationIgnored private var lastTitle = ""
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var proc: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var restarts = 0

    var active = false { didSet { if active && proc == nil { start() }; retime() } }

    /// Панель раскрыта — тикаем позицией чаще (для полосы), свёрнута — раз в секунду (линия на островке)
    var detailed = false { didSet { retime() } }

    private func retime() {
        timer?.invalidate(); timer = nil
        guard active else { return }
        let t = Timer(timeInterval: detailed ? 0.5 : 1, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying || self.detailed else { return }
            self.updatePosition()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var sourceIcon: NSImage? {
        guard let b = bundleID, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return nil }
        return NSWorkspace.shared.icon(forFile: u.path)
    }

    func refresh() {
        if detailed, let v = AppleScript.run("output volume of (get volume settings)")?.int32Value { volume = Double(v) }
        updatePosition()
    }

    private func updatePosition() {
        var p = elapsed
        if isPlaying && rate > 0 && stamp > 0 { p += (Date().timeIntervalSince1970 - stamp) * rate }
        position = duration > 0 ? min(max(0, p), duration) : max(0, p)
    }

    // MARK: мост

    private func start() {
        guard let lib = Bundle.main.url(forResource: "libnp", withExtension: "dylib"),
              let script = Bundle.main.url(forResource: "nowplaying", withExtension: "pl") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, lib.path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.proc = nil; self.input = nil
                self.restarts += 1
                if self.active && self.restarts < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.proc == nil { self.start() } }
                }
            }
        }
        do { try p.run() } catch { return }
        proc = p
        input = inp.fileHandleForWriting
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { apply(obj) }
        }
    }

    private func apply(_ o: [String: Any]) {
        if ProcessInfo.processInfo.environment["ND_DEBUG"] != nil { fputs("apply \(o["title"] ?? "-") \(o["artId"] ?? "-") \((o["art"] as? String)?.count ?? -1) have \(artID) \(artwork != nil)\n", stderr) }
        restarts = 0
        let t = o["title"] as? String ?? ""
        let b = o["bundle"] as? String
        // Нет ни заголовка, ни приложения — ничего не играет
        guard b != nil || !t.isEmpty else {
            // При переключении треков плеер на миг шлёт «пусто» — не мигаем, ждём 2.5 с
            let g = gen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.gen == g else { return }
                self.source = nil; self.bundleID = nil; self.title = ""; self.artist = ""; self.album = ""; self.isPlaying = false
                if self.artwork != nil { Theme.shared.apply(nil) }
                withAnimation(.easeInOut(duration: 0.6)) { self.artwork = nil; self.artBlur = nil }
                self.artID = ""; self.duration = 0; self.elapsed = 0; self.position = 0
                self.artData = nil; self.artKey = ""
                RemoteServer.shared.changed()
            }
            return
        }
        gen += 1
        bundleID = b
        source = o["app"] as? String ?? "Плеер"
        if title != t { title = t }
        artist = o["artist"] as? String ?? ""
        album = o["album"] as? String ?? ""
        let playing = (o["playing"] as? NSNumber)?.boolValue ?? false
        duration = (o["duration"] as? NSNumber)?.doubleValue ?? 0
        let el = (o["elapsed"] as? NSNumber)?.doubleValue ?? 0
        let ts = (o["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        // Браузеры часто не обновляют время после перемотки/паузы — берём его от плеера,
        // только если оно действительно поменялось (или сменился трек), иначе считаем сами.
        let fresh = el != bridgeElapsed || ts != bridgeStamp || t != lastTitle
        bridgeElapsed = el; bridgeStamp = ts; lastTitle = t
        if fresh {
            elapsed = el; stamp = ts
            rate = (o["rate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
        } else if playing != isPlaying {
            updatePosition(); elapsed = position; stamp = Date().timeIntervalSince1970
            rate = playing ? 1 : 0
        }
        isPlaying = playing
        updatePosition()
        defer { RemoteServer.shared.changed() }
        let aid = o["artId"] as? String ?? ""
        if let b64 = o["art"] as? String {
            artID = aid
            // Декод, размытие и цвета — в фоне, чтобы не тормозить; на экран — одной плавной сменой
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let data = Data(base64Encoded: b64), let img = NSImage(data: data), let cg = Self.cg(img) else { return }
                let blurred = Self.blurred(cg), tint = Self.dominant(cg), pal = Theme.palette(cg)
                DispatchQueue.main.async {
                    guard let self, self.artID == aid else { return }      // пока считали, трек уже сменился
                    withAnimation(.easeInOut(duration: 0.55)) { self.artwork = img; self.artBlur = blurred; self.tint = tint }
                    Theme.shared.set(pal)
                    self.artData = data; self.artKey = aid
                    RemoteServer.shared.changed()
                }
            }
        } else if !aid.isEmpty && aid != artID {
            send("art")                         // обложка сменилась, но не пришла — попросить ещё раз
        } else if aid.isEmpty && !artID.isEmpty {
            // Обложка пропала — скорее всего на миг (перемотка, смена трека). Держим старые цвета;
            // сбрасываем, только если её нет дольше 2.5 с.
            let g = gen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.gen == g, !self.artID.isEmpty else { return }
                self.artID = ""; self.artData = nil; self.artKey = ""
                RemoteServer.shared.changed()
                withAnimation(.easeInOut(duration: 0.8)) { self.artwork = nil; self.artBlur = nil; self.tint = Accent.deck.a }
                Theme.shared.apply(nil)
            }
        }
    }

    private func send(_ s: String) {
        try? input?.write(contentsOf: Data((s + "\n").utf8))
    }

    // MARK: управление

    /// Совместимо со старыми вызовами: "playpause", "next track", "previous track"
    func command(_ cmd: String) {
        switch cmd {
        case "playpause":
            updatePosition()
            elapsed = position; stamp = Date().timeIntervalSince1970
            isPlaying.toggle()                 // мгновенный отклик, мост подтвердит
            rate = isPlaying ? 1 : 0
            send("cmd 2")
        case "next track": send("cmd 4")
        case "previous track": send("cmd 5")
        default: break
        }
    }

    func skip(_ s: Double) { seek(max(0, min(duration, position + s))) }

    func seek(_ t: Double) {
        position = t; elapsed = t; stamp = Date().timeIntervalSince1970
        if isPlaying && rate == 0 { rate = 1 }
        send(String(format: "seek %.2f", t))
    }

    func setVolume(_ v: Double) {
        volume = v
        AppleScript.run("set volume output volume \(Int(v))")
    }

    func openSource() {
        guard let b = bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: b).first else { return }
        app.activate()
    }

    static let ci = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])

    /// Обложка → уменьшенный CGImage (все расчёты на 256 px — быстро)
    static func cg(_ img: NSImage) -> CGImage? {
        guard let full = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let k = min(1, 256 / CGFloat(max(full.width, full.height)))
        if k >= 1 { return full }
        let w = Int(CGFloat(full.width) * k), h = Int(CGFloat(full.height) * k)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return full }
        c.interpolationQuality = .medium
        c.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage() ?? full
    }

    static func blurred(_ cg: CGImage) -> NSImage? {
        let small = CIImage(cgImage: cg)
        let k = 160 / max(small.extent.width, small.extent.height)
        let s2 = small.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let out = s2.clampedToExtent().applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4]).cropped(to: s2.extent)
        guard let r = ci.createCGImage(out, from: s2.extent) else { return nil }
        return NSImage(cgImage: r, size: s2.extent.size)
    }

    /// Средний цвет обложки, чуть насыщеннее — как фон у Spotify
    static func dominant(_ cg: CGImage) -> Color {
        let im = CIImage(cgImage: cg)
        guard let out = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: im, kCIInputExtentKey: CIVector(cgRect: im.extent)])?.outputImage
        else { return Accent.deck.a }
        var px = [UInt8](repeating: 0, count: 4)
        ci.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(deviceRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 1.35 + 0.08), brightness: min(0.78, max(0.42, b * 1.1)))
    }

    /// Позиция «прямо сейчас» — для плавной полосы
    func livePosition(_ now: Date) -> Double {
        var p = elapsed
        if isPlaying && rate > 0 && stamp > 0 { p += (now.timeIntervalSince1970 - stamp) * rate }
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }
}

/// Цветовая тема всего островка: берётся из обложки играющего трека, без музыки — фирменная.
@Observable
final class Theme {
    static let shared = Theme()
    // цвета обложки (или фирменные, если обложки нет)
    var ca = Accent.deck.a
    var cb = Accent.deck.b
    var cbg: Color? = nil
    /// Итоговые цвета: по обложке или фиксированная палитра из настроек
    var a: Color { Prefs.shared.fixedAccent?.a ?? ca }          // яркий акцент (кнопки, полосы, вкладка)
    var b: Color { Prefs.shared.fixedAccent?.b ?? cb }
    var bg: Color? { Prefs.shared.fixedAccent == nil ? cbg : nil }   // подложка панели; nil — обычная чёрная
    var accent: Accent { Accent(a: a, b: b) }

    /// nil — вернуть фирменные цвета
    func apply(_ img: NSImage?) { set(nil) }

    func set(_ p: (Color, Color, Color)?) {
        withAnimation(.easeInOut(duration: 0.6)) {
            if let p { ca = p.0; cb = p.1; cbg = p.2 } else { ca = Accent.deck.a; cb = Accent.deck.b; cbg = nil }
        }
    }

    /// Два цвета из разных углов обложки → яркие акценты + приглушённый фон
    static func palette(_ cg: CGImage) -> (Color, Color, Color)? {
        let ci = CIImage(cgImage: cg)
        let ctx = MediaController.ci
        func avg(_ r: CGRect) -> (CGFloat, CGFloat, CGFloat) {
            let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: r)])
            var px = [UInt8](repeating: 0, count: 4)
            if let o = f?.outputImage { ctx.render(o, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil) }
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
            NSColor(deviceRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &v, alpha: &al)
            return (h, s, v)
        }
        let e = ci.extent
        let all = avg(e)
        let c1 = avg(CGRect(x: e.minX, y: e.midY, width: e.width / 2, height: e.height / 2))   // верх-лево
        let c2 = avg(CGRect(x: e.midX, y: e.minY, width: e.width / 2, height: e.height / 2))   // низ-право
        func pop(_ c: (CGFloat, CGFloat, CGFloat)) -> Color {
            c.1 < 0.12 ? Color(white: 0.9) : Color(hue: c.0, saturation: min(0.85, max(0.5, c.1 * 1.3)), brightness: 1)
        }
        let grey = all.1 < 0.12
        var a = pop(c1.1 > 0.12 ? c1 : all), b = pop(c2.1 > 0.12 ? c2 : all)
        if grey { a = Color(white: 0.95); b = Color(white: 0.7) }
        else if abs(c1.0 - c2.0) < 0.04 || c1.1 < 0.12 || c2.1 < 0.12 {    // один оттенок — слегка развести для градиента
            a = pop(all); b = Color(hue: (all.0 + 0.07).truncatingRemainder(dividingBy: 1), saturation: min(0.85, max(0.5, all.1 * 1.3)), brightness: 0.95)
        }
        let bg = grey ? Color(white: 0.32) : Color(hue: all.0, saturation: min(1, all.1 * 1.35 + 0.1), brightness: min(0.6, max(0.35, all.2)))
        return (a, b, bg)
    }
}
