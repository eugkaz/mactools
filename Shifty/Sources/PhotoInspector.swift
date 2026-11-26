import AppKit
import SwiftUI

struct InspectorView: View {
    @Bindable var doc: PhotoDoc
    @FocusState private var textFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let l = doc.selected {
                    HStack {
                        Image(systemName: l.icon).foregroundStyle(Accent.shifty.gradient)
                        Text(l.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                    }
                    arrange(l)
                    Divider()
                    specific(l)
                    Divider()
                    common(l)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "cursorarrow.click.2").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Выберите слой на холсте").foregroundStyle(.secondary)
                        Text("⌘Z — отменить · ⌘D — дублировать\n⌫ — удалить · стрелки — сдвиг\nShift при повороте — шаг 15°")
                            .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.top, 60)
                }
                if let s = doc.status { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .padding(14)
            .padding(.top, 22)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusText)) { _ in textFocus = true }
    }

    func bind<T>(_ kp: WritableKeyPath<Layer, T>, snapshot: Bool = false, after: ((inout Layer) -> Void)? = nil) -> Binding<T> {
        Binding(get: { doc.selected![keyPath: kp] }, set: { v in
            guard let id = doc.selection else { return }
            doc.update(id, snapshot: snapshot) { $0[keyPath: kp] = v; after?(&$0) }
        })
    }

    func refit(_ l: inout Layer) {
        let c = CGPoint(x: l.frame.midX, y: l.frame.midY)
        let s = TextMeasure.size(l)
        l.frame = CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
    }

    func arrange(_ l: Layer) -> some View {
        HStack(spacing: 4) {
            iconBtn("square.3.layers.3d.top.filled", "На передний план") { doc.toFront() }
            iconBtn("chevron.up", "Выше") { doc.move(1) }
            iconBtn("chevron.down", "Ниже") { doc.move(-1) }
            iconBtn("square.3.layers.3d.bottom.filled", "На задний план") { doc.toBack() }
            Spacer()
            iconBtn(l.locked ? "lock.fill" : "lock.open", "Закрепить") { doc.update(l.id, snapshot: true) { $0.locked.toggle() } }
            iconBtn("plus.square.on.square", "Дублировать ⌘D") { doc.duplicate() }
            iconBtn("trash", "Удалить ⌫") { doc.delete() }
        }
    }

    func iconBtn(_ s: String, _ help: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { Image(systemName: s).frame(width: 22, height: 20) }.buttonStyle(.borderless).help(help)
    }

    func slider(_ title: String, _ b: Binding<CGFloat>, _ r: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title).font(.system(size: 11)); Spacer(); Text("\(Int(b.wrappedValue))").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: b, in: r)
        }
    }

    @ViewBuilder func specific(_ l: Layer) -> some View {
        switch l.type {
        case .text:
            TextEditor(text: bind(\.text, after: refit))
                .font(.system(size: 13)).frame(height: 70).scrollContentBackground(.hidden)
                .padding(4).background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                .focused($textFocus)
            Picker("Шрифт", selection: bind(\.fontName, after: refit)) {
                ForEach(Fonts.curated, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                Divider()
                ForEach(Fonts.all, id: \.self) { Text($0).tag($0) }
            }
            slider("Размер", bind(\.fontSize, after: refit), 8...max(400, l.fontSize))
            HStack {
                Toggle("Жирный", isOn: bind(\.bold, after: refit)).toggleStyle(.button)
                Toggle("Курсив", isOn: bind(\.italic, after: refit)).toggleStyle(.button)
                Picker("", selection: bind(\.align)) {
                    Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                    Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                    Image(systemName: "text.alignright").tag(TextAlignment.trailing)
                }.pickerStyle(.segmented).labelsHidden()
            }
            slider("Межбуквенный", bind(\.letterSpacing, after: refit), -5...40)
            ColorPicker("Цвет текста", selection: bind(\.color))
            Picker("Стиль", selection: bind(\.textStyle, after: refit)) { ForEach(TextStyle.allCases) { Text($0.rawValue).tag($0) } }
            if [.outline, .pill, .neon].contains(l.textStyle) {
                ColorPicker(l.textStyle == .pill ? "Цвет плашки" : (l.textStyle == .neon ? "Цвет свечения" : "Цвет обводки"), selection: bind(\.accent))
            }
        case .rect, .ellipse, .star:
            ColorPicker("Заливка", selection: bind(\.fill))
            ColorPicker("Обводка", selection: bind(\.stroke))
            slider("Толщина обводки", bind(\.strokeWidth), 0...80)
            if l.type == .rect { slider("Скругление", bind(\.corner), 0...min(l.frame.width, l.frame.height) / 2) }
        case .frame, .line, .arrow, .pen:
            ColorPicker("Цвет", selection: bind(\.stroke))
            slider("Толщина", bind(\.strokeWidth), 1...80)
            if l.type == .frame { slider("Скругление", bind(\.corner), 0...min(l.frame.width, l.frame.height) / 2) }
        case .symbol:
            ColorPicker("Цвет", selection: bind(\.color))
        case .image:
            slider("Скругление углов", bind(\.corner), 0...min(l.frame.width, l.frame.height) / 2)
            Toggle("Тень", isOn: bind(\.imageShadow))
            ColorPicker("Рамка", selection: bind(\.stroke))
            slider("Толщина рамки", bind(\.strokeWidth), 0...60)
            Text("Фильтры и коррекция — вкладка «Фото» слева").font(.system(size: 10)).foregroundStyle(.secondary)
        case .blur, .pixelate:
            VStack(alignment: .leading) {
                Text("Сила").font(.system(size: 11))
                Slider(value: bind(\.amount), in: 0...1)
            }
            slider("Скругление", bind(\.corner), 0...min(l.frame.width, l.frame.height) / 2)
        case .emoji:
            EmptyView()
        }
    }

    func common(_ l: Layer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text("Прозрачность").font(.system(size: 11)); Spacer(); Text("\(Int(l.opacity * 100))%").font(.system(size: 10)).foregroundStyle(.secondary) }
                Slider(value: bind(\.opacity), in: 0.05...1)
            }
            slider("Поворот °", Binding(get: { CGFloat(l.rotation) }, set: { v in doc.update(l.id) { $0.rotation = Double(v) } }), -180...180)
            HStack {
                Text("X").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("", value: Binding(get: { Int(l.frame.minX) }, set: { v in doc.update(l.id, snapshot: true) { $0.frame.origin.x = CGFloat(v) } }), format: .number).frame(width: 52)
                Text("Y").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("", value: Binding(get: { Int(l.frame.minY) }, set: { v in doc.update(l.id, snapshot: true) { $0.frame.origin.y = CGFloat(v) } }), format: .number).frame(width: 52)
                Spacer()
                Text("\(Int(l.frame.width))×\(Int(l.frame.height))").font(.system(size: 10)).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).controlSize(.small)
            Text("ВЫРОВНЯТЬ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                alignBtn("align.horizontal.left") { $0.origin.x = 0 }
                alignBtn("align.horizontal.center") { $0.origin.x = doc.canvas.width / 2 - $0.width / 2 }
                alignBtn("align.horizontal.right") { $0.origin.x = doc.canvas.width - $0.width }
                alignBtn("align.vertical.top") { $0.origin.y = 0 }
                alignBtn("align.vertical.center") { $0.origin.y = doc.canvas.height / 2 - $0.height / 2 }
                alignBtn("align.vertical.bottom") { $0.origin.y = doc.canvas.height - $0.height }
                alignBtn("arrow.up.left.and.arrow.down.right") { $0 = CGRect(origin: .zero, size: doc.canvas) }
            }
        }
    }

    func alignBtn(_ icon: String, _ f: @escaping (inout CGRect) -> Void) -> some View {
        Button { if let id = doc.selection { doc.update(id, snapshot: true) { f(&$0.frame) } } } label: {
            Image(systemName: icon).frame(width: 26, height: 22)
        }.buttonStyle(.bordered).controlSize(.small)
    }
}

