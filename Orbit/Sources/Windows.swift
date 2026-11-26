import AppKit
import ApplicationServices

// MARK: - Accessibility

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func string(_ el: AXUIElement, _ name: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? String
    }
    static func bool(_ el: AXUIElement, _ name: String) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return false }
        return (v as? Bool) ?? false
    }
    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let arr = v as? [AnyObject] else { return [] }
        return arr.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let a = AXUIElementCreateApplication(app.processIdentifier)
        return element(a, kAXFocusedWindowAttribute) ?? element(a, kAXMainWindowAttribute)
    }
    /// Рамка окна в координатах AX (начало — левый верхний угол главного экрана)
    static func frame(_ w: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        guard let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) else { return }
        // размер → позиция → размер: иначе окно упирается в край экрана и сжимается неправильно
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
    }
    static func pid(_ el: AXUIElement) -> pid_t { var p: pid_t = 0; AXUIElementGetPid(el, &p); return p }
}

// MARK: - Координаты

enum Geo {
    static var primaryH: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    /// AppKit (снизу-слева) ↔ AX (сверху-слева)
    static func toAX(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height) }
    static func toNS(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height) }
    static func screen(for nsRect: CGRect) -> NSScreen {
        let c = CGPoint(x: nsRect.midX, y: nsRect.midY)
        return NSScreen.screens.first { $0.frame.contains(c) }
            ?? NSScreen.screens.max { $0.frame.intersection(nsRect).width * $0.frame.intersection(nsRect).height
                                     < $1.frame.intersection(nsRect).width * $1.frame.intersection(nsRect).height }
            ?? NSScreen.main!
    }
}

// MARK: - Действия

