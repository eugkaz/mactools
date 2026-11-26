import AppKit

/// Значок в строке меню: планета с орбитой; в фокусе орбита превращается в кольцо прогресса
@MainActor
final class OrbitIcon {
    weak var button: NSStatusBarButton?
    private var spin: CGFloat = 0.6
    private var anim: Timer?
    var progress: Double? { didSet { render() } }      // nil — не в фокусе
    var resting = false

    init(button: NSStatusBarButton) { self.button = button; render() }

    /// Короткий оборот спутника — отклик на действие
    func pulse() {
        anim?.invalidate()
        let start = Date(), from = spin
        anim = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let p = min(1, Date().timeIntervalSince(start) / 0.6)
                let e = 1 - pow(1 - p, 3)
                self.spin = from + CGFloat(e) * .pi * 2
                self.render()
                if p >= 1 { t.invalidate(); self.anim = nil }
            }
        }
    }

    func render() {
        let prog = progress, sp = spin, rest = resting
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { r in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.translateBy(x: r.midX, y: r.midY)
            c.setStrokeColor(.black); c.setFillColor(.black); c.setLineCap(.round)
            if let p = prog {
                // кольцо прогресса
                c.setLineWidth(1.1); c.setAlpha(0.35)
                c.addEllipse(in: CGRect(x: -7.5, y: -7.5, width: 15, height: 15)); c.strokePath()
                c.setAlpha(1); c.setLineWidth(2.2)
                c.addArc(center: .zero, radius: 7.5, startAngle: .pi / 2, endAngle: .pi / 2 - CGFloat(p) * .pi * 2, clockwise: true)
                c.strokePath()
                if rest {
                    c.setLineWidth(1.6)
                    c.move(to: CGPoint(x: -1.6, y: -2.5)); c.addLine(to: CGPoint(x: -1.6, y: 2.5))
                    c.move(to: CGPoint(x: 1.6, y: -2.5)); c.addLine(to: CGPoint(x: 1.6, y: 2.5)); c.strokePath()
                } else {
                    c.fillEllipse(in: CGRect(x: -3, y: -3, width: 6, height: 6))
                }
            } else {
                // планета
                c.fillEllipse(in: CGRect(x: -3.6, y: -3.6, width: 7.2, height: 7.2))
                // наклонная орбита (задняя часть тоньше)
                c.saveGState(); c.rotate(by: -0.42)
                c.setLineWidth(1.3)
                c.addEllipse(in: CGRect(x: -9, y: -3.6, width: 18, height: 7.2)); c.strokePath()
                // спутник
                let mx = 9 * cos(sp), my = 3.6 * sin(sp)
                c.setBlendMode(.clear); c.fillEllipse(in: CGRect(x: mx - 2.6, y: my - 2.6, width: 5.2, height: 5.2))
                c.setBlendMode(.normal); c.fillEllipse(in: CGRect(x: mx - 1.8, y: my - 1.8, width: 3.6, height: 3.6))
                c.restoreGState()
            }
            return true
        }
        img.isTemplate = true
        button?.image = img
    }
}