enum Fonts {
    static let curated = ["Helvetica Neue", "SF Pro", "Avenir Next", "Futura", "Gill Sans", "Georgia", "Didot", "Baskerville", "Menlo",
                          "American Typewriter", "Chalkboard SE", "Marker Felt", "Noteworthy", "Rockwell", "Impact", "Copperplate", "Snell Roundhand"]
        .filter { NSFont(name: $0, size: 12) != nil || NSFontManager.shared.availableFontFamilies.contains($0) }
    static let all = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") && !curated.contains($0) }
}

struct AdjustPanel: View {
    @Bindable var doc: PhotoDoc

    var target: Layer? { doc.selected?.type == .image ? doc.selected : doc.layers.first { $0.type == .image } }

    func bind(_ kp: WritableKeyPath<EditSettings, Double>) -> Binding<Double> {
        Binding(get: { target?.adjust[keyPath: kp] ?? 0 }, set: { v in if let t = target { doc.update(t.id) { $0.adjust[keyPath: kp] = v } } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = target {
                Text(doc.selected?.id == t.id ? "Выбранное фото" : "Основное фото").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("ФИЛЬТРЫ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                    ForEach(Preset.allCases) { p in
                        Button { doc.update(t.id, snapshot: true) { $0.adjust.preset = p } } label: {
                            Text(p.rawValue).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 7).fill(t.adjust.preset == p ? Accent.shifty.b : DS.fill))
                                .foregroundStyle(t.adjust.preset == p ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                Text("КОРРЕКЦИЯ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                row("Экспозиция", \.exposure, -2...2)
                row("Яркость", \.brightness, -0.5...0.5)
                row("Контраст", \.contrast, 0.5...1.6)
                row("Насыщенность", \.saturation, 0...2)
                row("Теплота", \.warmth, -1...1)
                row("Резкость", \.sharpen, 0...2)
                row("Размытие", \.blur, 0...10)
                row("Виньетка", \.vignette, 0...1)
                Text("ПОВОРОТ И КАДР").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack {
                    Button { doc.update(t.id, snapshot: true) { $0.adjust.rotation -= 1; let f = $0.frame; $0.frame = CGRect(x: f.midX - f.height / 2, y: f.midY - f.width / 2, width: f.height, height: f.width) } } label: { Image(systemName: "rotate.left") }
                    Button { doc.update(t.id, snapshot: true) { $0.adjust.rotation += 1; let f = $0.frame; $0.frame = CGRect(x: f.midX - f.height / 2, y: f.midY - f.width / 2, width: f.height, height: f.width) } } label: { Image(systemName: "rotate.right") }
                    Button { doc.update(t.id, snapshot: true) { $0.adjust.flipH.toggle() } } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    Button { doc.update(t.id, snapshot: true) { $0.adjust.flipV.toggle() } } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                }
                Picker("Кадр", selection: Binding(get: { t.adjust.aspect }, set: { a in
                    doc.update(t.id, snapshot: true) { l in
                        l.adjust.aspect = a
                        guard let img = l.image else { return }
                        var w = img.size.width, h = img.size.height
                        if l.adjust.rotation % 2 != 0 { swap(&w, &h) }
                        if let r = a.ratio { if w / h > r { w = h * r } else { h = w / r } }
                        let k = min(l.frame.width / w, l.frame.height / h)
                        l.frame = CGRect(x: l.frame.midX - w * k / 2, y: l.frame.midY - h * k / 2, width: w * k, height: h * k)
                    }
                })) { ForEach(Aspect.allCases) { Text($0.rawValue).tag($0) } }
                Button("Сбросить коррекцию") { doc.update(t.id, snapshot: true) { $0.adjust = EditSettings() } }
            } else {
                Text("Добавьте фото на холст").foregroundStyle(.secondary)
            }
        }
    }

    func row(_ title: String, _ kp: WritableKeyPath<EditSettings, Double>, _ r: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(String(format: "%.2f", bind(kp).wrappedValue)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: bind(kp), in: r)
        }
    }
}

struct LayersPanel: View {
    @Bindable var doc: PhotoDoc
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("СЛОИ (сверху — передний план)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(doc.layers.reversed()) { l in
                HStack(spacing: 8) {
                    Image(systemName: l.icon).frame(width: 18).foregroundStyle(Accent.shifty.gradient)
                    Text(l.title).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Button { doc.update(l.id, snapshot: true) { $0.hidden.toggle() } } label: { Image(systemName: l.hidden ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                    Button { doc.update(l.id, snapshot: true) { $0.locked.toggle() } } label: { Image(systemName: l.locked ? "lock.fill" : "lock.open") }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(doc.selection == l.id ? Accent.shifty.b.opacity(0.2) : DS.fill))
                .contentShape(Rectangle())
                .onTapGesture { doc.selection = l.id }
            }
            if doc.layers.isEmpty { Text("Пусто").foregroundStyle(.secondary) }
        }
    }
}
