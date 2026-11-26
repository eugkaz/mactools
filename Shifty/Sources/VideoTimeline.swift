import AppKit
import SwiftUI

struct TimelineView2: View {
    @Bindable var p: VideoProject
    @Binding var pps: CGFloat
    let lead: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "minus.magnifyingglass").font(.system(size: 10))
                Slider(value: $pps, in: 6...240).frame(width: 140).controlSize(.mini)
                Image(systemName: "plus.magnifyingglass").font(.system(size: 10))
                Spacer()
                if case .clip = p.selection {
                    Button { p.moveClip(-1) } label: { Image(systemName: "arrow.left") }.help("Сдвинуть клип влево")
                    Button { p.moveClip(1) } label: { Image(systemName: "arrow.right") }.help("Сдвинуть клип вправо")
                    Button { p.duplicateClip() } label: { Image(systemName: "plus.square.on.square") }.help("Дублировать ⌘D")
                }
            }
            .controlSize(.small).buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 5)
            ScrollView(.horizontal) {
                let width = max(800, CGFloat(p.total) * pps + 300)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ruler.frame(height: 20)
                        trackLabel("film", h: 62) { clipsTrack }
                        trackLabel("textformat", h: 28) { textTrack }
                        trackLabel("music.note", h: 28) { musicTrack }
                    }
                    playhead.frame(height: 180)
                }
                .frame(width: width, alignment: .topLeading)
                .padding(.leading, lead)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    func trackLabel<C: View>(_ icon: String, h: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.fill).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.line)).frame(height: h)
            c().frame(height: h, alignment: .leading)
        }
    }

    var ruler: some View {
        Canvas { ctx, size in
            let step: Double = pps > 80 ? 1 : pps > 25 ? 5 : 10
            var t = 0.0
            while CGFloat(t) * pps < size.width {
                let x = CGFloat(t) * pps
                ctx.fill(Path(CGRect(x: x, y: 12, width: 1, height: 8)), with: .color(.secondary))
                ctx.draw(Text(String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)).font(.system(size: 9)).foregroundStyle(.secondary),
                         at: CGPoint(x: x + 2, y: 5), anchor: .leading)
                let sub = step / 5
                for k in 1..<5 {
                    let xs = CGFloat(t + sub * Double(k)) * pps
                    ctx.fill(Path(CGRect(x: xs, y: 16, width: 1, height: 4)), with: .color(.secondary.opacity(0.5)))
                }
                t += step
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in p.seek(Double(v.location.x / pps)) })
    }

    var playhead: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Accent.shifty.gradient).frame(width: 2).shadow(color: Accent.shifty.b, radius: 4)
            Circle().fill(Accent.shifty.gradient).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)).shadow(color: Accent.shifty.b, radius: 5)
        }
        .frame(width: 12)
        .offset(x: CGFloat(p.playhead) * pps - 6)
        .gesture(DragGesture().onChanged { v in p.seek(Double((CGFloat(p.playhead) * pps + v.translation.width) / pps)) })
        .allowsHitTesting(true)
    }

    var clipsTrack: some View {
        HStack(spacing: 0) {
            ForEach(p.clips) { c in ClipBlock(p: p, clip: c, pps: pps) }
        }
    }

    var textTrack: some View {
        ZStack(alignment: .leading) {
            ForEach(p.texts) { t in TextBlock(p: p, t: t, pps: pps) }
        }
    }

    @ViewBuilder var musicTrack: some View {
        if let m = p.music {
            let len = min(m.duration - m.offset, p.total)
            HStack(spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 10))
                Text(m.url.deletingPathExtension().lastPathComponent).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: max(30, CGFloat(len) * pps), height: 24, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [Color(hex: 0x2FD39A), Color(hex: 0x14A37F)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(p.selection == .music ? Color.white : .clear, lineWidth: 2))
            .foregroundStyle(.white)
            .onTapGesture { p.selection = .music }
        }
    }
}

struct ClipBlock: View {
    let p: VideoProject
    let clip: Clip
    let pps: CGFloat
    @State private var startClip: Clip?

    var body: some View {
        let w = max(14, CGFloat(clip.duration) * pps)
        let sel = p.selection == .clip(clip.id)
        ZStack(alignment: .leading) {
            thumbStrip(w)
                .frame(width: w, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if clip.speed != 1 || clip.muted {
                HStack(spacing: 3) {
                    if clip.speed != 1 { Text(String(format: "%.2g×", clip.speed)) }
                    if clip.muted { Image(systemName: "speaker.slash.fill") }
                }
                .font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6))).foregroundStyle(.white).padding(4)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            RoundedRectangle(cornerRadius: 6).strokeBorder(sel ? Color.white : Color.black.opacity(0.3), lineWidth: sel ? 2.5 : 1)
                .frame(width: w, height: 58)
            if sel {
                handle(left: true).frame(maxWidth: .infinity, alignment: .leading)
                handle(left: false).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: w, height: 58)
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .onTapGesture { p.selection = .clip(clip.id) }
    }

