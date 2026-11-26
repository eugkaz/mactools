import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, ri = R * 0.45
        for i in 0..<10 {
            let a = CGFloat(-Double.pi / 2 + Double(i) * .pi / 5)
            let rr = i % 2 == 0 ? R : ri
            let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct ArrowShape: Shape {
    var head = true
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.midY
        p.move(to: CGPoint(x: r.minX, y: y))
        p.addLine(to: CGPoint(x: r.maxX, y: y))
        if head {
            let h = max(r.height * 1.2, 18)
            p.move(to: CGPoint(x: r.maxX - h, y: y - h * 0.6))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: r.maxX - h, y: y + h * 0.6))
        }
        return p
    }
}

struct PenShape: Shape {
    let points: [CGPoint]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard let f = points.first else { return p }
        func m(_ q: CGPoint) -> CGPoint { CGPoint(x: r.minX + q.x * r.width, y: r.minY + q.y * r.height) }
        p.move(to: m(f))
        if points.count == 1 { p.addLine(to: m(f)) }
        for i in 1..<max(1, points.count) {
            let a = m(points[i - 1]), b = m(points[i])
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        if let l = points.last { p.addLine(to: m(l)) }
        return p
    }
}

/// Отрисовка одного слоя (используется и на холсте, и при экспорте)
struct LayerView: View {
    let l: Layer
    let doc: PhotoDoc

    var body: some View {
        content
            .frame(width: max(1, l.frame.width), height: max(1, l.frame.height))
            .opacity(l.opacity)
            .rotationEffect(.degrees(l.rotation))
    }

    @ViewBuilder var content: some View {
        switch l.type {
        case .image:
            if let img = doc.rendered(l) {
                Image(nsImage: img).resizable()
                    .clipShape(RoundedRectangle(cornerRadius: l.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: l.corner, style: .continuous).strokeBorder(l.stroke, lineWidth: l.strokeWidth))
                    .shadow(color: .black.opacity(l.imageShadow ? 0.35 : 0), radius: l.imageShadow ? max(l.frame.width, l.frame.height) * 0.03 : 0,
                            y: l.imageShadow ? max(l.frame.width, l.frame.height) * 0.015 : 0)
            }
        case .text: TextLayerView(l: l)
        case .rect:
            RoundedRectangle(cornerRadius: l.corner, style: .continuous).fill(l.fill)
                .overlay(RoundedRectangle(cornerRadius: l.corner, style: .continuous).strokeBorder(l.stroke, lineWidth: l.strokeWidth))
        case .ellipse:
            Ellipse().fill(l.fill).overlay(Ellipse().strokeBorder(l.stroke, lineWidth: l.strokeWidth))
        case .star:
            StarShape().fill(l.fill).overlay(StarShape().stroke(l.stroke, lineWidth: l.strokeWidth))
        case .frame:
            RoundedRectangle(cornerRadius: l.corner, style: .continuous).strokeBorder(l.stroke, lineWidth: max(1, l.strokeWidth))
        case .line, .arrow:
            ArrowShape(head: l.type == .arrow).stroke(l.stroke, style: StrokeStyle(lineWidth: max(1, l.strokeWidth), lineCap: .round, lineJoin: .round))
        case .emoji:
            Text(l.glyph).font(.system(size: l.frame.height * 0.82)).fixedSize()
        case .symbol:
            Image(systemName: l.glyph).resizable().aspectRatio(contentMode: .fit).foregroundStyle(l.color)
        case .pen:
            PenShape(points: l.points).stroke(l.stroke, style: StrokeStyle(lineWidth: l.strokeWidth, lineCap: .round, lineJoin: .round))
        case .blur, .pixelate:
            if let img = doc.redaction(l) {
                Image(nsImage: img).resizable().interpolation(l.type == .pixelate ? .none : .high)
                    .clipShape(RoundedRectangle(cornerRadius: l.corner, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: l.corner).fill(.black.opacity(0.85))
            }
        }
    }
}

struct TextLayerView: View {
    let l: Layer
    var font: Font {
        var f = Font(TextMeasure.nsFont(l) as CTFont)
        if l.italic { f = f.italic() }
        return f
    }
    var base: some View {
        Text(l.text).font(font).kerning(l.letterSpacing).multilineTextAlignment(l.align).fixedSize()
    }
    var body: some View {
        ZStack {
            switch l.textStyle {
            case .plain:
                base.foregroundStyle(l.color)
            case .shadow:
                base.foregroundStyle(l.color).shadow(color: .black.opacity(0.45), radius: l.fontSize * 0.08, y: l.fontSize * 0.04)
            case .outline:
                let w = max(1, l.fontSize * 0.045)
                ForEach(0..<12, id: \.self) { i in
                    let a = CGFloat(Double(i) / 12 * 2 * .pi)
                    base.foregroundStyle(l.accent).offset(x: cos(a) * w, y: sin(a) * w)
                }
                base.foregroundStyle(l.color)
            case .pill:
                base.foregroundStyle(l.color)
                    .padding(.horizontal, l.fontSize * 0.65).padding(.vertical, l.fontSize * 0.3)
                    .background(Capsule().fill(l.accent))
            case .neon:
                base.foregroundStyle(l.color)
                    .shadow(color: l.accent, radius: l.fontSize * 0.08)
                    .shadow(color: l.accent, radius: l.fontSize * 0.25)
                    .shadow(color: l.accent.opacity(0.7), radius: l.fontSize * 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: l.align == .leading ? .leading : (l.align == .trailing ? .trailing : .center))
    }
}

struct BackgroundView: View {
    let bg: Background
    var body: some View {
        switch bg {
        case .color(let c): c
        case .transparent: Color.clear
        case .gradient(let a, let b, let angle):
            let r = angle * .pi / 180
            LinearGradient(colors: [a, b], startPoint: UnitPoint(x: 0.5 - cos(r) / 2, y: 0.5 - sin(r) / 2),
                           endPoint: UnitPoint(x: 0.5 + cos(r) / 2, y: 0.5 + sin(r) / 2))
        }
    }
}

/// Чистый рендер холста (экспорт)
struct CanvasRender: View {
    let doc: PhotoDoc
    var body: some View {
        ZStack(alignment: .topLeading) {
            BackgroundView(bg: doc.background)
            ForEach(doc.layers.filter { !$0.hidden }) { l in
                LayerView(l: l, doc: doc).position(x: l.frame.midX, y: l.frame.midY)
            }
        }
        .frame(width: doc.canvas.width, height: doc.canvas.height)
        .clipped()
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.25)))
                }
            }
        }
    }
}

