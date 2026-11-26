import AppKit

/// Нарисованный вручную анимированный значок для строки меню (template — сам подстраивается под светлую/тёмную тему).
final class StatusIcon {
    enum Kind { case lens, shifty, deck }
    enum State: Equatable { case idle, hover, scanning, playing, open }

    let kind: Kind
    weak var button: NSStatusBarButton?
    var state: State = .idle { didSet { if state != oldValue { kick() } } }
    private var timer: Timer?
    private var t: CGFloat = 0
    private var pulseStart: Date?
    private var hoverAmt: CGFloat = 0
    private var openAmt: CGFloat = 0

    init(button: NSStatusBarButton, kind: Kind) {
        self.button = button
        self.kind = kind
        render()
    }

    func pulse() { pulseStart = Date(); kick() }

    private var needsAnimation: Bool {
        if let p = pulseStart, Date().timeIntervalSince(p) < 0.7 { return true }
        let targetHover: CGFloat = state == .hover ? 1 : 0
        let targetOpen: CGFloat = state == .open ? 1 : 0
        if abs(hoverAmt - targetHover) > 0.01 || abs(openAmt - targetOpen) > 0.01 { return true }
        return state == .scanning   // «играет» рисуется статично — без 30 кадров/с в строке меню
    }

    private func kick() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func step() {
        t += 1.0 / 30
        hoverAmt += ((state == .hover ? 1 : 0) - hoverAmt) * 0.25
        openAmt += ((state == .open ? 1 : 0) - openAmt) * 0.22
        render()
        if !needsAnimation { timer?.invalidate(); timer = nil; pulseStart = nil; render() }
    }

    private var pulseP: CGFloat {
        guard let p = pulseStart else { return 0 }
        let x = CGFloat(Date().timeIntervalSince(p) / 0.7)
        return x >= 1 ? 0 : sin(x * .pi)
    }

    private func render() {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { [self] _ in
            NSColor.black.set()
            switch kind {
            case .lens: drawLens()
            case .shifty: drawShifty()
            case .deck: drawDeck()
            }
            return true
        }
        img.isTemplate = true
        button?.image = img
    }

    // MARK: Lens — рамка видоискателя + строки текста, при работе бежит линия сканирования

    private func drawLens() {
        let inset = 2.2 + hoverAmt * 1.4 - pulseP * 1.4
        let len: CGFloat = 4.6
        let r = NSRect(x: inset, y: inset, width: 18 - 2 * inset, height: 18 - 2 * inset)
        let p = NSBezierPath()
        p.lineWidth = 1.6
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: NSPoint(x: cx, y: cy + dy * len))
            p.line(to: NSPoint(x: cx, y: cy))
            p.line(to: NSPoint(x: cx + dx * len, y: cy))
        }
        p.stroke()
        let scanning = state == .scanning
        let lines: [(CGFloat, CGFloat)] = [(11.6, 8), (9, 6), (6.4, 7.2)]
        for (y, w) in lines {
            let l = NSBezierPath()
            l.lineWidth = 1.4
            l.lineCapStyle = .round
            l.move(to: NSPoint(x: 5.2, y: y))
            l.line(to: NSPoint(x: 5.2 + w, y: y))
            NSColor.black.withAlphaComponent(scanning ? 0.45 : 1).set()
            l.stroke()
        }
        if scanning {
            let y = 9 + 5 * sin(t * 4.2)
            let s = NSBezierPath()
            s.lineWidth = 1.4
            s.lineCapStyle = .round
            s.move(to: NSPoint(x: 3.2, y: y))
            s.line(to: NSPoint(x: 14.8, y: y))
            NSColor.black.set()
            s.stroke()
        }
    }

    // MARK: Shifty — волшебная палочка, звёзды мерцают

    private func star(_ c: NSPoint, _ r: CGFloat, rot: CGFloat = 0) {
        guard r > 0.2 else { return }
        let p = NSBezierPath()
        for i in 0..<8 {
            let a = rot + CGFloat(i) * .pi / 4
            let rr = i % 2 == 0 ? r : r * 0.32
            let pt = NSPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            i == 0 ? p.move(to: pt) : p.line(to: pt)
        }
        p.close()
        p.fill()
    }

    private func drawShifty() {
        let w = NSBezierPath()
        w.lineWidth = 2.2
        w.lineCapStyle = .round
        w.move(to: NSPoint(x: 3, y: 3))
        w.line(to: NSPoint(x: 10.6, y: 10.6))
        w.stroke()
        let busy = state == .scanning
        let p = pulseP
        let tw = { (phase: CGFloat) -> CGFloat in busy ? 0.55 + 0.45 * sin(self.t * 7 + phase) : 1 }
        star(NSPoint(x: 13, y: 13), (3.6 + p * 1.6) * (busy ? 0.85 + 0.15 * sin(t * 5) : 1), rot: busy ? t * 2.5 : 0)
        star(NSPoint(x: 6.2, y: 14.4), 1.9 * tw(1.3) + p * 0.8)
        star(NSPoint(x: 14.6, y: 6.2), 1.7 * tw(2.6) + p * 0.8)
        if busy || p > 0 { star(NSPoint(x: 9.6, y: 16.2), 1.1 * tw(4) + p) }
    }

    // MARK: NotchDeck — экран с островком; музыка — эквалайзер, открыт — островок раскрывается

    private func drawDeck() {
        let screen = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 2.6, width: 14.8, height: 12.6), xRadius: 2.6, yRadius: 2.6)
        screen.lineWidth = 1.3
        screen.stroke()
        let o = openAmt
        let islandW = 7.2 + o * 6.4 + (state == .playing ? 1.6 : 0) * (1 - o)
        let islandH = 3.6 + o * 6.2
        let island = NSRect(x: 9 - islandW / 2, y: 15.2 - islandH, width: islandW, height: islandH)
        let path = NSBezierPath(roundedRect: island, xRadius: min(1.8, islandH / 2), yRadius: min(1.8, islandH / 2))
        path.fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        if state == .playing && o < 0.5 {
            for i in 0..<3 {
                let h = 0.8 + 1.6 * abs(sin(t * 6 + CGFloat(i) * 1.7))
                NSBezierPath(roundedRect: NSRect(x: 7.3 + CGFloat(i) * 1.45, y: island.midY - h / 2, width: 0.9, height: h), xRadius: 0.45, yRadius: 0.45).fill()
            }
        } else if o > 0.5 {
            for i in 0..<3 {
                NSBezierPath(roundedRect: NSRect(x: island.minX + 1.4 + CGFloat(i) * 4, y: island.minY + 1.4, width: 3, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
            }
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        if pulseP > 0 {
            let g = NSBezierPath(roundedRect: island.insetBy(dx: -1.5 * pulseP, dy: -1.5 * pulseP), xRadius: 2.4, yRadius: 2.4)
            g.lineWidth = 0.8
            g.stroke()
        }
    }
}