    func thumbStrip(_ w: CGFloat) -> some View {
        let imgs = p.thumbs[clip.id] ?? []
        let n = max(1, Int(ceil(w / 52)))
        return HStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { i in
                // кадр из обрезанного диапазона
                let src = clip.trimStart + (clip.trimEnd - clip.trimStart) * (Double(i) + 0.5) / Double(n)
                let idx = imgs.isEmpty ? -1 : min(imgs.count - 1, max(0, Int(src / clip.sourceDuration * Double(imgs.count))))
                ZStack {
                    Color(hex: 0x2A2340)
                    if idx >= 0 { Image(nsImage: imgs[idx]).resizable().aspectRatio(contentMode: .fill) }
                }
                .frame(width: w / CGFloat(n), height: 58).clipped()
            }
        }
    }

    func handle(left: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.white)
            .overlay(Image(systemName: left ? "chevron.compact.left" : "chevron.compact.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
            .frame(width: 10, height: 58)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                if startClip == nil { startClip = clip; p.checkpoint() }
                guard let s = startClip else { return }
                let dt = Double(v.translation.width / pps) * s.speed
                p.updateClip(clip.id) { c in
                    if left { c.trimStart = min(max(0, s.trimStart + dt), s.trimEnd - 0.2) }
                    else { c.trimEnd = max(min(s.sourceDuration, s.trimEnd + dt), s.trimStart + 0.2) }
                }
            }.onEnded { _ in startClip = nil })
    }
}

struct TextBlock: View {
    let p: VideoProject
    let t: TextOverlay
    let pps: CGFloat
    @State private var s0: TextOverlay?

    var body: some View {
        let sel = p.selection == .text(t.id)
        HStack(spacing: 0) {
            edge(left: true)
            Text(t.text).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            edge(left: false)
        }
        .frame(width: max(20, CGFloat(t.end - t.start) * pps), height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [Color(hex: 0xFFB547), Color(hex: 0xFF7A3D)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(sel ? Color.white : .clear, lineWidth: 2))
        .foregroundStyle(.white)
        .offset(x: CGFloat(t.start) * pps)
        .gesture(DragGesture(minimumDistance: 2).onChanged { v in
            if s0 == nil { s0 = t; p.checkpoint(); p.selection = .text(t.id) }
            guard let s = s0 else { return }
            let d = Double(v.translation.width / pps)
            let len = s.end - s.start
            let ns = max(0, s.start + d)
            p.updateText(t.id) { $0.start = ns; $0.end = ns + len }
        }.onEnded { _ in s0 = nil })
        .onTapGesture { p.selection = .text(t.id); p.seek(t.start + 0.01) }
    }

    func edge(left: Bool) -> some View {
        Rectangle().fill(Color.white.opacity(0.001)).frame(width: 7)
            .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                if s0 == nil { s0 = t; p.checkpoint() }
                guard let s = s0 else { return }
                let d = Double(v.translation.width / pps)
                p.updateText(t.id) { x in
                    if left { x.start = min(max(0, s.start + d), s.end - 0.2) } else { x.end = max(s.start + 0.2, s.end + d) }
                }
            }.onEnded { _ in s0 = nil })
    }
}