enum WinAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, almostMaximize, center
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case larger, smaller, nextDisplay, prevDisplay, restore

    var title: String {
        switch self {
        case .leftHalf: "Левая половина"; case .rightHalf: "Правая половина"
        case .topHalf: "Верхняя половина"; case .bottomHalf: "Нижняя половина"
        case .maximize: "На весь экран"; case .almostMaximize: "Почти на весь экран"; case .center: "По центру"
        case .topLeft: "Левый верхний угол"; case .topRight: "Правый верхний угол"
        case .bottomLeft: "Левый нижний угол"; case .bottomRight: "Правый нижний угол"
        case .firstThird: "Левая треть"; case .centerThird: "Центральная треть"; case .lastThird: "Правая треть"
        case .firstTwoThirds: "Левые две трети"; case .lastTwoThirds: "Правые две трети"
        case .larger: "Больше"; case .smaller: "Меньше"
        case .nextDisplay: "На следующий монитор"; case .prevDisplay: "На предыдущий монитор"
        case .restore: "Вернуть как было"
        }
    }
    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"; case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"; case .bottomHalf: "rectangle.bottomhalf.filled"
        case .maximize: "rectangle.fill"; case .almostMaximize: "rectangle.inset.filled"; case .center: "rectangle.center.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"; case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"; case .bottomRight: "rectangle.inset.bottomright.filled"
        case .firstThird, .firstTwoThirds: "rectangle.leftthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .lastThird, .lastTwoThirds: "rectangle.rightthird.inset.filled"
        case .larger: "arrow.up.left.and.arrow.down.right"; case .smaller: "arrow.down.right.and.arrow.up.left"
        case .nextDisplay: "rectangle.on.rectangle.angled"; case .prevDisplay: "rectangle.on.rectangle.angled"
        case .restore: "arrow.uturn.backward"
        }
    }
    /// Сочетание по умолчанию: (код клавиши, модификаторы)
    var hotkey: (Int, UInt32)? {
        let co = Hotkeys.ctrlOpt
        switch self {
        case .leftHalf: return (123, co); case .rightHalf: return (124, co)
        case .topHalf: return (126, co); case .bottomHalf: return (125, co)
        case .maximize: return (36, co); case .center: return (8, co)
        case .topLeft: return (32, co); case .topRight: return (34, co)
        case .bottomLeft: return (38, co); case .bottomRight: return (40, co)
        case .firstThird: return (2, co); case .centerThird: return (3, co); case .lastThird: return (5, co)
        case .firstTwoThirds: return (14, co); case .lastTwoThirds: return (17, co)
        case .larger: return (24, co); case .smaller: return (27, co)
        case .nextDisplay: return (124, Hotkeys.ctrlOptCmd); case .prevDisplay: return (123, Hotkeys.ctrlOptCmd)
        case .restore: return (51, co)
        case .almostMaximize: return nil
        }
    }
    var hotkeyLabel: String { hotkey.map { Hotkeys.label($0.0, $0.1) } ?? "" }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    var gap: CGFloat { CGFloat(UserDefaults.standard.integer(forKey: "gap")) }

    private var saved: [CFHashCode: CGRect] = [:]       // для «вернуть как было»
    private var lastAction: WinAction?
    private var lastTime = Date.distantPast
    private var cycle = 0

    func perform(_ a: WinAction, window: AXUIElement? = nil) {
        guard AX.trusted else { AX.prompt(); return }
        guard let w = window ?? AX.focusedWindow(), let cur = AX.frame(w) else { NSSound.beep(); return }
        let key = CFHash(w)

        if a == .restore {
            if let r = saved[key] { AX.setFrame(w, r); saved[key] = nil } else { NSSound.beep() }
            return
        }
        // повторное нажатие той же клавиши: 1/2 → 2/3 → 1/3
        if a == lastAction, Date().timeIntervalSince(lastTime) < 2 { cycle += 1 } else { cycle = 0 }
        lastAction = a; lastTime = Date()

        let nsCur = Geo.toNS(cur)
        let screen = Geo.screen(for: nsCur)
        guard let target = rect(a, cur: nsCur, screen: screen) else { return }
        if saved[key] == nil { saved[key] = cur }
        AX.setFrame(w, Geo.toAX(target))
    }

    /// Целевая рамка в координатах AppKit
    func rect(_ a: WinAction, cur: CGRect, screen: NSScreen, cycleOverride: Int? = nil) -> CGRect? {
        let g = gap
        let v = screen.visibleFrame.insetBy(dx: g, dy: g)
        let fr: [CGFloat] = [1 / 2, 2 / 3, 1 / 3]
        let f = fr[(cycleOverride ?? cycle) % 3]
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: w, height: h).integral
        }
        let hw = (v.width - g) / 2, hh = (v.height - g) / 2
        switch a {
        case .leftHalf: return r(v.minX, v.minY, v.width * f - g / 2, v.height)
        case .rightHalf: let w = v.width * f - g / 2; return r(v.maxX - w, v.minY, w, v.height)
        case .topHalf: let h = v.height * f - g / 2; return r(v.minX, v.maxY - h, v.width, h)
        case .bottomHalf: return r(v.minX, v.minY, v.width, v.height * f - g / 2)
        case .maximize: return v
        case .almostMaximize: return v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05).integral
        case .center:
            let w = min(cur.width, v.width), h = min(cur.height, v.height)
            return r(v.midX - w / 2, v.midY - h / 2, w, h)
        case .topLeft: return r(v.minX, v.maxY - hh, hw, hh)
        case .topRight: return r(v.maxX - hw, v.maxY - hh, hw, hh)
        case .bottomLeft: return r(v.minX, v.minY, hw, hh)
        case .bottomRight: return r(v.maxX - hw, v.minY, hw, hh)
        case .firstThird: let w = (v.width - 2 * g) / 3; return r(v.minX, v.minY, w, v.height)
        case .centerThird: let w = (v.width - 2 * g) / 3; return r(v.minX + w + g, v.minY, w, v.height)
        case .lastThird: let w = (v.width - 2 * g) / 3; return r(v.maxX - w, v.minY, w, v.height)
        case .firstTwoThirds: let w = (v.width - g) * 2 / 3; return r(v.minX, v.minY, w, v.height)
        case .lastTwoThirds: let w = (v.width - g) * 2 / 3; return r(v.maxX - w, v.minY, w, v.height)
        case .larger, .smaller:
            let d: CGFloat = a == .larger ? -30 : 30
            var n = cur.insetBy(dx: d, dy: d).intersection(v)
            if n.width < 300 || n.height < 200 { n = cur }
            return n.integral
        case .nextDisplay, .prevDisplay:
            let all = NSScreen.screens
            guard all.count > 1, let i = all.firstIndex(of: screen) else { NSSound.beep(); return nil }
            let to = all[(i + (a == .nextDisplay ? 1 : all.count - 1)) % all.count]
            let s = screen.visibleFrame, t = to.visibleFrame
            let rx = (cur.minX - s.minX) / s.width, ry = (cur.minY - s.minY) / s.height
            let w = min(cur.width, t.width), h = min(cur.height, t.height)
            return r(t.minX + rx * t.width, t.minY + ry * t.height, w, h).intersection(t)
        case .restore: return nil
        }
    }
}

