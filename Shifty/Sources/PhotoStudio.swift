import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum StudioTab: String, CaseIterable, Identifiable {
    case design = "Дизайн", text = "Текст", elements = "Элементы", stickers = "Стикеры", draw = "Кисть", hide = "Скрыть", background = "Фон", adjust = "Фото", layers = "Слои"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .design: return "rectangle.on.rectangle"
        case .text: return "textformat"
        case .elements: return "square.on.circle"
        case .stickers: return "face.smiling"
        case .draw: return "paintbrush.pointed"
        case .hide: return "eye.slash"
        case .background: return "paintpalette"
        case .adjust: return "camera.filters"
        case .layers: return "square.3.layers.3d"
        }
    }
}

struct PhotoStudioView: View {
    @State var doc = PhotoDoc()
    @State private var tab: StudioTab = .design
    @State private var exportFormat: OutFormat = .png
    @State private var quality = 0.9
    let url: URL?

    init(url: URL?) {
        self.url = url
    }

    var body: some View {
        HStack(spacing: 0) {
            sideRail
            ScrollView { panel.padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                .scrollIndicators(.never)
                .frame(width: 272)
                .background(DS.bg1)
                .overlay(alignment: .trailing) { Rectangle().fill(DS.line).frame(width: 1) }
            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        EditableCanvas(doc: doc)
                            .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
                            .padding(48)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                    .background(StudioBackdrop(accent: .shifty))
                    .onAppear { fitZoom(geo.size) }
                    .onChange(of: doc.canvas) { _, _ in fitZoom(geo.size) }
                }
            }
            InspectorView(doc: doc).frame(width: 264).background(DS.bg1)
                .overlay(alignment: .leading) { Rectangle().fill(DS.line).frame(width: 1) }
        }
        .background(DS.bg0)
        .environment(\.colorScheme, .dark)
        .tint(Accent.shifty.b)
        .onAppear {
            if let url { doc.open(url) } else { doc.newBlank(CGSize(width: 1080, height: 1080)) }
            exportFormat = url.map(OutFormat.guess) ?? .png
        }
        .background(KeyCatcher(doc: doc))
    }

    func fitZoom(_ s: CGSize) {
        doc.zoom = max(0.05, min(1.5, min((s.width - 80) / doc.canvas.width, (s.height - 80) / doc.canvas.height)))
    }

    var sideRail: some View {
        StudioRail(items: StudioTab.allCases.map { ($0, $0.rawValue, $0.icon) }, selection: $tab, accent: .shifty)
    }

    var topBar: some View {
        HStack(spacing: 8) {
            CircleIconButton(symbol: "arrow.uturn.backward", size: 28) { doc.undo() }.disabled(!doc.canUndo).opacity(doc.canUndo ? 1 : 0.4).help("Отменить ⌘Z")
            CircleIconButton(symbol: "arrow.uturn.forward", size: 28) { doc.redo() }.disabled(!doc.canRedo).opacity(doc.canRedo ? 1 : 0.4).help("Повторить ⇧⌘Z")
            Text("\(Int(doc.canvas.width)) × \(Int(doc.canvas.height))").font(DS.font(11, .semibold, rounded: true)).foregroundStyle(DS.text2)
                .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(DS.fill).overlay(Capsule().strokeBorder(DS.line)))
            if let st = doc.status, !st.isEmpty {
                Text(st).font(DS.font(11)).foregroundStyle(Accent.shifty.a).lineLimit(1).transition(.opacity)
            }
            Spacer()
            ZoomControl(zoom: $doc.zoom)
            Menu {
                ForEach(OutFormat.allCases.filter { Imaging.canWrite($0.uti) }) { f in Button(f.rawValue) { exportFormat = f } }
            } label: {
                HStack(spacing: 4) { Text(exportFormat.rawValue).font(DS.font(11.5, .semibold, rounded: true)); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                    .foregroundStyle(DS.text).padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(DS.fill).overlay(Capsule().strokeBorder(DS.line)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button { copyToClipboard() } label: { Label("Копировать", systemImage: "doc.on.doc") }.buttonStyle(PillButtonStyle())
            Button { export() } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
                .buttonStyle(PillButtonStyle(accent: .shifty))
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 10)
        .background(DS.bg0)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: 1) }
    }

    // MARK: Панели слева

    @ViewBuilder var panel: some View {
        switch tab {
        case .design: designPanel
        case .text: textPanel
        case .elements: elementsPanel
        case .stickers: stickersPanel
        case .draw: drawPanel
        case .hide: hidePanel
        case .background: backgroundPanel
        case .adjust: AdjustPanel(doc: doc)
        case .layers: LayersPanel(doc: doc)
        }
    }

    func header(_ s: String) -> some View {
        SectionLabel(text: s).padding(.top, 8)
    }

    var designPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Быстро")
            Button { doc.beautify() } label: {
                Label("Красивый скриншот", systemImage: "sparkles").frame(maxWidth: .infinity)
            }.buttonStyle(PillButtonStyle(accent: .shifty, height: 38)).disabled(!doc.layers.contains { $0.type == .image })
            Text("Поля, градиент, скругление и тень — для постов и документации").font(.system(size: 10)).foregroundStyle(.secondary)
            header("Размер холста")
            if let first = doc.layers.first(where: { $0.type == .image }), let img = first.image {
                sizeButton("По фото", CGSize(width: img.size.width, height: img.size.height))
            }
            ForEach(SizePreset.all) { p in sizeButton(p.name, p.size) }
            header("Добавить")
            Button { addImageFromPanel() } label: { Label("Изображение…", systemImage: "photo.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(height: 34))
            Text("Или перетащите картинки прямо на холст").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    func sizeButton(_ name: String, _ s: CGSize) -> some View {
        Button { doc.resizeCanvas(s) } label: {
            HStack {
                RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, lineWidth: 1.2)
                    .frame(width: 18 * min(1, s.width / s.height), height: 18 * min(1, s.height / s.width)).frame(width: 20)
                Text(name).font(.system(size: 12))
                Spacer()
                Text("\(Int(s.width))×\(Int(s.height))").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.vertical, 5).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(doc.canvas == s ? Accent.shifty.b.opacity(0.18) : DS.fill)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(doc.canvas == s ? Accent.shifty.a.opacity(0.5) : DS.line)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var textPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Добавить текст")
            presetButton("Заголовок", size: 22, weight: .heavy) { doc.addText("h1") }
            presetButton("Подзаголовок", size: 16, weight: .bold) { doc.addText("h2") }
            presetButton("Обычный текст", size: 13, weight: .regular) { doc.addText("body") }
            header("Стили")
            HStack(spacing: 8) {
                Button { doc.addText("pill") } label: {
                    Text("НОВИНКА").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.48, green: 0.36, blue: 1)))
                }.buttonStyle(.plain)
                Button { doc.addText("neon") } label: {
                    Text("Неон").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).shadow(color: .cyan, radius: 4).shadow(color: .cyan, radius: 8)
                        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(.black))
                }.buttonStyle(.plain)
                Button { doc.addText("outline") } label: {
                    Text("ОБВОДКА").font(.system(size: 12, weight: .black)).foregroundStyle(.white).shadow(color: .black, radius: 0.6)
                        .shadow(color: .black, radius: 0.6).padding(6).background(RoundedRectangle(cornerRadius: 6).fill(.yellow))
                }.buttonStyle(.plain)
            }
            Text("Двойной клик по тексту на холсте — редактировать").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    func presetButton(_ s: String, size: CGFloat, weight: Font.Weight, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(s).font(.system(size: size, weight: weight)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.fill).overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(DS.line)))
                .hoverHighlight(radius: 11)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var elementsPanel: some View {
        let items: [(LType, String, String)] = [(.rect, "rectangle.fill", "Прямоугольник"), (.ellipse, "circle.fill", "Круг"), (.star, "star.fill", "Звезда"),
                                                 (.frame, "rectangle", "Рамка"), (.arrow, "arrow.right", "Стрелка"), (.line, "line.diagonal", "Линия")]
        return VStack(alignment: .leading, spacing: 8) {
            header("Фигуры")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.2) { t, icon, name in
                    Button { doc.addShape(t) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Accent.shifty.gradient)
                            Text(name).font(DS.font(10, .medium)).foregroundStyle(DS.text2)
                        }.frame(width: 76, height: 64).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.fill).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line)))
                        .hoverHighlight(radius: 12)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            header("Значки")
            let symbols = ["checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill", "info.circle.fill", "heart.fill", "star.fill",
                           "bolt.fill", "flame.fill", "hand.thumbsup.fill", "cursorarrow", "hand.point.up.left.fill", "1.circle.fill", "2.circle.fill",
                           "3.circle.fill", "arrow.down.circle.fill", "lock.fill", "bell.fill", "gift.fill", "crown.fill", "sparkles"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(symbols, id: \.self) { s in
                    Button { doc.addGlyph(s, symbol: true) } label: {
                        Image(systemName: s).font(.system(size: 19)).foregroundStyle(DS.text).frame(width: 42, height: 38)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.fill))
                            .hoverHighlight(radius: 9)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    var stickersPanel: some View {
        let emoji = "😀😂🥹😍🤩😎🤔🤯😱🥳😴🤖👀👍👎👏🙏💪🔥✨⭐️💯✅❌⚠️❗️❓💡🎉🎁🚀💻⌨️🖥📱🧠💬📌📍🔒🔑⏰📈📉💰🛒🍕☕️🌈❤️💜💙🖤".map(String.init)
        return VStack(alignment: .leading, spacing: 8) {
            header("Эмодзи")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(Array(emoji.enumerated()), id: \.offset) { _, e in
                    Button { doc.addGlyph(e, symbol: false) } label: {
                        Text(e).font(.system(size: 26)).frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    var drawPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Кисть")
            Toggle("Рисовать на холсте", isOn: Binding(get: { doc.tool == .pen }, set: { doc.tool = $0 ? .pen : .select; if $0 { doc.selection = nil } }))
                .toggleStyle(.switch)
            ColorPicker("Цвет", selection: $doc.penColor)
            HStack {
                Text("Толщина"); Slider(value: $doc.penWidth, in: 2...80)
                Text("\(Int(doc.penWidth))").font(.system(size: 10)).monospacedDigit().frame(width: 24)
            }
            HStack(spacing: 6) {
                ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .black, .white], id: \.self) { c in
                    Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().strokeBorder(.secondary.opacity(0.5)))
                        .onTapGesture { doc.penColor = c }
                }
            }
            Text("Каждый штрих — отдельный слой: его можно двигать, менять цвет или удалить").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    var hidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Спрятать данные")
            Button { doc.addShape(.blur) } label: { Label("Размытие", systemImage: "drop.halffull").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(height: 36))
            Button { doc.addShape(.pixelate) } label: { Label("Пиксели", systemImage: "square.grid.3x3.fill").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(height: 36))
            Button {
                var l = Layer(type: .rect, frame: CGRect(x: doc.center.x - doc.unit * 0.2, y: doc.center.y - doc.unit * 0.04, width: doc.unit * 0.4, height: doc.unit * 0.08))
                l.fill = .black; l.corner = 4
                doc.add(l)
            } label: { Label("Чёрная плашка", systemImage: "rectangle.fill").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(height: 36))
            Text("Наложите на пароли, почту, токены и лица на скриншоте").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    var backgroundPanel: some View {
        let gradients: [(Color, Color)] = [
            (Color(red: 0.48, green: 0.36, blue: 1), Color(red: 1, green: 0.36, blue: 0.62)), (Color(red: 0.05, green: 0.8, blue: 0.7), Color(red: 0.04, green: 0.36, blue: 1)),
            (Color(red: 1, green: 0.6, blue: 0.2), Color(red: 1, green: 0.25, blue: 0.4)), (Color(red: 0.1, green: 0.1, blue: 0.18), Color(red: 0.3, green: 0.2, blue: 0.5)),
            (Color(red: 0.98, green: 0.85, blue: 0.6), Color(red: 0.98, green: 0.6, blue: 0.7)), (Color(red: 0.6, green: 0.95, blue: 0.6), Color(red: 0.2, green: 0.6, blue: 0.9)),
            (Color(red: 0.95, green: 0.95, blue: 0.97), Color(red: 0.8, green: 0.82, blue: 0.9)), (Color(red: 0.2, green: 0.2, blue: 0.22), Color(red: 0.02, green: 0.02, blue: 0.03)),
        ]
        let solids: [Color] = [.white, .black, Color(white: 0.95), Color(red: 1, green: 0.97, blue: 0.9), Color(red: 0.48, green: 0.36, blue: 1),
                               Color(red: 1, green: 0.3, blue: 0.45), Color(red: 0.1, green: 0.7, blue: 0.5), Color(red: 0.15, green: 0.45, blue: 1)]
        return VStack(alignment: .leading, spacing: 8) {
            header("Градиенты")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<gradients.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [gradients[i].0, gradients[i].1], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 44)
                        .onTapGesture { doc.snapshot(); doc.background = .gradient(gradients[i].0, gradients[i].1, 135) }
                }
            }
            header("Цвета")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<solids.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8).fill(solids[i]).frame(height: 36).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))
                        .onTapGesture { doc.snapshot(); doc.background = .color(solids[i]) }
                }
            }
            header("Свой")
            switch doc.background {
            case .color(let c):
                ColorPicker("Цвет фона", selection: Binding(get: { c }, set: { doc.background = .color($0) }))
            case .gradient(let a, let b, let ang):
                ColorPicker("Цвет 1", selection: Binding(get: { a }, set: { doc.background = .gradient($0, b, ang) }))
                ColorPicker("Цвет 2", selection: Binding(get: { b }, set: { doc.background = .gradient(a, $0, ang) }))
                HStack { Text("Угол"); Slider(value: Binding(get: { ang }, set: { doc.background = .gradient(a, b, $0) }), in: 0...360) }
            case .transparent:
                Text("Прозрачный (сохраните в PNG)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("Прозрачный фон") { doc.snapshot(); doc.background = .transparent }.buttonStyle(PillButtonStyle(height: 30))
        }
    }

    // MARK: Экспорт

    func renderImage() -> CGImage? {
        let prevSel = doc.selection
        doc.selection = nil
        defer { doc.selection = prevSel }
        let r = ImageRenderer(content: CanvasRender(doc: doc))
        r.scale = 1
        r.isOpaque = { if case .transparent = doc.background { return false }; return true }()
        return r.cgImage
    }

    func copyToClipboard() {
        guard let cg = renderImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))])
        doc.status = "Скопировано в буфер"
        NSSound(named: "Pop")?.play()
    }

    func export() {
        guard let cg = renderImage() else { return }
        let p = NSSavePanel()
        let base = doc.sourceURL?.deletingPathExtension().lastPathComponent ?? "Дизайн"
        p.nameFieldStringValue = base + " (Shifty)." + exportFormat.ext
        p.directoryURL = doc.sourceURL?.deletingLastPathComponent()
        if let t = UTType(filenameExtension: exportFormat.ext) { p.allowedContentTypes = [t] }
        guard p.runModal() == .OK, let url = p.url else { return }
        let fmt = exportFormat
        Task {
            do {
                try await Imaging.write(cg, to: url, uti: fmt.uti, quality: quality)
                NSSound(named: "Glass")?.play()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { doc.status = error.localizedDescription }
        }
    }

    func addImageFromPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        if p.runModal() == .OK { p.urls.forEach { doc.addImage($0) } }
    }
}