struct VideoInspector: View {
    @Bindable var p: VideoProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch p.selection {
                case .clip(let id):
                    if let c = p.clips.first(where: { $0.id == id }) { clipPanel(c) }
                case .text(let id):
                    if let t = p.texts.first(where: { $0.id == id }) { textPanel(t) }
                case .music:
                    if let m = p.music { musicPanel(m) }
                case nil:
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Выберите клип, текст или музыку на таймлайне").foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("Пробел — play · S — разрезать\n⌫ — удалить · ⌘D — дублировать\n← → — по кадру, ⇧ — по секунде")
                            .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.top, 50)
                }
            }
            .padding(14).padding(.top, 22)
        }
    }

    func h(_ s: String) -> some View { Text(s.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }

    func clipPanel(_ c: Clip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            h("Скорость")
            HStack(spacing: 4) {
                ForEach([0.25, 0.5, 1, 1.5, 2, 4], id: \.self) { s in
                    Button(String(format: "%g×", s)) { p.checkpoint(); p.updateClip(c.id) { $0.speed = s } }
                        .buttonStyle(.bordered).tint(c.speed == s ? Accent.shifty.b : nil).controlSize(.small)
                }
            }
            Slider(value: Binding(get: { c.speed }, set: { v in p.updateClip(c.id) { $0.speed = (v * 20).rounded() / 20 } }), in: 0.1...5)
            h("Звук")
            Toggle("Без звука", isOn: Binding(get: { c.muted }, set: { v in p.checkpoint(); p.updateClip(c.id) { $0.muted = v } }))
                .disabled(!c.hasAudio)
            HStack { Text("Громкость").font(.system(size: 11)); Slider(value: Binding(get: { c.volume }, set: { v in p.updateClip(c.id) { $0.volume = v } }), in: 0...2) }
            h("Обрезка")
            Text(String(format: "%.2f – %.2f с из %.1f с", c.trimStart, c.trimEnd, c.sourceDuration)).font(.system(size: 11, design: .monospaced))
            HStack {
                Button("Начало = курсор") { trim(c, start: true) }
                Button("Конец = курсор") { trim(c, start: false) }
            }.controlSize(.small)
            Button("Сбросить обрезку") { p.checkpoint(); p.updateClip(c.id) { $0.trimStart = 0; $0.trimEnd = $0.sourceDuration } }.controlSize(.small)
            Divider()
            HStack {
                Button { p.duplicateClip() } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { p.deleteSelection() } label: { Label("Удалить", systemImage: "trash") }
            }.controlSize(.small)
        }
    }

    func trim(_ c: Clip, start: Bool) {
        let s = p.clipStart(c.id)
        let local = p.playhead - s
        guard local > 0, local < c.duration else { NSSound.beep(); return }
        p.checkpoint()
        let src = c.trimStart + local * c.speed
        p.updateClip(c.id) { if start { $0.trimStart = src } else { $0.trimEnd = src } }
    }

    func textPanel(_ t: TextOverlay) -> some View {
        func b<T>(_ kp: WritableKeyPath<TextOverlay, T>) -> Binding<T> {
            Binding(get: { p.texts.first { $0.id == t.id }?[keyPath: kp] ?? t[keyPath: kp] }, set: { v in p.updateText(t.id) { $0[keyPath: kp] = v } })
        }
        return VStack(alignment: .leading, spacing: 10) {
            h("Текст")
            TextEditor(text: b(\.text)).font(.system(size: 13)).frame(height: 60).scrollContentBackground(.hidden)
                .padding(4).background(RoundedRectangle(cornerRadius: 6).fill(DS.fill))
            HStack { Text("Размер").font(.system(size: 11)); Slider(value: b(\.size), in: 0.02...0.25) }
            Toggle("Жирный", isOn: b(\.bold))
            ColorPicker("Цвет", selection: b(\.color))
            Picker("Стиль", selection: b(\.style)) { ForEach(TextStyle.allCases) { Text($0.rawValue).tag($0) } }
            if [.outline, .pill, .neon].contains(t.style) { ColorPicker("Акцент", selection: b(\.accent)) }
            Picker("Анимация", selection: b(\.anim)) { ForEach(TextAnim.allCases) { Text($0.rawValue).tag($0) } }
            h("Время")
            HStack {
                Text(String(format: "%.1f – %.1f с", t.start, t.end)).font(.system(size: 11, design: .monospaced))
                Spacer()
            }
            HStack {
                Button("С курсора") { p.checkpoint(); p.updateText(t.id) { let l = $0.end - $0.start; $0.start = p.playhead; $0.end = p.playhead + l } }
                Button("До курсора") { p.checkpoint(); p.updateText(t.id) { $0.end = max($0.start + 0.2, p.playhead) } }
            }.controlSize(.small)
            h("Позиция")
            HStack {
                ForEach([("Верх", 0.15), ("Центр", 0.5), ("Низ", 0.85)], id: \.0) { n, y in
                    Button(n) { p.checkpoint(); p.updateText(t.id) { $0.pos = CGPoint(x: 0.5, y: y) } }.controlSize(.small)
                }
            }
            Button(role: .destructive) { p.deleteSelection() } label: { Label("Удалить текст", systemImage: "trash") }.controlSize(.small)
        }
    }

    func musicPanel(_ m: MusicTrack) -> some View {
        func b<T>(_ kp: WritableKeyPath<MusicTrack, T>) -> Binding<T> {
            Binding(get: { p.music?[keyPath: kp] ?? m[keyPath: kp] }, set: { v in p.music?[keyPath: kp] = v; p.scheduleRebuild() })
        }
        return VStack(alignment: .leading, spacing: 10) {
            h("Музыка")
            Text(m.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            HStack { Text("Громкость").font(.system(size: 11)); Slider(value: b(\.volume), in: 0...1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Начать трек с %.1f с", m.offset)).font(.system(size: 11))
                Slider(value: b(\.offset), in: 0...max(0.1, m.duration - 1))
            }
            Toggle("Плавное начало", isOn: b(\.fadeIn))
            Toggle("Плавное затухание", isOn: b(\.fadeOut))
            Button(role: .destructive) { p.deleteSelection() } label: { Label("Убрать музыку", systemImage: "trash") }.controlSize(.small)
        }
    }
}
