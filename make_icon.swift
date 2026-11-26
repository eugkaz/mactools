import AppKit
// usage: make_icon <shifty|deck|lens> <out.icns> [preview.png]
let a = CommandLine.arguments
let kind = a[1]

func rgb(_ h: UInt32, _ al: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: al)
}
func grad(_ ctx: CGContext, _ colors: [CGColor], _ p0: CGPoint, _ p1: CGPoint, locs: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func radial(_ ctx: CGContext, _ colors: [CGColor], _ c: CGPoint, _ r: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
func star(_ c: CGPoint, _ r: CGFloat, inner: CGFloat = 0.3, rot: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<8 {
        let ang = rot + CGFloat(i) * .pi / 4
        let rr = i % 2 == 0 ? r : r * inner
        let pt = CGPoint(x: c.x + rr * cos(ang), y: c.y + rr * sin(ang))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

/// База: «сквиркл» macOS с градиентом, мягким бликом и внутренней обводкой
func base(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32, accentGlow: UInt32? = nil) -> CGRect {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0.35))
    ctx.addPath(rr(body, 185)); ctx.setFillColor(rgb(bottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rr(body, 185)); ctx.clip()
    grad(ctx, [rgb(top), rgb(bottom)], CGPoint(x: 300, y: 924), CGPoint(x: 724, y: 100))
    if let g = accentGlow { radial(ctx, [rgb(g, 0.55), rgb(g, 0)], CGPoint(x: 760, y: 820), 520) }
    // верхний блик
    grad(ctx, [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)], CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 560))
    ctx.restoreGState()
    ctx.addPath(rr(body.insetBy(dx: 3, dy: 3), 182)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(6); ctx.strokePath()
    return body
}

func drawShifty(_ ctx: CGContext) {
    _ = base(ctx, 0x8B5CFF, 0xFF4F9A, accentGlow: 0xFFC46B)
    // две карточки файлов: старый формат → новый
    func card(_ r: CGRect, angle: CGFloat, fill: CGColor, label: String, labelColor: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle); ctx.translateBy(x: -r.midX, y: -r.midY)
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: rgb(0x3A0B4F, 0.45))
        let fold: CGFloat = 70
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + 36, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 36, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 36), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 36, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 36), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 36))
        p.addQuadCurve(to: CGPoint(x: r.minX + 36, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        ctx.addPath(p); ctx.setFillColor(fill); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle); ctx.translateBy(x: -r.midX, y: -r.midY)
        let f = CGMutablePath()
        f.move(to: CGPoint(x: r.maxX, y: r.maxY - fold)); f.addLine(to: CGPoint(x: r.maxX - fold + 10, y: r.maxY - fold + 10))
        f.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY)); f.closeSubpath()
        ctx.addPath(f); ctx.setFillColor(rgb(0xE6DAFF)); ctx.fillPath()
        // строки-заглушки
        for (i, w) in [CGFloat(0.62), 0.44].enumerated() {
            ctx.addPath(rr(CGRect(x: r.minX + 44, y: r.maxY - 120 - CGFloat(i) * 46, width: (r.width - 88) * w, height: 22), 11))
            ctx.setFillColor(rgb(0xC9B8F2, 0.9)); ctx.fillPath()
        }
        // плашка формата
        let tag = CGRect(x: r.minX + 40, y: r.minY + 44, width: r.width - 80, height: 92)
        ctx.addPath(rr(tag, 30)); ctx.setFillColor(labelColor); ctx.fillPath()
        let font = NSFont.systemFont(ofSize: 62, weight: .heavy)
        let str = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white, .kern: 1])
        let line = CTLineCreateWithAttributedString(str)
        let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: tag.midX - b.width / 2, y: tag.midY - b.height / 2 - b.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
    card(CGRect(x: 205, y: 300, width: 330, height: 420), angle: 0.16, fill: rgb(0xF4EEFF), label: "PNG", labelColor: rgb(0x9B8AC4))
    card(CGRect(x: 470, y: 250, width: 340, height: 440), angle: -0.1, fill: rgb(0xFFFFFF), label: "WEBP", labelColor: rgb(0x7B3CFF))
    // дуга-стрелка превращения
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x4A0E6B, 0.4))
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 330, y: 780))
    arc.addQuadCurve(to: CGPoint(x: 640, y: 770), control: CGPoint(x: 480, y: 900))
    ctx.addPath(arc); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.strokePath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 600, y: 830)); head.addLine(to: CGPoint(x: 668, y: 760)); head.addLine(to: CGPoint(x: 572, y: 742))
    ctx.addPath(head); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.restoreGState()
    // искры
    ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFFE9A8, 0.95))
    ctx.addPath(star(CGPoint(x: 780, y: 760), 92, inner: 0.28)); ctx.setFillColor(rgb(0xFFF6D6)); ctx.fillPath()
    ctx.addPath(star(CGPoint(x: 865, y: 620), 40, inner: 0.3)); ctx.fillPath()
    ctx.addPath(star(CGPoint(x: 205, y: 840), 34, inner: 0.3)); ctx.fillPath()
}

