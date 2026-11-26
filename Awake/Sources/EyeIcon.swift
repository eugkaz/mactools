import AppKit

/// Живой значок-глаз: закрыт — Mac спит; открыт — не спит; зрачок бегает — ИИ работает
@MainActor
final class EyeIcon {
    enum State { case asleep, awake, working, battery }
    weak var button: NSStatusBarButton?
    var state: State = .asleep { didSet { if state != oldValue { transition() } } }
    var lid = false { didSet { if lid != oldValue { render() } } }

    private var open: CGFloat = 0          // 0 закрыт … 1 открыт
    private var target: CGFloat = 0
    private var t: CGFloat = 0
    private var timer: Timer?
    private var pulseAt: Date?
    private var nextBlink = Date().addingTimeInterval(4)
    private var blinkAt: Date?

    init(button: NSStatusBarButton) { self.button = button; render() }

    func pulse() { pulseAt = Date(); kick() }

    private func transition() { target = state == .asleep ? 0 : 1; kick() }

    private var animating: Bool {
        abs(open - target) > 0.01 || state == .working || pulseAt != nil || blinkAt != nil
    }

    private func kick() {
        guard timer == nil else { return }
        // «не спит» без работы — редкие моргания, 10 fps; работа — 24 fps
        let fps: Double = abs(open - target) > 0.01 || pulseAt != nil ? 24 : 8
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(dt: CGFloat(1 / fps)) }
        }
    }

    private func step(dt: CGFloat) {
        t += dt
        open += (target - open) * min(1, dt * 9)
        if state == .working, blinkAt == nil, Date() >= nextBlink {
            blinkAt = Date(); nextBlink = Date().addingTimeInterval(.random(in: 3...7))
        }
        if let b = blinkAt, Date().timeIntervalSince(b) > 0.22 { blinkAt = nil }
        if let p = pulseAt, Date().timeIntervalSince(p) > 0.5 { pulseAt = nil }
        render()
        if !animating { timer?.invalidate(); timer = nil; scheduleBlink() }
        else if timer != nil {
            // перестроить таймер под нужный fps
            let wantFast = abs(open - target) > 0.01 || pulseAt != nil
            if wantFast != (timer!.timeInterval < 0.07) { timer?.invalidate(); timer = nil; kick() }
        }
    }

    private var blinkToken = 0
    /// В покое таймер не крутится — только разовое моргание раз в несколько секунд
    private func scheduleBlink() {
        guard state == .awake else { return }
        blinkToken += 1; let tok = blinkToken
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 4...9)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, tok == self.blinkToken, self.state == .awake, self.timer == nil else { return }
                self.blinkAt = Date(); self.kick()
            }
        }
    }

    private func render() {
        let size = NSSize(width: 20, height: 18)
        var o = open
        if let b = blinkAt { let p = CGFloat(Date().timeIntervalSince(b) / 0.22); o *= abs(1 - 2 * p) }
        let scale: CGFloat = pulseAt.map { 1 + 0.18 * sin(CGFloat(Date().timeIntervalSince($0) / 0.5) * .pi) } ?? 1
        let st = state, tt = t, lid = lid
        let img = NSImage(size: size, flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: r.midX, y: r.midY + (lid ? 1.5 : 0)); ctx.scaleBy(x: scale, y: scale)
            ctx.setStrokeColor(.black); ctx.setFillColor(.black)
            ctx.setLineWidth(1.6); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            let w: CGFloat = 7.5, h: CGFloat = 5.2 * max(o, 0.04)
            // нижнее веко
            ctx.move(to: CGPoint(x: -w, y: 0)); ctx.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: -h * 1.25 - (1 - o) * 4.5))
            if o > 0.08 {
                ctx.addQuadCurve(to: CGPoint(x: -w, y: 0), control: CGPoint(x: 0, y: h * 1.25))
                ctx.strokePath()
                // зрачок
                let px: CGFloat = st == .working ? sin(tt * 3.2) * 2.8 : 0
                ctx.saveGState()
                ctx.move(to: CGPoint(x: -w, y: 0))
                ctx.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: -h * 1.25))
                ctx.addQuadCurve(to: CGPoint(x: -w, y: 0), control: CGPoint(x: 0, y: h * 1.25))
                ctx.clip()
                let pr: CGFloat = 2.6
                ctx.fillEllipse(in: CGRect(x: px - pr, y: -pr, width: pr * 2, height: pr * 2))
                ctx.restoreGState()
            } else {
                ctx.strokePath()
                // ресницы и «z»
                for dx in [-4.5, 0, 4.5] as [CGFloat] {
                    let bx = dx, by: CGFloat = -3.9 + abs(dx) * 0.25
                    ctx.move(to: CGPoint(x: bx, y: by)); ctx.addLine(to: CGPoint(x: bx * 1.2, y: by - 2)); ctx.strokePath()
                }
                ctx.setLineWidth(1.2)
                let zx: CGFloat = 4.5, zy: CGFloat = 3.2, s: CGFloat = 3.2
                ctx.move(to: CGPoint(x: zx, y: zy + s)); ctx.addLine(to: CGPoint(x: zx + s, y: zy + s))
                ctx.addLine(to: CGPoint(x: zx, y: zy)); ctx.addLine(to: CGPoint(x: zx + s, y: zy)); ctx.strokePath()
            }
            if st == .battery {
                ctx.fillEllipse(in: CGRect(x: 6.4, y: 3.4, width: 3, height: 3))
            }
            if lid {  // полоска-«крышка» под глазом: можно закрывать
                ctx.setLineWidth(1.4)
                ctx.move(to: CGPoint(x: -6, y: -7.6)); ctx.addLine(to: CGPoint(x: 6, y: -7.6)); ctx.strokePath()
            }
            return true
        }
        img.isTemplate = true
        button?.image = img
    }
}
