import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Круговое меню: появляется центром под курсором, действия — пузыри по кольцам.
final class DropPanel: NSPanel {
    let hosting: NSHostingView<RadialView>

    init(model: ShiftyModel) {
        hosting = NSHostingView(rootView: RadialView(model: model))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    func show(near p: NSPoint) {
        let d = RadialLayout.diameter(for: hosting.rootView.model.actions.count)
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main!
        let f = screen.frame
        let x = min(max(p.x - d / 2, f.minX), f.maxX - d)
        let y = min(max(p.y - d / 2, f.minY), f.maxY - d)
        setFrame(NSRect(x: x, y: y, width: d, height: d), display: true)
        hosting.rootView.model.appearTick += 1
        generation += 1
        alphaValue = 1
        orderFrontRegardless()
    }

    private var generation = 0

    func hide() {
        guard isVisible else { return }
        let g = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; animator().alphaValue = 0 }) { [weak self] in
            guard let self, self.generation == g else { return }   // успели показать снова — не прятать
            self.orderOut(nil)
        }
    }
}

enum RadialLayout {
    static let bubble: CGFloat = 68
    static let innerMax = 8
    static func rings(_ n: Int) -> (inner: Int, outer: Int) { n <= innerMax ? (n, 0) : (innerMax, n - innerMax) }
    static func innerRadius(_ n: Int) -> CGFloat { n <= 6 ? 96 : 108 }
    static let outerRadius: CGFloat = 186
    static func diameter(for n: Int) -> CGFloat {
        let r = rings(n).outer > 0 ? outerRadius : innerRadius(n)
        return (r + bubble / 2 + 18) * 2
    }
    static func point(index i: Int, count n: Int, radius r: CGFloat, center c: CGFloat, offset: Double = 0) -> CGPoint {
        let a = CGFloat((-90.0 + offset + 360.0 / Double(n) * Double(i)) * Double.pi / 180)
        return CGPoint(x: c + r * cos(a), y: c + r * sin(a))
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct RadialView: View {
    @Bindable var model: ShiftyModel
    @State private var appeared = false

    var body: some View {
        let n = model.actions.count
        let d = RadialLayout.diameter(for: n)
        let c = d / 2
        let (inner, outer) = RadialLayout.rings(n)
        ZStack {
            // без подложки: лёгкое свечение и тонкие орбиты, по которым стоят пузыри
            ZStack {
                Circle().fill(RadialGradient(colors: [Accent.shifty.b.opacity(0.22), Accent.shifty.a.opacity(0.08), .clear],
                                             center: .center, startRadius: 40, endRadius: RadialLayout.innerRadius(n) + 40))
                    .frame(width: (RadialLayout.innerRadius(n) + 40) * 2, height: (RadialLayout.innerRadius(n) + 40) * 2)
                Circle().stroke(AngularGradient(colors: [Accent.shifty.a.opacity(0.5), Accent.shifty.b.opacity(0.1), Accent.shifty.a.opacity(0.5)], center: .center),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: RadialLayout.innerRadius(n) * 2, height: RadialLayout.innerRadius(n) * 2)
                if outer > 0 {
                    Circle().stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                        .frame(width: RadialLayout.outerRadius * 2, height: RadialLayout.outerRadius * 2)
                }
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.8), value: appeared)
            .allowsHitTesting(false)

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { i, a in
                let onInner = i < inner
                let idx = onInner ? i : i - inner
                let cnt = onInner ? inner : outer
                let r = onInner ? RadialLayout.innerRadius(n) : RadialLayout.outerRadius
                let p = RadialLayout.point(index: idx, count: cnt, radius: appeared ? r : 20, center: c,
                                           offset: onInner ? 0 : 180.0 / Double(max(cnt, 1)))
                Bubble(action: a, model: model)
                    .position(p)
                    .opacity(model.isBusy ? 0 : (appeared ? 1 : 0))
                    .scaleEffect(model.isBusy ? 0.6 : 1)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72).delay(Double(i) * 0.012), value: appeared)
                    .animation(.easeOut(duration: 0.2), value: model.isBusy)
            }

            CenterHub(model: model)
                .position(x: c, y: c)
                .scaleEffect(appeared ? 1 : 0.4)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: appeared)
        }
        .frame(width: d, height: d)
        .onAppear { if Snapshot.dir != nil { appeared = true } }
        .onChange(of: model.appearTick) { _, _ in
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
    }
}

struct CenterHub: View {
    let model: ShiftyModel
    @State private var spin = false

