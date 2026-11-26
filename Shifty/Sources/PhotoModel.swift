import AppKit
import SwiftUI
import Observation
import CoreImage
import CoreImage.CIFilterBuiltins

enum LType: String, Codable { case image, text, rect, ellipse, line, arrow, star, frame, emoji, symbol, pen, blur, pixelate }

enum TextStyle: String, CaseIterable, Identifiable {
    case plain = "Обычный", shadow = "Тень", outline = "Обводка", pill = "Плашка", neon = "Неон"
    var id: String { rawValue }
}

struct Layer: Identifiable, Equatable {
    var id = UUID()
    var type: LType
    var frame: CGRect
    var rotation: Double = 0
    var opacity: Double = 1
    var locked = false
    var hidden = false
    // текст
    var text = "Ваш текст"
    var fontName = "Helvetica Neue"
    var fontSize: CGFloat = 72
    var bold = true
    var italic = false
    var color: Color = .white
    var align: TextAlignment = .center
    var textStyle: TextStyle = .shadow
    var accent: Color = Color(red: 0.48, green: 0.36, blue: 1)   // плашка / обводка / неон
    var letterSpacing: CGFloat = 0
    // фигуры
    var fill: Color = Color(red: 0.48, green: 0.36, blue: 1)
    var stroke: Color = .white
    var strokeWidth: CGFloat = 0
    var corner: CGFloat = 0
    // картинка
    var image: NSImage?
    var adjust = EditSettings()
    var imageShadow = false
    // эмодзи / символ
    var glyph = "😀"
    // кисть: точки в долях рамки
    var points: [CGPoint] = []
    // размытие / пиксели
    var amount: Double = 0.5

    var proportional: Bool { [.image, .emoji, .symbol, .text].contains(type) }
    var title: String {
        switch type {
        case .image: return "Изображение"
        case .text: return "Текст: " + text.prefix(16)
        case .rect: return "Прямоугольник"
        case .ellipse: return "Круг"
        case .line: return "Линия"
        case .arrow: return "Стрелка"
        case .star: return "Звезда"
        case .frame: return "Рамка"
        case .emoji: return "Стикер " + glyph
        case .symbol: return "Значок"
        case .pen: return "Рисунок"
        case .blur: return "Размытие"
        case .pixelate: return "Пиксели"
        }
    }
    var icon: String {
        switch type {
        case .image: return "photo"
        case .text: return "textformat"
        case .rect: return "rectangle.fill"
        case .ellipse: return "circle.fill"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .star: return "star.fill"
        case .frame: return "rectangle"
        case .emoji: return "face.smiling"
        case .symbol: return "seal"
        case .pen: return "scribble"
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3.fill"
        }
    }

    static func == (a: Layer, b: Layer) -> Bool {
        a.id == b.id && a.frame == b.frame && a.rotation == b.rotation && a.opacity == b.opacity && a.hidden == b.hidden && a.locked == b.locked
        && a.text == b.text && a.fontName == b.fontName && a.fontSize == b.fontSize && a.bold == b.bold && a.italic == b.italic
        && a.color == b.color && a.align == b.align && a.textStyle == b.textStyle && a.accent == b.accent && a.letterSpacing == b.letterSpacing
        && a.fill == b.fill && a.stroke == b.stroke && a.strokeWidth == b.strokeWidth && a.corner == b.corner
        && a.image === b.image && a.adjust == b.adjust && a.imageShadow == b.imageShadow && a.glyph == b.glyph
        && a.points == b.points && a.amount == b.amount
    }
}

enum Background: Equatable {
    case color(Color)
    case gradient(Color, Color, Double)   // угол в градусах
    case transparent
}