func drawDeck(_ ctx: CGContext) {
    _ = base(ctx, 0x2A2A44, 0x0B0B14, accentGlow: 0x6A5CFF)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.addPath(rr(body, 185)); ctx.clip()
    // раскрытый островок у верхнего края
    let island = CGRect(x: 170, y: 330, width: 684, height: 594 + 20)
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 50, color: rgb(0x6A5CFF, 0.55))
    let p = CGMutablePath()
    p.move(to: CGPoint(x: island.minX, y: island.maxY))
    p.addLine(to: CGPoint(x: island.maxX, y: island.maxY))
    p.addLine(to: CGPoint(x: island.maxX, y: island.minY + 90))
    p.addQuadCurve(to: CGPoint(x: island.maxX - 90, y: island.minY), control: CGPoint(x: island.maxX, y: island.minY))
    p.addLine(to: CGPoint(x: island.minX + 90, y: island.minY))
    p.addQuadCurve(to: CGPoint(x: island.minX, y: island.minY + 90), control: CGPoint(x: island.minX, y: island.minY))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    // вкладки-таблетки
    let pills: [(UInt32, CGFloat)] = [(0x8C73FF, 150), (0x2C2C3A, 74), (0x2C2C3A, 74), (0x2C2C3A, 74)]
    var x: CGFloat = 230
    for (c, w) in pills {
        ctx.addPath(rr(CGRect(x: x, y: 790, width: w, height: 58), 29)); ctx.setFillColor(rgb(c)); ctx.fillPath()
        x += w + 20
    }
    // плитки: музыка, буфер, терминал
    let tiles: [(UInt32, UInt32)] = [(0xFF5C8A, 0xFF9A5C), (0x5CC8FF, 0x5C7BFF), (0x48E5A2, 0x1FA67A)]
    for (i, (c1, c2)) in tiles.enumerated() {
        let r = CGRect(x: 230 + CGFloat(i) * 196, y: 420, width: 172, height: 300)
        ctx.saveGState()
        ctx.addPath(rr(r, 38)); ctx.clip()
        grad(ctx, [rgb(c1), rgb(c2)], CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY))
        ctx.restoreGState()
    }
    // эквалайзер на первой плитке
    for (i, h) in [CGFloat(110), 190, 140, 220].enumerated() {
        ctx.addPath(rr(CGRect(x: 262 + CGFloat(i) * 30, y: 460, width: 18, height: h), 9)); ctx.setFillColor(rgb(0xFFFFFF, 0.92)); ctx.fillPath()
    }
    // «буфер»: строки
    for (i, w) in [CGFloat(110), 80, 120, 70].enumerated() {
        ctx.addPath(rr(CGRect(x: 448, y: 660 - CGFloat(i) * 52, width: w, height: 22), 11)); ctx.setFillColor(rgb(0xFFFFFF, 0.9)); ctx.fillPath()
    }
    // терминал: >_
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let t = CGMutablePath()
    t.move(to: CGPoint(x: 640, y: 640)); t.addLine(to: CGPoint(x: 690, y: 590)); t.addLine(to: CGPoint(x: 640, y: 540))
    ctx.addPath(t); ctx.strokePath()
    ctx.move(to: CGPoint(x: 712, y: 520)); ctx.addLine(to: CGPoint(x: 760, y: 520)); ctx.strokePath()
    // нижняя «полка» с точками
    ctx.addPath(rr(CGRect(x: 230, y: 230, width: 564, height: 70), 35)); ctx.setFillColor(rgb(0xFFFFFF, 0.08)); ctx.fillPath()
    for i in 0..<3 {
        ctx.addEllipse(in: CGRect(x: 470 + CGFloat(i) * 34, y: 254, width: 22, height: 22))
        ctx.setFillColor(rgb(0xFFFFFF, i == 0 ? 0.9 : 0.35)); ctx.fillPath()
    }
}