// MARK: - Прилипание при перетаскивании к краям

@MainActor
final class SnapController {
    static let shared = SnapController()
    var enabled = UserDefaults.standard.object(forKey: "snap") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "snap"); enabled ? start() : stop() }
    }
    private var monitors: [Any] = []
    private var downPoint: CGPoint?
    private var window: AXUIElement?
    private var startPos: CGPoint?
    private var dragging = false
    private var lookedUp = false
    private var zone: WinAction?
    private var lastCheck = Date.distantPast
    private let preview = SnapPreview()

    func start() {
        guard monitors.isEmpty, enabled else { return }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.down() }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.drag() }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.up() }
        } as Any)
    }
    func stop() { monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll(); reset() }

    private func reset() { downPoint = nil; window = nil; startPos = nil; dragging = false; lookedUp = false; zone = nil; preview.hide() }

    private func down() { reset(); downPoint = NSEvent.mouseLocation }

    private func drag() {
        guard let dp = downPoint, AX.trusted else { return }
        if !lookedUp {
            lookedUp = true
            // окно под точкой нажатия (координаты AX)
            let sys = AXUIElementCreateSystemWide()
            var el: AXUIElement?
            let p = CGPoint(x: dp.x, y: Geo.primaryH - dp.y)
            guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &el) == .success, let el else { return }
            if AX.pid(el) == getpid() { return }
            var w: AXUIElement? = (AX.string(el, kAXRoleAttribute) == kAXWindowRole) ? el : AX.element(el, kAXWindowAttribute)
            if w == nil { w = AX.element(el, kAXTopLevelUIElementAttribute) }
            guard let w, AX.string(w, kAXRoleAttribute) == kAXWindowRole,
                  AX.string(w, kAXSubroleAttribute) == kAXStandardWindowSubrole else { return }
            window = w; startPos = AX.frame(w)?.origin
            return
        }
        guard let w = window, let sp = startPos else { return }
        if !dragging {
            guard Date().timeIntervalSince(lastCheck) > 0.05 else { return }
            lastCheck = Date()
            // окно реально двигается — значит тащат за заголовок
            guard let f = AX.frame(w), hypot(f.minX - sp.x, f.minY - sp.y) > 2 else { return }
            dragging = true
        }
        let m = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) else { return }
        let z = zoneFor(m, screen.frame)
        if z != zone {
            zone = z
            if let z, let cur = AX.frame(w),
               let r = WindowManager.shared.rect(z, cur: Geo.toNS(cur), screen: screen, cycleOverride: 0) {
                preview.show(r)
            } else { preview.hide() }
        }
    }

    private func up() {
        defer { reset() }
        guard dragging, let z = zone, let w = window else { return }
        // даём системе закончить перетаскивание, потом ставим рамку
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { WindowManager.shared.perform(z, window: w) }
        }
    }

    private func zoneFor(_ m: CGPoint, _ f: CGRect) -> WinAction? {
        let e: CGFloat = 3, c: CGFloat = 50
        let left = m.x <= f.minX + e, right = m.x >= f.maxX - e - 1
        let top = m.y >= f.maxY - e - 1, bottom = m.y <= f.minY + e
        let nearL = m.x <= f.minX + c, nearR = m.x >= f.maxX - c
        let nearT = m.y >= f.maxY - c, nearB = m.y <= f.minY + c
        if (left && nearT) || (top && nearL) { return .topLeft }
        if (right && nearT) || (top && nearR) { return .topRight }
        if (left && nearB) || (bottom && nearL) { return .bottomLeft }
        if (right && nearB) || (bottom && nearR) { return .bottomRight }
        if top { return .maximize }
        if left { return .leftHalf }
        if right { return .rightHalf }
        return nil
    }
}

