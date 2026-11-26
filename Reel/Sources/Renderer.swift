import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit
import SwiftUI

/// Фоны: градиенты в стиле macOS-обоев
enum Backdrops {
    struct B { let name: String; let a: UInt32; let b: UInt32; let c: UInt32 }
    static let all: [B] = [
        B(name: "Закат", a: 0xFF9A8B, b: 0xFF6A88, c: 0xFF99AC),
        B(name: "Сирень", a: 0x8E7BFF, b: 0xC86DD7, c: 0x3023AE),
        B(name: "Океан", a: 0x2BC0E4, b: 0x1A6DFF, c: 0x0B1F5C),
        B(name: "Мята", a: 0x5CF2B5, b: 0x19A7CE, c: 0x0E5C6B),
        B(name: "Персик", a: 0xFFD3A5, b: 0xFD6585, c: 0xFFB88C),
        B(name: "Ночь", a: 0x2C2F48, b: 0x14151F, c: 0x3B2F63),
        B(name: "Лес", a: 0xA8E063, b: 0x56AB2F, c: 0x1D5C3A),
        B(name: "Графит", a: 0x5A5F6E, b: 0x2B2E36, c: 0x15161B),
        B(name: "Аврора", a: 0x00F5A0, b: 0x00D9F5, c: 0x7A2BFF),
        B(name: "Белый", a: 0xF4F5F8, b: 0xE3E6EE, c: 0xFFFFFF),
    ]
    static func color(_ h: UInt32, _ a: CGFloat = 1) -> CIColor {
        CIColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
    }
    static func swatch(_ i: Int) -> LinearGradient {
        let b = all[i % all.count]
        return LinearGradient(colors: [Color(hex: b.a), Color(hex: b.b), Color(hex: b.c)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func image(_ i: Int, _ r: CGRect) -> CIImage {
        let b = all[i % all.count]
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: r.minX, y: r.maxY); g.point1 = CGPoint(x: r.maxX, y: r.minY)
        g.color0 = color(b.a); g.color1 = color(b.b)
        let rad = CIFilter.radialGradient()
        rad.center = CGPoint(x: r.maxX * 0.85, y: r.minY + r.height * 0.1)
        rad.radius0 = 0; rad.radius1 = Float(r.width * 0.7)
        rad.color0 = color(b.c, 0.85); rad.color1 = color(b.c, 0)
        let glow = CIFilter.radialGradient()
        glow.center = CGPoint(x: r.width * 0.2, y: r.maxY * 0.9)
        glow.radius0 = 0; glow.radius1 = Float(r.width * 0.5)
        glow.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.18); glow.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        return glow.outputImage!.composited(over: rad.outputImage!.composited(over: g.outputImage!)).cropped(to: r)
    }
}

/// Сборка кадра: фон → тень → экран (зум, скругление) → вспышки кликов → курсор
final class Compositor: @unchecked Sendable {
    let meta: RecMeta
    let style: Style
    let track: Track
    let src: CGSize
    let out: CGSize
    let content: CGRect
    private let base: CIImage          // фон + тень
    private let mask: CIImage
    private let cursor: CIImage
    private let cursorTip: CGPoint     // кончик стрелки внутри картинки (снизу-слева)
    private let clicks: [[Double]]