    var body: some View {
        let big = model.isBusy
        ZStack {
            Circle().fill(RadialGradient(colors: [DS.bg2, DS.bg0], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 110))
            // вращающееся кольцо-градиент
            Circle().strokeBorder(AngularGradient(colors: [Accent.shifty.a, Accent.shifty.b, Accent.shifty.a.opacity(0.1), Accent.shifty.a], center: .center),
                                  lineWidth: isWorking ? 3 : 1.5)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: Accent.shifty.b.opacity(0.6), radius: isWorking ? 10 : 4)
            content.padding(big ? 20 : 14)
        }
        .frame(width: big ? 200 : 122, height: big ? 200 : 122)
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: big)
        .onHover { if $0 { model.cancelHide() } else if case .done = model.phase { model.scheduleHide(2) } }
        .onAppear { withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true } }
        .environment(\.colorScheme, .dark)
    }

    private var isWorking: Bool { if case .working = model.phase { return true }; return false }

    @ViewBuilder var content: some View {
        switch model.phase {
        case .choosing:
            VStack(spacing: 5) {
                if let h = model.hovered {
                    Image(systemName: h.icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(Accent.shifty.gradient)
                        .transition(.scale.combined(with: .opacity))
                    Text(h.title).font(DS.font(13.5, .bold, rounded: true)).foregroundStyle(DS.text)
                    Text(h.subtitle).font(DS.font(10)).foregroundStyle(DS.text2).multilineTextAlignment(.center).lineLimit(2)
                } else {
                    if let u = model.urls.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    }
                    Text(model.title).font(DS.font(10.5, .semibold)).foregroundStyle(DS.text).lineLimit(2).multilineTextAlignment(.center).truncationMode(.middle)
                    Text(model.pinned ? "выбери действие" : "отпусти тут — отмена").font(DS.font(9)).foregroundStyle(DS.text3).multilineTextAlignment(.center)
                }
            }
            .animation(DS.snappy, value: model.hovered?.id)
            .onTapGesture { model.onClose?() }
        case .working(let t):
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.system(size: 30, weight: .semibold)).foregroundStyle(Accent.shifty.gradient)
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(t)…").font(DS.font(13, .semibold, rounded: true)).foregroundStyle(DS.text).multilineTextAlignment(.center)
            }
        case .done(let outs, let msg):
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(Accent.mint.gradient).frame(width: 40, height: 40).shadow(color: Accent.mint.b.opacity(0.6), radius: 10)
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                }
                .transition(.scale)
                Text(msg).font(DS.font(12.5, .semibold, rounded: true)).foregroundStyle(DS.text).multilineTextAlignment(.center)
                if let f = outs.first {
                    Text(outs.count > 1 ? "\(outs.count) файлов" : f.lastPathComponent)
                        .font(DS.font(10)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting(outs); model.onClose?() }
                            .buttonStyle(PillButtonStyle(height: 24))
                        Button("Открыть") { outs.forEach { NSWorkspace.shared.open($0) }; model.onClose?() }
                            .buttonStyle(PillButtonStyle(accent: .shifty, height: 24))
                    }
                }
            }
        case .failed(let m):
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(Accent.warn.gradient).frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                }
                Text(m).font(DS.font(10)).foregroundStyle(DS.text2).multilineTextAlignment(.center).lineLimit(5)
            }
            .onTapGesture { model.onClose?() }
        }
    }
}

struct Bubble: View {
    let action: ShiftAction
    let model: ShiftyModel
    @State private var targeted = false
    @State private var hover = false

    var active: Bool { targeted || hover }

    var body: some View {
        let size = RadialLayout.bubble
        VStack(spacing: 2) {
            Image(systemName: action.icon).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(action.isEdit ? Accent.shifty.gradient : LinearGradient(colors: [DS.text, DS.text2], startPoint: .top, endPoint: .bottom)))
            Text(action.title).font(DS.font(10.5, .bold, rounded: true)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(active ? .white : DS.text)
        }
        .padding(.horizontal, 4)
        .frame(width: size, height: size)
        .background {
            ZStack {
                Circle().fill(LinearGradient(colors: [DS.bg2, DS.bg1], startPoint: .top, endPoint: .bottom))
                Circle().fill(Accent.shifty.gradient).opacity(active ? 1 : 0)
                Circle().fill(LinearGradient(colors: [.white.opacity(active ? 0.35 : 0.08), .clear], startPoint: .top, endPoint: .center))
                Circle().strokeBorder(active ? Color.white.opacity(0.4) : (action.isEdit ? Accent.shifty.a.opacity(0.55) : DS.lineHi), lineWidth: 1)
            }
        }
        .shadow(color: active ? Accent.shifty.b.opacity(0.7) : .black.opacity(0.45), radius: active ? 14 : 6, y: active ? 0 : 3)
        .scaleEffect(active ? 1.18 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: active)
        .contentShape(Circle())
        .onHover { h in hover = h; setHovered(h) }
        .onTapGesture { model.perform(action) }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { targeted }, set: { targeted = $0; setHovered($0) })) { _ in
            model.perform(action)
            return true
        }
    }

    func setHovered(_ on: Bool) {
        if on { model.hovered = action } else if model.hovered?.id == action.id { model.hovered = nil }
    }
}