/// Полупрозрачная подсказка, куда встанет окно
@MainActor
final class SnapPreview {
    private var panel: NSPanel?
    func show(_ r: CGRect) {
        if panel == nil {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .floating; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let v = NSVisualEffectView(); v.material = .hudWindow; v.state = .active; v.blendingMode = .behindWindow
            v.wantsLayer = true; v.layer?.cornerRadius = 14; v.layer?.masksToBounds = true
            v.layer?.borderWidth = 2; v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
            let tint = NSView(); tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            tint.autoresizingMask = [.width, .height]; tint.frame = v.bounds
            v.addSubview(tint)
            p.contentView = v
            panel = p
        }
        guard let p = panel else { return }
        let inset = r.insetBy(dx: 6, dy: 6)
        if !p.isVisible {
            p.setFrame(inset.insetBy(dx: inset.width * 0.1, dy: inset.height * 0.1), display: false)
            p.alphaValue = 0; p.orderFront(nil)
        }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.16; c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(inset, display: true); p.animator().alphaValue = 1
        }
    }
    func hide() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.12; p.animator().alphaValue = 0 },
                                            completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
    }
}

// MARK: - Рабочие наборы окон

struct LayoutItem: Codable { var bundle: String; var frames: [CGRect] }
struct WinLayout: Codable, Identifiable { var id = UUID(); var name: String; var items: [LayoutItem] }

@MainActor
enum Layouts {
    static var all: [WinLayout] {
        get { (UserDefaults.standard.data(forKey: "layouts").flatMap { try? JSONDecoder().decode([WinLayout].self, from: $0) }) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "layouts") }
    }

    static func saveCurrent(name: String) {
        guard AX.trusted else { AX.prompt(); return }
        var items: [LayoutItem] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            guard let b = app.bundleIdentifier, b != Bundle.main.bundleIdentifier else { continue }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            let frames = AX.windows(ax).filter { !AX.bool($0, kAXMinimizedAttribute) && AX.string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
                .compactMap(AX.frame)
            if !frames.isEmpty { items.append(LayoutItem(bundle: b, frames: frames)) }
        }
        var list = all.filter { $0.name != name }
        list.append(WinLayout(name: name, items: items))
        all = list
    }

    static func apply(_ l: WinLayout) {
        guard AX.trusted else { AX.prompt(); return }
        for it in l.items {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: it.bundle).first {
                place(app, it.frames)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: it.bundle) {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, _ in
                    guard let app else { return }
                    let pid = app.processIdentifier
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        MainActor.assumeIsolated {
                            if let a = NSRunningApplication(processIdentifier: pid) { place(a, it.frames) }
                        }
                    }
                }
            }
        }
    }
    private static func place(_ app: NSRunningApplication, _ frames: [CGRect]) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        let ws = AX.windows(ax).filter { AX.string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
        for (w, f) in zip(ws, frames) { AX.setFrame(w, f) }
    }
    static func delete(_ l: WinLayout) { all = all.filter { $0.id != l.id } }
}