/// Горячие клавиши холста
struct KeyCatcher: NSViewRepresentable {
    let doc: PhotoDoc
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak v] e in
            guard let w = v?.window, w.isKeyWindow else { return e }
            if w.firstResponder is NSTextView { return e }
            let cmd = e.modifierFlags.contains(.command), shift = e.modifierFlags.contains(.shift)
            let step: CGFloat = shift ? 10 : 1
            switch (e.keyCode, cmd) {
            case (6, true): shift ? doc.redo() : doc.undo(); return nil              // Z
            case (2, true): doc.duplicate(); return nil                               // D
            case (51, false), (117, false): doc.delete(); return nil                  // ⌫ Del
            case (123, false): doc.nudge(-step, 0); return nil
            case (124, false): doc.nudge(step, 0); return nil
            case (125, false): doc.nudge(0, step); return nil
            case (126, false): doc.nudge(0, -step); return nil
            case (53, false): doc.selection = nil; doc.tool = .select; return nil     // Esc
            default: return e
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var monitor: Any?; deinit { if let m = monitor { NSEvent.removeMonitor(m) } } }
}

// MARK: - Общие детали студий

/// Левая панель-рельс с иконками разделов
struct StudioRail<T: Hashable>: View {
    var items: [(T, String, String)]
    @Binding var selection: T
    var accent: Accent
    @Namespace private var ns
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(accent.gradient).frame(width: 30, height: 30).shadow(color: accent.b.opacity(0.6), radius: 8)
                Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.bottom, 14)
            ForEach(items, id: \.0) { v, title, icon in
                let on = v == selection
                Button { withAnimation(DS.spring) { selection = v } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon).font(.system(size: 16, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(DS.text2))
                            .frame(width: 38, height: 32)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.gradient)
                                        .matchedGeometryEffect(id: "rail", in: ns)
                                        .shadow(color: accent.b.opacity(0.5), radius: 8, y: 2)
                                }
                            }
                        Text(title).font(DS.font(9.5, on ? .semibold : .medium)).foregroundStyle(on ? DS.text : DS.text3)
                    }
                    .frame(width: 66, height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 34)
        .padding(.horizontal, 4)
        .frame(width: 74)
        .background(DS.bg0)
        .overlay(alignment: .trailing) { Rectangle().fill(DS.line).frame(width: 1) }
    }
}

/// Фон вокруг холста: тёмный с точечной сеткой и свечением
struct StudioBackdrop: View {
    var accent: Accent
    var body: some View {
        ZStack {
            DS.bg0
            Canvas { ctx, size in
                let step: CGFloat = 22
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.07)))
                        x += step
                    }
                    y += step
                }
            }
            RadialGradient(colors: [accent.b.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 600)
        }
    }
}

/// Капсула масштаба: − 100% +
struct ZoomControl: View {
    @Binding var zoom: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Button { zoom = max(0.05, zoom / 1.25) } label: { Image(systemName: "minus").frame(width: 26, height: 28) }
            Text("\(Int(zoom * 100))%").font(DS.font(11.5, .semibold, rounded: true)).monospacedDigit().frame(width: 44)
                .onTapGesture { zoom = 1 }
            Button { zoom = min(4, zoom * 1.25) } label: { Image(systemName: "plus").frame(width: 26, height: 28) }
        }
        .buttonStyle(.plain).font(.system(size: 10, weight: .bold)).foregroundStyle(DS.text2)
        .background(Capsule().fill(DS.fill).overlay(Capsule().strokeBorder(DS.line)))
    }
}