/// Интерактивный холст
struct EditableCanvas: View {
    @Bindable var doc: PhotoDoc
    @State private var dragStart: CGRect?
    @State private var penPoints: [CGPoint] = []
    @State private var dropTarget = false

    var body: some View {
        let z = doc.zoom
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if case .transparent = doc.background { Checkerboard() }
                BackgroundView(bg: doc.background)
                    .contentShape(Rectangle())
                    .onTapGesture { doc.selection = nil }
                ForEach(doc.layers.filter { !$0.hidden }) { l in
                    LayerView(l: l, doc: doc)
                        .contentShape(Rectangle())
                        .position(x: l.frame.midX, y: l.frame.midY)
                        .gesture(moveGesture(l))
                        .onTapGesture(count: 2) { if l.type == .text { doc.selection = l.id; NotificationCenter.default.post(name: .focusText, object: nil) } }
                        .simultaneousGesture(TapGesture().onEnded { doc.selection = l.id })
                }
                if !penPoints.isEmpty {
                    PenShape(points: penPoints.map { CGPoint(x: $0.x / doc.canvas.width, y: $0.y / doc.canvas.height) })
                        .stroke(doc.penColor, style: StrokeStyle(lineWidth: doc.penWidth, lineCap: .round, lineJoin: .round))
                        .frame(width: doc.canvas.width, height: doc.canvas.height)
                        .allowsHitTesting(false)
                }
                if let sel = doc.selected, doc.tool == .select, !sel.hidden {
                    SelectionOverlay(doc: doc, layer: sel, zoom: z)
                }
                if doc.tool == .pen {
                    Color.clear.contentShape(Rectangle()).gesture(penGesture)
                }
            }
            .frame(width: doc.canvas.width, height: doc.canvas.height)
            .clipped()
            .coordinateSpace(name: "canvas")
            .scaleEffect(z, anchor: .topLeading)
        }
        .frame(width: doc.canvas.width * z, height: doc.canvas.height * z, alignment: .topLeading)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: dropTarget ? 3 : 0))
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers, loc in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { u, _ in
                    if let u { DispatchQueue.main.async { doc.addImage(u, at: CGPoint(x: loc.x / z, y: loc.y / z)) } }
                }
            }
            return true
        }
    }

    func moveGesture(_ l: Layer) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { v in
                guard doc.tool == .select, !l.locked else { return }
                if dragStart == nil { dragStart = l.frame; doc.snapshot(); doc.selection = l.id }
                guard let s = dragStart else { return }
                var f = s.offsetBy(dx: v.translation.width, dy: v.translation.height)
                // примагничивание к центру и краям холста
                let snap = 8 / doc.zoom
                if abs(f.midX - doc.canvas.width / 2) < snap { f.origin.x = doc.canvas.width / 2 - f.width / 2 }
                if abs(f.midY - doc.canvas.height / 2) < snap { f.origin.y = doc.canvas.height / 2 - f.height / 2 }
                if abs(f.minX) < snap { f.origin.x = 0 }
                if abs(f.minY) < snap { f.origin.y = 0 }
                if abs(f.maxX - doc.canvas.width) < snap { f.origin.x = doc.canvas.width - f.width }
                if abs(f.maxY - doc.canvas.height) < snap { f.origin.y = doc.canvas.height - f.height }
                doc.update(l.id) { $0.frame = f }
            }
            .onEnded { _ in dragStart = nil }
    }

    var penGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { v in penPoints.append(v.location) }
            .onEnded { _ in
                defer { penPoints = [] }
                guard !penPoints.isEmpty else { return }
                let pad = doc.penWidth
                let xs = penPoints.map(\.x), ys = penPoints.map(\.y)
                let r = CGRect(x: xs.min()! - pad, y: ys.min()! - pad, width: xs.max()! - xs.min()! + pad * 2, height: ys.max()! - ys.min()! + pad * 2)
                var l = Layer(type: .pen, frame: r)
                l.points = penPoints.map { CGPoint(x: ($0.x - r.minX) / r.width, y: ($0.y - r.minY) / r.height) }
                l.stroke = doc.penColor
                l.strokeWidth = doc.penWidth
                doc.snapshot()
                doc.layers.append(l)
            }
    }
}