    init(meta: RecMeta, style: Style, segs: [ZoomSeg], src: CGSize) {
        self.meta = meta; self.style = style; self.src = src
        track = Track(meta: meta, segs: segs, style: style)
        let ow = CGFloat(style.outWidth)
        let oh = (ow * src.height / src.width / 2).rounded() * 2
        out = CGSize(width: ow, height: oh)
        // область экрана с полями, сохраняя пропорции
        let pad = ow * style.padding
        let avail = CGRect(origin: .zero, size: out).insetBy(dx: pad, dy: pad * (oh / ow) + pad * 0.3)
        let s = min(avail.width / src.width, avail.height / src.height)
        let w = src.width * s, h = src.height * s
        content = CGRect(x: (ow - w) / 2, y: (oh - h) / 2, width: w, height: h).integral
        let full = CGRect(origin: .zero, size: out)
        let rad = Double(ow) * style.radius

        let rr = CIFilter.roundedRectangleGenerator()
        rr.extent = content; rr.radius = Float(rad); rr.color = .white
        mask = rr.outputImage!

        var b = style.padding > 0.001 ? Backdrops.image(style.bg, full) : CIImage(color: .black).cropped(to: full)
        if style.shadow > 0, style.padding > 0.001 {
            let sh = CIFilter.roundedRectangleGenerator()
            sh.extent = content.offsetBy(dx: 0, dy: -ow * 0.008); sh.radius = Float(rad)
            sh.color = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(0.55 * style.shadow))
            let blurred = sh.outputImage!.applyingGaussianBlur(sigma: Double(ow) * 0.014).cropped(to: full)
            b = blurred.composited(over: b)
        }
        base = b
        (cursor, cursorTip) = Self.makeCursor()
        clicks = meta.clicks
    }

    /// Векторная стрелка как в macOS, белая с чёрной обводкой и тенью
    static func makeCursor() -> (CIImage, CGPoint) {
        let W = 96.0, H = 128.0
        let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
            let p = NSBezierPath()
            let pts: [(Double, Double)] = [(16, 10), (16, 96), (37, 76), (52, 110), (66, 104), (51, 71), (80, 71)]
            p.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
            for q in pts.dropFirst() { p.line(to: NSPoint(x: q.0, y: q.1)) }
            p.close(); p.lineJoinStyle = .round
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.45); sh.shadowBlurRadius = 8; sh.shadowOffset = NSSize(width: 0, height: -3)
            NSGraphicsContext.saveGraphicsState(); sh.set()
            NSColor.white.setFill(); p.fill()
            NSGraphicsContext.restoreGraphicsState()
            p.lineWidth = 9; NSColor.white.setStroke(); p.stroke()
            p.lineWidth = 4.5; NSColor.black.setStroke(); p.stroke()
            NSColor.black.setFill(); p.fill()
            // внутренняя белая окантовка поверх чёрной заливки
            p.lineWidth = 0; return true
        }
        // рендер в CGImage
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
        NSGraphicsContext.restoreGraphicsState()
        let ci = CIImage(cgImage: rep.cgImage!)
        return (ci, CGPoint(x: 16, y: H - 10))   // кончик в координатах CI (снизу-слева)
    }

    func frame(_ srcImage: CIImage, t: Double) -> CIImage {
        let c = track.at(t)
        let z = max(1, c.z)
        let w = src.width, h = src.height
        // видимая часть исходника (координаты CI: начало снизу-слева)
        let vw = w / z, vh = h / z
        var vx = c.cx * w - vw / 2, vy = (1 - c.cy) * h - vh / 2
        vx = min(max(vx, 0), w - vw); vy = min(max(vy, 0), h - vh)
        let k = content.width / vw
        let T = CGAffineTransform(translationX: -vx, y: -vy)
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(translationX: content.minX, y: content.minY))

        let screen = srcImage.transformed(by: T).cropped(to: content)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = screen; blend.backgroundImage = base; blend.maskImage = mask
        var img = blend.outputImage!

        let cursorPt = CGPoint(x: c.px * w, y: (1 - c.py) * h).applying(T)
        let scaleOut = k     // пикселей вывода на пиксель исходника
        // вспышки кликов
        if style.ripple {
            for cl in clicks where t >= cl[0] && t - cl[0] < 0.55 {
                let e = (t - cl[0]) / 0.55
                let ease = 1 - pow(1 - e, 3)
                let p = CGPoint(x: cl[1] * w, y: (1 - cl[2]) * h).applying(T)
                let r = (14 + 46 * ease) * (src.width / 1440) * scaleOut
                // мягкий светящийся круг + тонкое кольцо
                let halo = CIFilter.radialGradient()
                halo.center = p; halo.radius0 = Float(r * 0.35); halo.radius1 = Float(r)
                halo.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.42 * (1 - e)))
                halo.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
                let ringO = CIFilter.radialGradient()
                ringO.center = p; ringO.radius0 = Float(r * 0.92); ringO.radius1 = Float(r * 1.04)
                ringO.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.85 * (1 - e)))
                ringO.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
                let ringI = CIFilter.radialGradient()
                ringI.center = p; ringI.radius0 = Float(r * 0.80); ringI.radius1 = Float(r * 0.92)
                ringI.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
                ringI.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.85 * (1 - e)))
                let box = CGRect(x: p.x - r * 1.1, y: p.y - r * 1.1, width: r * 2.2, height: r * 2.2)
                // кольцо = внутренний градиент (0→1) ∩ внешний (1→0)
                let ringMask = CIFilter.multiplyCompositing()
                ringMask.inputImage = ringI.outputImage!.cropped(to: box); ringMask.backgroundImage = ringO.outputImage!.cropped(to: box)
                let ring = ringMask.outputImage!.composited(over: halo.outputImage!.cropped(to: box))
                img = ring.cropped(to: content).composited(over: img)
            }
        }
        // курсор
        if meta.customCursor, content.insetBy(dx: -4, dy: -4).contains(cursorPt) {
            var press = 1.0
            if let last = clicks.last(where: { $0[0] <= t }), t - last[0] < 0.18 {
                press = 1 - 0.18 * sin((t - last[0]) / 0.18 * .pi)
            }
            // базовый размер: ~22 pt системного курсора × масштаб
            let pt = src.width / 1440        // пикселей исходника на «точку» (для Retina ≈ 2)
            let targetH = 26 * pt * style.cursorSize * scaleOut * press
            let s = targetH / cursor.extent.height
            let cur = cursor.transformed(by: CGAffineTransform(scaleX: s, y: s))
            let tip = CGPoint(x: cursorTip.x * s, y: cursorTip.y * s)
            img = cur.transformed(by: CGAffineTransform(translationX: cursorPt.x - tip.x, y: cursorPt.y - tip.y)).composited(over: img)
        }
        return img.cropped(to: CGRect(origin: .zero, size: out))
    }
}