func drawReel(_ ctx: CGContext) {
    _ = base(ctx, 0xFF5A7A, 0x7B3DFF, accentGlow: 0xFFB0C8)
    // «экран» с рамкой
    let scr = CGRect(x: 200, y: 300, width: 624, height: 420)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x2A0B4F, 0.5))
    ctx.addPath(rr(scr, 46)); ctx.setFillColor(rgb(0x15131F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rr(scr.insetBy(dx: 18, dy: 18), 30)); ctx.clip()
    grad(ctx, [rgb(0x2B2540), rgb(0x1A1726)], CGPoint(x: 0, y: scr.maxY), CGPoint(x: 0, y: scr.minY))
    // окна внутри
    for (i, w) in [CGFloat(260), 200, 230].enumerated() {
        ctx.addPath(rr(CGRect(x: 250, y: 620 - CGFloat(i) * 70, width: w, height: 34), 17)); ctx.setFillColor(rgb(0xFFFFFF, 0.14)); ctx.fillPath()
    }
    ctx.restoreGState()
    // лупа-приближение
    let c = CGPoint(x: 610, y: 470), R: CGFloat = 150
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x1A0533, 0.55))
    ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - R + 16, y: c.y - R + 16, width: (R - 16) * 2, height: (R - 16) * 2)); ctx.clip()
    grad(ctx, [rgb(0xFFE3EC), rgb(0xF1E6FF)], CGPoint(x: 0, y: c.y + R), CGPoint(x: 0, y: c.y - R))
    // крупный курсор в лупе
    let cur = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, -150), (38, -114), (64, -170), (90, -158), (64, -104), (112, -104)]
    for (i, p) in pts.enumerated() { let q = CGPoint(x: c.x - 40 + p.0, y: c.y + 75 + p.1); i == 0 ? cur.move(to: q) : cur.addLine(to: q) }
    cur.closeSubpath()
    ctx.addPath(cur); ctx.setFillColor(rgb(0x111111)); ctx.fillPath()
    ctx.addPath(cur); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(10); ctx.setLineJoin(.round); ctx.strokePath()
    // вспышка клика
    ctx.setStrokeColor(rgb(0xFF5A7A, 0.9)); ctx.setLineWidth(10)
    ctx.addEllipse(in: CGRect(x: c.x - 40 - 46, y: c.y + 75 - 46, width: 92, height: 92)); ctx.strokePath()
    ctx.restoreGState()
    // кнопка записи
    let rc = CGPoint(x: 300, y: 250)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34, color: rgb(0xFF2D55, 0.9))
    ctx.addEllipse(in: CGRect(x: rc.x - 78, y: rc.y - 78, width: 156, height: 156)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: rc.x - 50, y: rc.y - 50, width: 100, height: 100)); ctx.setFillColor(rgb(0xFF2D55)); ctx.fillPath()
}