struct SizePreset: Identifiable {
    let id = UUID()
    let name: String
    let size: CGSize
    static let all: [SizePreset] = [
        .init(name: "Instagram — пост", size: CGSize(width: 1080, height: 1080)),
        .init(name: "Instagram — 4:5", size: CGSize(width: 1080, height: 1350)),
        .init(name: "Сторис / Reels / TikTok", size: CGSize(width: 1080, height: 1920)),
        .init(name: "YouTube — превью", size: CGSize(width: 1280, height: 720)),
        .init(name: "X / Twitter — пост", size: CGSize(width: 1600, height: 900)),
        .init(name: "LinkedIn — обложка", size: CGSize(width: 1584, height: 396)),
        .init(name: "Telegram — аватар", size: CGSize(width: 640, height: 640)),
        .init(name: "Презентация 16:9", size: CGSize(width: 1920, height: 1080)),
        .init(name: "A4 (печать)", size: CGSize(width: 2480, height: 3508)),
    ]
}

@Observable
final class PhotoDoc {
    var canvas = CGSize(width: 1080, height: 1080)
    var background: Background = .color(.white)
    var layers: [Layer] = []
    var selection: UUID?
    var zoom: CGFloat = 0.5
    var tool: Tool = .select
    var penColor: Color = Color(red: 1, green: 0.27, blue: 0.4)
    var penWidth: CGFloat = 10
    var sourceURL: URL?
    var status: String?

    @ObservationIgnored private var undoStack: [(CGSize, Background, [Layer])] = []
    @ObservationIgnored private var redoStack: [(CGSize, Background, [Layer])] = []
    @ObservationIgnored var renderCache: [UUID: (EditSettings, NSImage)] = [:]
    @ObservationIgnored var redactCache: [UUID: (CGRect, Double, LType, NSImage)] = [:]

    enum Tool { case select, pen }

    var selected: Layer? {
        get { layers.first { $0.id == selection } }
        set { if let v = newValue, let i = layers.firstIndex(where: { $0.id == v.id }) { layers[i] = v } }
    }

    // MARK: Undo