enum Render {
    static func composition(asset: AVAsset, meta: RecMeta, style: Style, segs: [ZoomSeg]) async throws -> (AVMutableVideoComposition, CGSize) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "Reel", code: 1, userInfo: [NSLocalizedDescriptionKey: "В файле нет видео"]) }
        let size = try await track.load(.naturalSize)
        let comp = Compositor(meta: meta, style: style, segs: segs, src: size)
        let vc = try await AVMutableVideoComposition.videoComposition(with: asset) { req in
            let t = req.compositionTime.seconds
            req.finish(with: comp.frame(req.sourceImage, t: t), context: nil)
        }
        vc.renderSize = comp.out
        vc.frameDuration = CMTime(value: 1, timescale: 60)
        return (vc, comp.out)
    }

    /// Экспорт в MP4 (H.264, совместим везде)
    static func export(_ rec: Recording, meta: RecMeta, style: Style, segs: [ZoomSeg], to url: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: rec.video)
        let (vc, _) = try await composition(asset: asset, meta: meta, style: style, segs: segs)
        guard let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Reel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось начать экспорт"])
        }
        s.videoComposition = vc
        let dur = try await asset.load(.duration).seconds
        let end = min(style.trimEnd ?? dur, dur)
        s.timeRange = CMTimeRange(start: CMTime(seconds: style.trimStart, preferredTimescale: 600),
                                  end: CMTime(seconds: max(end, style.trimStart + 0.1), preferredTimescale: 600))
        try? FileManager.default.removeItem(at: url)
        let poll = Task {
            while !Task.isCancelled {
                for await st in s.states(updateInterval: 0.2) {
                    if case .exporting(let p) = st { progress(p.fractionCompleted) }
                }
                break
            }
        }
        defer { poll.cancel() }
        try await s.export(to: url, as: .mp4)
        progress(1)
    }
}