extension Notification.Name { static let focusText = Notification.Name("shifty.focusText") }

struct SelectionOverlay: View {
    let doc: PhotoDoc
    let layer: Layer
    let zoom: CGFloat
    @State private var start: Layer?

    var body: some View {
        let f = layer.frame
        let hs = 11 / zoom
        ZStack {
            Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom)
                .frame(width: f.width + 2 / zoom, height: f.height + 2 / zoom)
                .allowsHitTesting(false)
            if !layer.locked {
                ForEach(0..<4, id: \.self) { i in
                    let cx: CGFloat = i % 2 == 0 ? -1 : 1, cy: CGFloat = i < 2 ? -1 : 1
                    Circle().fill(.white).overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom))
                        .frame(width: hs, height: hs)
                        .offset(x: cx * f.width / 2, y: cy * f.height / 2)
                        .gesture(resize(cx, cy))
                }
                // поворот
                Rectangle().fill(Color.accentColor).frame(width: 1.2 / zoom, height: 22 / zoom).offset(y: -f.height / 2 - 11 / zoom)
                    .allowsHitTesting(false)
                Circle().fill(Color.accentColor).overlay(Image(systemName: "arrow.clockwise").font(.system(size: 7 / zoom, weight: .bold)).foregroundStyle(.white))
                    .frame(width: hs * 1.3, height: hs * 1.3)
                    .offset(y: -f.height / 2 - 26 / zoom)
                    .gesture(rotate)
            }
        }
        .rotationEffect(.degrees(layer.rotation))
        .position(x: f.midX, y: f.midY)
    }

    func resize(_ cx: CGFloat, _ cy: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { v in
                if start == nil { start = layer; doc.snapshot() }
                guard let s = start else { return }
                // переводим смещение в систему координат повёрнутого слоя
                let a = CGFloat(-s.rotation * .pi / 180)
                let dx = v.translation.width * cos(a) - v.translation.height * sin(a)
                let dy = v.translation.width * sin(a) + v.translation.height * cos(a)
                var w = max(8, s.frame.width + cx * dx * 2)
                var h = max(8, s.frame.height + cy * dy * 2)
                let keep = s.proportional != NSEvent.modifierFlags.contains(.shift)
                if keep {
                    let k = max(w / s.frame.width, h / s.frame.height)
                    w = s.frame.width * k; h = s.frame.height * k
                }
                doc.update(layer.id) { l in
                    l.frame = CGRect(x: s.frame.midX - w / 2, y: s.frame.midY - h / 2, width: w, height: h)
                    if l.type == .text { l.fontSize = s.fontSize * w / s.frame.width }
                }
            }
            .onEnded { _ in start = nil }
    }

    var rotate: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { v in
                if start == nil { start = layer; doc.snapshot() }
                let c = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
                var deg = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi + 90
                if !NSEvent.modifierFlags.contains(.shift) {   // прилипание к 0/45/90…
                    let r = (deg / 45).rounded() * 45
                    if abs(deg - r) < 4 { deg = r }
                } else { deg = (deg / 15).rounded() * 15 }
                doc.update(layer.id) { $0.rotation = deg }
            }
            .onEnded { _ in start = nil }
    }
}
