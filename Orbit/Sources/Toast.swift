import AppKit
import SwiftUI

/// Плашка сверху экрана, исчезает сама
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var token = 0

    static func show(_ text: String) {
        let host = NSHostingView(rootView: ToastView(text: text).environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let p = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.ignoresMouseEvents = true
            p.hasShadow = true; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p; return p
        }()
        p.contentView = host
        let s = NSScreen.main ?? NSScreen.screens[0]
        let f = CGRect(x: s.frame.midX - size.width / 2, y: s.visibleFrame.maxY - size.height - 12, width: size.width, height: size.height)
        p.setFrame(f.offsetBy(dx: 0, dy: 10), display: true)
        p.alphaValue = 0; p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.22; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.3, 0.4, 1)
            p.animator().alphaValue = 1; p.animator().setFrame(f, display: true)
        }
        token += 1; let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                guard t == token else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                                    completionHandler: { MainActor.assumeIsolated { if t == token { p.orderOut(nil) } } })
            }
        }
    }
}

struct ToastView: View {
    var text: String
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Accent.orbit.gradient).frame(width: 8, height: 8).shadow(color: Accent.orbit.b, radius: 4)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.text)
        }
        .padding(.leading, 14).padding(.trailing, 16).frame(height: 38)
        .background(Capsule().fill(DS.bg1.opacity(0.96)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
        .padding(10)   // место под тень
        .fixedSize()
    }
}