func drawOrbit(_ ctx: CGContext) {
    _ = base(ctx, 0xFFB547, 0xF2365A, accentGlow: 0xFFE08A)
    let c = CGPoint(x: 512, y: 520)
    // сетка окон 2×2 (одно подсвечено — «прилипло»)
    let tiles: [(CGRect, Bool)] = [
        (CGRect(x: 300, y: 530, width: 200, height: 150), true), (CGRect(x: 524, y: 530, width: 200, height: 150), false),
        (CGRect(x: 300, y: 356, width: 200, height: 150), false), (CGRect(x: 524, y: 356, width: 200, height: 150), false)]
    for (r, hi) in tiles {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x7A0A2E, 0.35))
        ctx.addPath(rr(r, 26)); ctx.setFillColor(rgb(0xFFFFFF, hi ? 1 : 0.55)); ctx.fillPath()
        ctx.restoreGState()
        if hi {
            // строка заголовка с «светофором»
            for (i, col) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                ctx.fillEllipse(in: CGRect(x: r.minX + 22 + CGFloat(i) * 30, y: r.maxY - 36, width: 18, height: 18))
                ctx.setFillColor(rgb(UInt32(col))); ctx.fillEllipse(in: CGRect(x: r.minX + 22 + CGFloat(i) * 30, y: r.maxY - 36, width: 18, height: 18))
            }
            for (i, w) in [CGFloat(140), 100].enumerated() {
                ctx.addPath(rr(CGRect(x: r.minX + 24, y: r.minY + 30 + CGFloat(i) * 32, width: w, height: 16), 8))
                ctx.setFillColor(rgb(0xF2365A, 0.35)); ctx.fillPath()
            }
        }
    }
    // орбита: задняя половина
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: 0.38)
    let orbit = CGRect(x: -380, y: -120, width: 760, height: 240)
    ctx.setLineWidth(22); ctx.setLineCap(.round)
    ctx.saveGState(); ctx.clip(to: CGRect(x: -500, y: 0, width: 1000, height: 300))
    ctx.addEllipse(in: orbit); ctx.setStrokeColor(rgb(0xFFFFFF, 0.45)); ctx.strokePath()
    ctx.restoreGState()
    // передняя половина ярче
    ctx.saveGState(); ctx.clip(to: CGRect(x: -500, y: -300, width: 1000, height: 300))
    ctx.setShadow(offset: .zero, blur: 20, color: rgb(0xFFF3C4, 0.9))
    ctx.addEllipse(in: orbit); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.strokePath()
    ctx.restoreGState()
    // спутник
    let a: CGFloat = -2.35
    let m = CGPoint(x: 380 * cos(a), y: 120 * sin(a))
    ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFFF3C4, 1))
    radial(ctx, [rgb(0xFFFFFF), rgb(0xFFE7A3)], m, 0)
    ctx.addEllipse(in: CGRect(x: m.x - 62, y: m.y - 62, width: 124, height: 124)); ctx.setFillColor(rgb(0xFFF6DC)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addEllipse(in: CGRect(x: m.x - 28, y: m.y + 4, width: 34, height: 34)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(star(CGPoint(x: 790, y: 790), 54, inner: 0.25, rot: .pi / 2)); ctx.setFillColor(rgb(0xFFFFFF, 0.95)); ctx.fillPath()
    ctx.addPath(star(CGPoint(x: 230, y: 250), 30, inner: 0.25, rot: .pi / 2)); ctx.setFillColor(rgb(0xFFFFFF, 0.8)); ctx.fillPath()
}

func drawAwake(_ ctx: CGContext) {
    let body = base(ctx, 0x2A1B6E, 0x0B0B24, accentGlow: 0x7C5CFF)
    // звёзды
    for (x, y, r) in [(250.0, 780.0, 14.0), (330, 700, 8), (760, 800, 10), (700, 720, 6), (820, 640, 7)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.addPath(star(CGPoint(x: x, y: y), r * 2.2, inner: 0.28)); ctx.setFillColor(rgb(0xFFFFFF, 0.85)); ctx.fillPath()
    }
    // ноутбук: основание
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: rgb(0, 0.5))
    let deck = CGMutablePath()
    deck.move(to: CGPoint(x: 170, y: 300)); deck.addLine(to: CGPoint(x: 854, y: 300))
    deck.addLine(to: CGPoint(x: 800, y: 250)); deck.addLine(to: CGPoint(x: 224, y: 250)); deck.closeSubpath()
    ctx.addPath(deck); ctx.setFillColor(rgb(0xC9CFE0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rr(CGRect(x: 170, y: 296, width: 684, height: 18), 9)); ctx.setFillColor(rgb(0xE9ECF5)); ctx.fillPath()
    // свет из щели приоткрытой крышки
    ctx.saveGState()
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: 230, y: 318)); beam.addLine(to: CGPoint(x: 794, y: 318))
    beam.addLine(to: CGPoint(x: 900, y: 520)); beam.addLine(to: CGPoint(x: 124, y: 520)); beam.closeSubpath()
    ctx.addPath(rr(body, 185)); ctx.clip()
    ctx.addPath(beam); ctx.clip()
    grad(ctx, [rgb(0xB9A8FF, 0.75), rgb(0x7C5CFF, 0)], CGPoint(x: 0, y: 318), CGPoint(x: 0, y: 540))
    ctx.restoreGState()
    // крышка почти закрыта
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0, 0.45))
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: 210, y: 322)); lid.addLine(to: CGPoint(x: 814, y: 322))
    lid.addLine(to: CGPoint(x: 780, y: 372)); lid.addLine(to: CGPoint(x: 244, y: 372)); lid.closeSubpath()
    ctx.addPath(lid); ctx.setFillColor(rgb(0xDDE2EE)); ctx.fillPath()
    ctx.restoreGState()
    // ИИ-искра над ноутбуком, с ореолом
    let c = CGPoint(x: 512, y: 610)
    radial(ctx, [rgb(0xA58BFF, 0.9), rgb(0x7C5CFF, 0)], c, 230)
    ctx.setShadow(offset: .zero, blur: 40, color: rgb(0xD6CCFF, 1))
    let sp = CGMutablePath()
    for i in 0..<8 {
        let ang = CGFloat(i) * .pi / 4 + .pi / 2
        let r: CGFloat = i % 2 == 0 ? 170 : 38
        let pt = CGPoint(x: c.x + r * cos(ang), y: c.y + r * sin(ang))
        i == 0 ? sp.move(to: pt) : sp.addLine(to: pt)
    }
    sp.closeSubpath()
    ctx.addPath(sp); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.addPath(star(CGPoint(x: 700, y: 560), 50, inner: 0.25, rot: .pi / 2)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

func drawLens(_ ctx: CGContext) {
    _ = base(ctx, 0x16D9B5, 0x0A5CFF, accentGlow: 0x8CF7FF)
    // бумажный лист с текстом
    let sheet = CGRect(x: 250, y: 220, width: 524, height: 600)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x032A6B, 0.45))
    ctx.addPath(rr(sheet, 56)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    // «Aa»
    let font = NSFont.systemFont(ofSize: 190, weight: .black)
    let str = NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: NSColor(cgColor: rgb(0x0A4FD6))!])
    let line = CTLineCreateWithAttributedString(str)
    ctx.textPosition = CGPoint(x: 312, y: 582)
    CTLineDraw(line, ctx)
    // строки текста
    for (i, w) in [CGFloat(400), 330, 380, 250].enumerated() {
        ctx.addPath(rr(CGRect(x: 312, y: 500 - CGFloat(i) * 62, width: w, height: 30), 15))
        ctx.setFillColor(rgb(0x9DB5DD, i == 1 ? 1 : 0.75)); ctx.fillPath()
    }
    // луч сканирования
    ctx.saveGState()
    ctx.addPath(rr(sheet, 56)); ctx.clip()
    ctx.clip(to: CGRect(x: 0, y: 455, width: 1024, height: 110))
    grad(ctx, [rgb(0x19E3C0, 0.38), rgb(0x19E3C0, 0)], CGPoint(x: 0, y: 455), CGPoint(x: 0, y: 565))
    ctx.restoreGState()
    ctx.setShadow(offset: .zero, blur: 34, color: rgb(0x2BFFE0, 1))
    ctx.addPath(rr(CGRect(x: 196, y: 446, width: 632, height: 18), 9)); ctx.setFillColor(rgb(0xC8FFF6)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // уголки видоискателя
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(40); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let r = CGRect(x: 180, y: 160, width: 664, height: 720), L: CGFloat = 130
    for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: cx, y: cy + dy * L)); ctx.addLine(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx + dx * L, y: cy))
        ctx.strokePath()
    }
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    ctx.setShouldAntialias(true)
    switch kind {
    case "shifty": drawShifty(ctx)
    case "deck": drawDeck(ctx)
    case "awake": drawAwake(ctx)
    case "orbit": drawOrbit(ctx)
    case "reel": drawReel(ctx)
    default: drawLens(ctx)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try! render(px).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent("icon_\(name).png"))
}
if a.count > 3 { try! render(512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3])) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", set.path, "-o", a[2]]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