    func snapshot() {
        undoStack.append((canvas, background, layers))
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append((canvas, background, layers))
        (canvas, background, layers) = s
        if let sel = selection, !layers.contains(where: { $0.id == sel }) { selection = nil }
    }
    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append((canvas, background, layers))
        (canvas, background, layers) = s
    }

    func update(_ id: UUID, snapshot snap: Bool = false, _ f: (inout Layer) -> Void) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        if snap { snapshot() }
        f(&layers[i])
    }

    // MARK: Создание

    func open(_ url: URL) {
        guard let img = NSImage(contentsOf: url), let rep = img.representations.first else { return }
        sourceURL = url
        let px = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let size = px.width > 0 ? px : img.size
        img.size = size
        canvas = size
        background = .color(.white)
        layers = [Layer(type: .image, frame: CGRect(origin: .zero, size: size), image: img)]
        selection = nil
        undoStack.removeAll(); redoStack.removeAll()
    }

    func newBlank(_ size: CGSize) {
        canvas = size
        background = .gradient(Color(red: 0.48, green: 0.36, blue: 1), Color(red: 1, green: 0.36, blue: 0.62), 135)
        layers = []
        sourceURL = nil
    }

    var center: CGPoint { CGPoint(x: canvas.width / 2, y: canvas.height / 2) }
    var unit: CGFloat { min(canvas.width, canvas.height) }

    @discardableResult
    func add(_ l: Layer) -> UUID {
        snapshot()
        layers.append(l)
        selection = l.id
        tool = .select
        return l.id
    }

    func addText(_ preset: String) {
        var l = Layer(type: .text, frame: .zero)
        switch preset {
        case "h1": l.text = "Заголовок"; l.fontSize = unit * 0.11; l.bold = true
        case "h2": l.text = "Подзаголовок"; l.fontSize = unit * 0.06; l.bold = true; l.textStyle = .shadow
        case "body": l.text = "Обычный текст"; l.fontSize = unit * 0.04; l.bold = false; l.textStyle = .plain
        case "pill": l.text = "НОВИНКА"; l.fontSize = unit * 0.05; l.textStyle = .pill; l.letterSpacing = 4
        case "neon": l.text = "Неон"; l.fontSize = unit * 0.1; l.textStyle = .neon; l.color = .white; l.accent = Color(red: 0.2, green: 0.95, blue: 1)
        case "outline": l.text = "ОБВОДКА"; l.fontSize = unit * 0.09; l.textStyle = .outline; l.color = .white; l.accent = .black
        default: break
        }
        l.frame = CGRect(origin: .zero, size: TextMeasure.size(l))
        l.frame.origin = CGPoint(x: center.x - l.frame.width / 2, y: center.y - l.frame.height / 2)
        add(l)
    }

    func addShape(_ t: LType) {
        let s = unit * 0.3
        var l = Layer(type: t, frame: CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s))
        switch t {
        case .line, .arrow:
            l.frame = CGRect(x: center.x - s / 2, y: center.y - s * 0.05, width: s, height: s * 0.1)
            l.stroke = Color(red: 1, green: 0.27, blue: 0.4); l.strokeWidth = max(6, unit * 0.012)
        case .frame:
            l.stroke = Color(red: 1, green: 0.27, blue: 0.4); l.strokeWidth = max(6, unit * 0.01); l.corner = unit * 0.02
            l.frame = CGRect(x: center.x - s * 0.7, y: center.y - s / 2, width: s * 1.4, height: s)
        case .rect: l.corner = unit * 0.03
        case .blur, .pixelate:
            l.frame = CGRect(x: center.x - s * 0.7, y: center.y - s * 0.2, width: s * 1.4, height: s * 0.4)
        default: break
        }
        add(l)
    }

    func addGlyph(_ g: String, symbol: Bool) {
        let s = unit * 0.2
        var l = Layer(type: symbol ? .symbol : .emoji, frame: CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s))
        l.glyph = g
        if symbol { l.color = Color(red: 1, green: 0.27, blue: 0.4) }
        add(l)
    }

    func addImage(_ url: URL, at p: CGPoint? = nil) {
        guard let img = NSImage(contentsOf: url) else { return }
        if let rep = img.representations.first, rep.pixelsWide > 0 { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        let k = min(1, unit * 0.6 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let c = p ?? center
        add(Layer(type: .image, frame: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height), image: img))
    }

    // MARK: Порядок слоёв

    func delete() { guard let id = selection else { return }; snapshot(); layers.removeAll { $0.id == id }; selection = nil }
    func duplicate() {
        guard var l = selected else { return }
        snapshot()
        l.id = UUID(); l.frame = l.frame.offsetBy(dx: 30, dy: 30)
        layers.append(l); selection = l.id
    }
    func move(_ d: Int) {
        guard let id = selection, let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(layers.count - 1, i + d))
        guard i != j else { return }
        snapshot(); layers.swapAt(i, j)
    }
    func toFront() { guard let id = selection, let i = layers.firstIndex(where: { $0.id == id }) else { return }; snapshot(); layers.append(layers.remove(at: i)) }
    func toBack() { guard let id = selection, let i = layers.firstIndex(where: { $0.id == id }) else { return }; snapshot(); layers.insert(layers.remove(at: i), at: 0) }
    func nudge(_ dx: CGFloat, _ dy: CGFloat) { guard let id = selection else { return }; update(id) { $0.frame = $0.frame.offsetBy(dx: dx, dy: dy) } }

    func resizeCanvas(_ size: CGSize) {
        snapshot()
        let k = min(size.width / canvas.width, size.height / canvas.height)
        let dx = (size.width - canvas.width * k) / 2, dy = (size.height - canvas.height * k) / 2
        for i in layers.indices {
            var f = layers[i].frame
            f = CGRect(x: f.minX * k + dx, y: f.minY * k + dy, width: f.width * k, height: f.height * k)
            layers[i].frame = f
            if layers[i].type == .text { layers[i].fontSize *= k }
            if [.line, .arrow, .frame, .rect].contains(layers[i].type) { layers[i].strokeWidth *= k; layers[i].corner *= k }
        }
        canvas = size
    }

    /// «Красивый скриншот»: поля, градиент, скругление и тень у картинки
    func beautify() {
        guard let i = layers.firstIndex(where: { $0.type == .image }) else { return }
        snapshot()
        let img = layers[i].frame.size
        let pad = max(img.width, img.height) * 0.09
        canvas = CGSize(width: img.width + pad * 2, height: img.height + pad * 2)
        layers[i].frame = CGRect(x: pad, y: pad, width: img.width, height: img.height)
        layers[i].corner = max(img.width, img.height) * 0.018
        layers[i].imageShadow = true
        background = .gradient(Color(red: 0.36, green: 0.4, blue: 1), Color(red: 0.95, green: 0.4, blue: 0.75), 135)
    }

    // MARK: Рендер картинок с коррекцией

    func rendered(_ l: Layer) -> NSImage? {
        guard let img = l.image else { return nil }
        if l.adjust == EditSettings() { return img }
        if let c = renderCache[l.id], c.0 == l.adjust { return c.1 }
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        var s = l.adjust; s.scale = 100
        let maxSide = CGFloat(max(cg.width, cg.height))
        var ci = CIImage(cgImage: cg)
        if maxSide > 2400 { let k = 2400 / maxSide; ci = ci.transformed(by: CGAffineTransform(scaleX: k, y: k)) }
        guard let out = ImagePipeline.render(ImagePipeline.apply(ci, s, finalScale: false)) else { return img }
        let r = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
        renderCache[l.id] = (l.adjust, r)
        return r
    }

    /// Размытие/пиксели — берём область из нижележащей картинки
    func redaction(_ l: Layer) -> NSImage? {
        if let c = redactCache[l.id], c.0 == l.frame, c.1 == l.amount, c.2 == l.type { return c.3 }
        guard let idx = layers.firstIndex(where: { $0.id == l.id }),
              let base = layers[..<idx].last(where: { $0.type == .image && $0.frame.intersects(l.frame) }),
              let img = rendered(base), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width) / base.frame.width, sy = CGFloat(cg.height) / base.frame.height
        let r = l.frame.offsetBy(dx: -base.frame.minX, dy: -base.frame.minY)
        let px = CGRect(x: r.minX * sx, y: CGFloat(cg.height) - r.maxY * sy, width: r.width * sx, height: r.height * sy)
        let ci = CIImage(cgImage: cg).clampedToExtent()
        var out: CIImage
        if l.type == .blur {
            let f = CIFilter.gaussianBlur(); f.inputImage = ci; f.radius = Float(4 + l.amount * 60); out = f.outputImage ?? ci
        } else {
            let f = CIFilter.pixellate(); f.inputImage = ci; f.scale = Float(6 + l.amount * 50); f.center = CGPoint(x: px.minX, y: px.minY)
            out = f.outputImage ?? ci
        }
        guard let res = ImagePipeline.ctx.createCGImage(out.cropped(to: px), from: px) else { return nil }
        let ns = NSImage(cgImage: res, size: l.frame.size)
        redactCache[l.id] = (l.frame, l.amount, l.type, ns)
        return ns
    }
}

enum TextMeasure {
    static func nsFont(_ l: Layer) -> NSFont {
        var f = NSFont(name: l.fontName, size: l.fontSize) ?? .systemFont(ofSize: l.fontSize)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if l.bold { traits.insert(.bold) }
        if l.italic { traits.insert(.italic) }
        if !traits.isEmpty, let d = Optional(f.fontDescriptor.withSymbolicTraits(traits)), let nf = NSFont(descriptor: d, size: l.fontSize) { f = nf }
        return f
    }
    static func size(_ l: Layer) -> CGSize {
        let a = NSAttributedString(string: l.text.isEmpty ? " " : l.text, attributes: [.font: nsFont(l), .kern: l.letterSpacing])
        let r = a.boundingRect(with: CGSize(width: 100000, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let pad: CGFloat = l.textStyle == .pill ? l.fontSize * 0.9 : l.fontSize * 0.25
        return CGSize(width: ceil(r.width) + pad * 2, height: ceil(r.height) + (l.textStyle == .pill ? l.fontSize * 0.5 : l.fontSize * 0.1) * 2)
    }
}
