import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Акценты живые: следуют за обложкой играющего трека (Theme)
var accent: Color { Theme.shared.a }
var accentB: Color { Theme.shared.b }
var deckAccent: Accent { Theme.shared.accent }
var deckGrad: LinearGradient { Theme.shared.accent.gradient }

/// Те же кривые, что у Coucou (IslandRootView): открытие — пружина 0.5/0.72, закрытие — ease 0.34 с
let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
let closeEase = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

struct DeckView: View {
    @Bindable var deck: DeckState

    var body: some View {
        let t = deck.progress
        let r = deck.shapeRect
        let ih = deck.islandHeight
        let left = deck.solo ? ih / 2 + (20 - ih / 2) * min(max(t, 0), 1) : 20 * min(max(t, 0), 1)
        let right = ih / 2 + (20 - ih / 2) * min(max(t, 0), 1)
        let cr = deck.cornerRadius
        let shape = deck.corner
            ? UnevenRoundedRectangle(topLeadingRadius: cr, bottomLeadingRadius: cr, bottomTrailingRadius: cr, topTrailingRadius: cr, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: left, bottomTrailingRadius: right, topTrailingRadius: 0, style: .continuous)
        let align: Alignment = deck.corner ? .bottomTrailing : .topLeading
        let closedCorner = deck.corner && !deck.isOpen
        let contentOpacity = min(max((t - 0.55) / 0.35, 0), 1)
        let islandOpacity = min(max(1 - t / 0.25, 0), 1)

        ZStack(alignment: .topLeading) {
            // подпись трека, выезжающая слева от круга при наведении
            if deck.corner { BubbleLabel(deck: deck) }
            ZStack(alignment: align) {
                shape.fill(Color.black)
                // Окраска под обложку: в раскрытой панели — заливка из угла, в свёрнутом островке — отлив слева
                if let bg = Theme.shared.bg {
                    LinearGradient(colors: [bg.opacity(0.26), bg.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(contentOpacity).allowsHitTesting(false)
                    LinearGradient(colors: [bg.opacity(0.9), bg.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: deck.islandWidth, height: ih)
                        .opacity(deck.playingNow && !deck.corner ? islandOpacity : 0).allowsHitTesting(false)
                }
                if deck.isOpen {
                    PatternField(kind: Prefs.shared.pattern).opacity(contentOpacity)
                }
                if deck.corner {
                    BubbleContent(deck: deck)
                        .frame(width: DeckState.bubble, height: DeckState.bubble)
                        .opacity(deck.showHUD ? 0 : islandOpacity)
                    BubbleHUD(hud: deck.hud)
                        .frame(width: DeckState.bubble, height: DeckState.bubble)
                        .opacity(deck.showHUD ? islandOpacity : 0)
                        .scaleEffect(deck.showHUD ? 1 : 0.7)
                        .allowsHitTesting(false)
                } else {
                    IslandContent(deck: deck)
                        .frame(width: deck.islandWidth, height: ih)
                        .opacity(deck.showHUD ? 0 : islandOpacity)
                        .blur(radius: deck.showHUD ? 3 : 0)
                    IslandHUD(deck: deck)
                        .frame(width: deck.islandWidth, height: ih)
                        .opacity(deck.showHUD ? islandOpacity : 0)
                        .blur(radius: deck.showHUD ? 0 : 3)
                        .allowsHitTesting(false)
                }
                if deck.isOpen {
                    LinearGradient(colors: [.clear, accent.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 60)
                        .opacity(contentOpacity).allowsHitTesting(false)
                    VStack(spacing: 0) {
                        TopBar(deck: deck)
                        HairDivider()
                        Group {
                            if deck.showSettings { SettingsView().transition(.opacity.combined(with: .move(edge: .top))) }
                            else { content }
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(ScanSweep(trigger: "\(deck.tab.rawValue)\(deck.showSettings)"))
                    }
                    .frame(width: deck.panelWidth, height: max(DeckState.panelHeight, r.height), alignment: .topLeading)
                    .opacity(contentOpacity)
                    .allowsHitTesting(contentOpacity > 0.5)
                    // панель открыта — громкость/яркость всплывает капсулой снизу
                    PanelHUD(hud: deck.hud)
                        .frame(width: r.width, height: r.height, alignment: .bottom)
                        .padding(.bottom, 10)
                        .opacity(deck.hud.visible ? contentOpacity : 0)
                        .offset(y: deck.hud.visible ? 0 : 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: r.width, height: r.height, alignment: align)
            .clipShape(shape)
            // «ушки»: панель вырастает из верхнего края экрана, как настоящая чёлка
            .overlay(alignment: .topTrailing) {
                if !deck.corner { NotchEar(right: true).fill(Color.black).frame(width: earSize, height: earSize).offset(x: earSize) }
            }
            .overlay(alignment: .topLeading) {
                if !deck.corner && deck.solo { NotchEar(right: false).fill(Color.black).frame(width: earSize, height: earSize).offset(x: -earSize) }
            }
            .overlay {   // светящаяся кромка круга в цвет трека
                if deck.corner {
                    shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.9), accentB.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                       lineWidth: deck.peek && closedCorner ? 1.6 : 0.8)
                        .opacity(closedCorner ? 1 : 0.35)
                }
            }
            .shadow(color: deck.corner ? (deck.peek && closedCorner ? accent.opacity(0.55) : .black.opacity(0.5)) : .clear,
                    radius: deck.corner ? (deck.peek && closedCorner ? 16 : 12) : 0, y: deck.corner ? 4 : 0)
            .scaleEffect(closedCorner ? (deck.pressing ? 0.84 : (deck.peek ? 1.12 : (deck.showHUD ? 1.1 : 1))) : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: deck.peek)
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: deck.showHUD)
            // смена места: схлопывание/появление (как Dynamic Island), без перелёта через экран
            .scaleEffect(x: 0.15 + 0.85 * deck.morph, y: deck.corner ? 0.15 + 0.85 * deck.morph : 0.3 + 0.7 * deck.morph,
                         anchor: deck.corner ? .center : .top)
            .opacity(Double(min(1, deck.morph * 1.6)))
            .blur(radius: (1 - deck.morph) * 4)
            .offset(x: r.minX, y: r.minY)
        }
        .frame(width: deck.windowSize.width, height: deck.windowSize.height, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: deck.islandWidth)
        .foregroundStyle(.white)
        .tint(accent)
    }

    var earSize: CGFloat { 6 + 6 * min(max(deck.progress, 0), 1) }

    @ViewBuilder var content: some View {
        switch deck.tab {
        case .media: MediaTab(m: deck.media)
        case .clipboard: ClipboardTab(store: deck.clipboard)
        case .shelf: ShelfTab(store: deck.shelf)
        case .launcher: LauncherTab(store: deck.launcher)
        case .dev: DevTab(ports: deck.ports, snippets: deck.snippets)
        case .system: SystemTab(sys: deck.system)
        }
    }
}

/// Свёрнутый островок — висит рядом с Coucou всегда
struct IslandContent: View {
    let deck: DeckState
    var body: some View {
        let m = deck.media
        let h = deck.islandHeight
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                if deck.playingNow || (deck.peek && !m.title.isEmpty) {
                    ZStack {
                        if let art = m.artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(accent)
                        }
                    }
                    .frame(width: h - 8, height: h - 8)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(accent.opacity(0.55), lineWidth: 0.7))
                    .shadow(color: accent.opacity(0.6), radius: 4)
                    Text(m.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                    if deck.peek {
                        HStack(spacing: 0) {
                            mini("backward.fill") { m.command("previous track") }
                            mini(m.isPlaying ? "pause.fill" : "play.fill", big: true) { m.command("playpause") }
                            mini("forward.fill") { m.command("next track") }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                    } else {
                        Image(systemName: m.isPlaying ? "waveform" : "pause.fill").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(deckGrad)
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        Text(Date().formatted(date: .omitted, time: .shortened)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, deck.hiddenPart + (deck.solo ? 8 : 4))
            .padding(.trailing, deck.peek ? 4 : 9)
            .frame(height: h)
            // тонкая линия прогресса по низу островка
            if (deck.playingNow || deck.peek) && m.duration > 0 {
                GeometryReader { g in
                    let x0 = deck.hiddenPart + (deck.solo ? h / 2 : 2)
                    let w = max(0, g.size.width - x0 - h / 2)
                    Capsule().fill(deckGrad)
                        .frame(width: max(2, w * min(1, m.position / max(m.duration, 1))), height: 1.5)
                        .shadow(color: accent.opacity(0.8), radius: 2)
                        .offset(x: x0, y: g.size.height - 2.5)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(DS.snappy, value: deck.peek)
    }

    func mini(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 10 : 8.5, weight: .bold))
                .foregroundStyle(big ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(0.85)))
                .frame(width: big ? 18 : 20, height: 18)
                .background { if big { Circle().fill(deckGrad) } }
                .contentShape(Rectangle())
        }.buttonStyle(PressScale())
    }
}

/// Круг в углу: обложка, кольцо прогресса, при наведении — значок воспроизведения
struct BubbleContent: View {
    let deck: DeckState
    var body: some View {
        let m = deck.media
        let B = DeckState.bubble
        ZStack {
            if let art = m.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).frame(width: B, height: B)
                    .scaleEffect(deck.peek ? 1.08 : 1)
            } else if m.source != nil {
                LinearGradient(colors: [accent, accentB], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 18, weight: .bold)).foregroundStyle(.black.opacity(0.8))
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text(Date().formatted(date: .omitted, time: .shortened)).font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white.opacity(0.9))
                }
            }
            if m.source != nil {
                // затемнение и значок при наведении
                Circle().fill(.black.opacity(deck.peek ? 0.38 : (m.isPlaying ? 0 : 0.3)))
                Image(systemName: m.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 3)
                    .opacity(deck.peek || !m.isPlaying ? 1 : 0).scaleEffect(deck.peek ? 1 : 0.6)
                // кольцо прогресса
                if m.duration > 0 {
                    Circle().trim(from: 0, to: min(1, m.position / max(m.duration, 1)))
                        .stroke(deckGrad, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(1.6)
                        .shadow(color: accent.opacity(0.8), radius: 2)
                }
            }
        }
        .frame(width: B, height: B)
        .clipShape(Circle())
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: deck.peek)
    }
}

/// Название трека, выезжающее капсулой слева от круга при наведении
struct BubbleLabel: View {
    let deck: DeckState
    var body: some View {
        let m = deck.media
        let b = deck.bubbleRect
        let show = deck.peek && !deck.isOpen && !m.title.isEmpty
        VStack(alignment: .trailing, spacing: 1) {
            Text(m.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            if !m.artist.isEmpty { Text(m.artist).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
        }
        .frame(maxWidth: 220, alignment: .trailing)
        .padding(.leading, 14).padding(.trailing, 30)
        .frame(height: 40)
        .background(Capsule().fill(.black.opacity(0.85))
            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.7)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        .fixedSize()
        .frame(width: 400, height: 40, alignment: .trailing)
        .offset(x: b.midX - 400 + (show ? 0 : 30), y: b.midY - 20)
        .opacity(show ? 1 : 0)
        .scaleEffect(show ? 1 : 0.92, anchor: .trailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: show)
        .allowsHitTesting(false)
    }
}

struct TopBar: View {
    @Bindable var deck: DeckState
    @Namespace private var ns
    var body: some View {
        let idx = (Tab.allCases.firstIndex(of: deck.tab) ?? 0) + 1
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { t in
                    TabIcon(tab: t, on: deck.tab == t && !deck.showSettings, ns: ns) { withAnimation(DS.spring) { deck.tab = t; deck.showSettings = false } }
                }
            }
            if Prefs.shared.showIndex || deck.showSettings {
                HairDivider(vertical: true).frame(height: 14).padding(.horizontal, 8)
                // моно-подпись «02 / БУФЕР»
                HStack(spacing: 5) {
                    Text(deck.showSettings ? "00" : String(format: "%02d", idx)).foregroundStyle(accent)
                        .contentTransition(.numericText(value: Double(deck.showSettings ? 0 : idx)))
                    Text("/").foregroundStyle(DS.text3)
                    Text(deck.showSettings ? "ВИД" : deck.tab.rawValue.uppercased()).foregroundStyle(DS.text2)
                }
                .font(ND.mono).tracking(1.3)
                .animation(DS.spring, value: deck.tab)
            }
            Spacer(minLength: 6)
            MiniNowPlaying(m: deck.media, deck: deck)
            GhostIcon(icon: deck.showSettings ? "checkmark" : "slider.horizontal.3", help: deck.showSettings ? "Готово" : "Внешний вид") {
                withAnimation(DS.spring) { deck.showSettings.toggle() }
            }
            GhostIcon(icon: "xmark", help: "Закрыть (Esc)") { AppDelegate.shared?.close() }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }
}

/// Вкладка: только иконка; активная — белая, под ней светится LED-штрих
struct TabIcon: View {
    let tab: Tab
    let on: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 11, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? DS.text : (hover ? DS.text2 : DS.text3))
                    .frame(height: 16)
                ZStack { if on { LEDDash(width: 10).matchedGeometryEffect(id: "tab", in: ns) } }.frame(height: 2)
            }
            .frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .help("\(tab.rawValue) — клавиша \((Tab.allCases.firstIndex(of: tab) ?? 0) + 1)")
        .onHover { h in withAnimation(DS.snappy) { hover = h } }
    }
}

struct MiniNowPlaying: View {
    let m: MediaController
    var deck: DeckState? = nil
    @State private var hover = false
    var body: some View {
        if m.isPlaying && !m.title.isEmpty && deck?.tab != .media {
            Button { withAnimation(DS.spring) { deck?.tab = .media } } label: {
                HStack(spacing: 5) {
                    if let art = m.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    } else {
                        Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(accent)
                    }
                    Text(m.title).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
                        .foregroundStyle(.white.opacity(hover ? 0.95 : 0.7))
                }
                .padding(.horizontal, 6).frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(hover ? 0.1 : 0)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScale()).help("Открыть плеер")
            .onHover { h in withAnimation(DS.snappy) { hover = h } }
            .transition(.opacity)
        }
    }
}

struct Pill: ViewModifier {
    var active = false
    @State private var hover = false
    func body(content: Content) -> some View {
        content.padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(active || hover ? DS.text : DS.text2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? ND.softHi : (hover ? ND.softHi : ND.soft)))
            .overlay(alignment: .bottom) { if active { LEDDash(width: 10).offset(y: 1) } }
            .onHover { h in withAnimation(DS.snappy) { hover = h } }
    }
}
extension View { func pill(_ active: Bool = false) -> some View { modifier(Pill(active: active)) } }

struct SmallButton: View {
    let icon: String
    var title: String?
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                if let title { Text(title).font(.system(size: 11, weight: .medium)) }
            }.pill(active)
        }.buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed ? 0.95 : 1).brightness(c.isPressed ? 0.06 : 0).animation(DS.snappy, value: c.isPressed)
    }
}

func fileIcon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }

// MARK: - Media

struct MediaTab: View {
    @Bindable var m: MediaController
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            backdrop
            if AppDelegate.shared?.deck.showRemote == true {
                RemoteSheet(shown: Binding(get: { AppDelegate.shared?.deck.showRemote ?? false },
                                           set: { AppDelegate.shared?.deck.showRemote = $0 }))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if m.source == nil { empty } else { player }
        }
        .animation(.easeInOut(duration: 0.4), value: m.source == nil)
    }

    // Едва заметное свечение обложки слева — без цветной карточки
    var backdrop: some View {
        ZStack {
            if let art = m.artBlur {
                Color.clear.overlay {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill).opacity(0.22)
                }.clipped()
                .mask(LinearGradient(colors: [.white, .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
            }
        }
        .allowsHitTesting(false)
    }

    func cover(_ side: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let art = m.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.3, weight: .semibold)).foregroundStyle(DS.text3)
            }
            // блик конверта
            LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .center)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.55), radius: 6, x: 2, y: 2)
        .onTapGesture { m.openSource() }
        .help("Открыть \(m.source ?? "")")
    }

    /// Конверт пластинки: при воспроизведении из него выезжает и крутится винил
    @ViewBuilder func medium(_ side: CGFloat) -> some View {
        switch Prefs.shared.medium {
        case "cassette": cassette(side)
        case "plain": cover(side).scaleEffect(m.isPlaying ? 1 : 0.94).animation(DS.spring, value: m.isPlaying)
        default: sleeve(side)
        }
    }

    /// Кассета: катушки крутятся, плёнка перематывается по ходу трека
    func cassette(_ side: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !m.isPlaying)) { ctx in
            Cassette(art: m.artwork, title: m.title, progress: m.duration > 0 ? min(1, m.livePosition(ctx.date) / m.duration) : 0.5,
                     angle: -ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2 * 360)
        }
        .frame(width: side * 1.42, height: side * 0.9)
        .onTapGesture { m.openSource() }
    }

    func sleeve(_ side: CGFloat) -> some View {
        let disc = side * 0.94
        return ZStack(alignment: .leading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !m.isPlaying)) { ctx in
                Vinyl(art: m.artwork, tint: m.tint)
                    .frame(width: disc, height: disc)
                    .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360))
            }
            .offset(x: m.isPlaying ? side * 0.42 : side * 0.06)
            cover(side)
        }
        .frame(width: side * 1.42, height: side, alignment: .leading)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: m.isPlaying)
    }

    var player: some View {
        GeometryReader { g in
            let side = max(56, min(90, g.size.height - 18))
            HStack(alignment: .center, spacing: 12) {
                medium(side)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 2)
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title.isEmpty ? "Без названия" : m.title).font(DS.font(14, .semibold)).lineLimit(1)
                            Text(m.artist.isEmpty ? (m.album.isEmpty ? " " : m.album) : m.artist).font(DS.font(11))
                                .foregroundStyle(DS.text2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        controls
                    }
                    Spacer(minLength: 2)
                    progress
                }
                .frame(maxWidth: .infinity, maxHeight: side, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    var header: some View {
        HStack(spacing: 5) {
            if let icon = m.sourceIcon { Image(nsImage: icon).resizable().frame(width: 12, height: 12) }
            Text((m.source ?? "").uppercased()).font(ND.mono).tracking(1.3)
                .foregroundStyle(DS.text3).lineLimit(1)
            if m.isPlaying { EqualizerBars().frame(width: 10, height: 8) }
            Spacer(minLength: 4)
            Image(systemName: m.volume < 1 ? "speaker.slash.fill" : (m.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                .font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.55)).frame(width: 13)
            ScrubBar(value: m.volume / 100) { m.setVolume($0 * 100) } commit: { m.setVolume($0 * 100) }.frame(width: 58)
                .help("Громкость \(Int(m.volume))%  ↑ ↓")
            remoteButton
        }
        .frame(height: 14)
    }

    @ViewBuilder var progress: some View {
        if m.duration > 0 {
            // Плавно, кадр за кадром — но только пока играет и никто не тянет ползунок
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !m.isPlaying || scrub != nil)) { ctx in
                bar(scrub ?? m.livePosition(ctx.date))
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 9, weight: .bold))
                Text(m.isPlaying ? "Трансляция" : "На паузе").font(DS.font(9.5, .semibold, rounded: true))
            }.foregroundStyle(.white.opacity(0.5))
        }
    }

    func bar(_ pos: Double) -> some View {
        HStack(spacing: 7) {
            Text(time(pos)).frame(width: 28, alignment: .leading)
            switch Prefs.shared.progress {
            case "wave": WaveScrub(value: pos / max(m.duration, 1), seed: m.title) { scrub = $0 * m.duration } commit: { m.seek($0 * m.duration); scrub = nil }
            case "line": ScrubBar(value: pos / max(m.duration, 1)) { scrub = $0 * m.duration } commit: { m.seek($0 * m.duration); scrub = nil }
            default: TickScrub(value: pos / max(m.duration, 1)) { scrub = $0 * m.duration } commit: { m.seek($0 * m.duration); scrub = nil }
            }
            Text(time(m.duration)).frame(width: 28, alignment: .trailing)
        }
        .font(.system(size: 8.5, weight: .medium, design: .monospaced)).foregroundStyle(DS.text3)
        .frame(height: 12)
    }

    var controls: some View {
        HStack(spacing: 0) {
            if m.duration > 0 { control("gobackward.15", 11) { m.skip(-15) }.help("Назад 15 с  ←") }
            control("backward.fill", 13) { m.command("previous track") }.help("Предыдущий трек")
            Button { m.command("playpause") } label: {
                Image(systemName: m.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black).frame(width: 30, height: 30)
                    .background(Circle().fill(.white))
                    .overlay(Circle().strokeBorder(accent.opacity(0.6), lineWidth: 1).padding(-3))
                    .shadow(color: accent.opacity(0.35), radius: 6)
                    .contentTransition(.symbolEffect(.replace))
            }.buttonStyle(PressScale()).padding(.horizontal, 3).help(m.isPlaying ? "Пауза  Пробел" : "Играть  Пробел")
            control("forward.fill", 13) { m.command("next track") }.help("Следующий трек")
            if m.duration > 0 { control("goforward.15", 11) { m.skip(15) }.help("Вперёд 15 с  →") }
        }
    }

    var empty: some View {
        HStack(spacing: 16) {
            ZStack {
                Vinyl(art: nil, tint: Color(white: 0.2)).frame(width: 84, height: 84)
                Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.text2)
            }
            VStack(alignment: .leading, spacing: 5) {
                DeckLabel(text: "Тишина")
                Text("Ничего не играет").font(DS.font(14, .semibold))
                Text("Spotify, Музыка, YouTube в браузере, VLC — управление появится здесь")
                    .font(DS.font(10.5)).foregroundStyle(DS.text2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    SmallButton(icon: "music.note", title: "Музыка") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                    if let spotify = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        SmallButton(icon: "dot.radiowaves.left.and.right", title: "Spotify") { NSWorkspace.shared.open(spotify) }
                    }
                    SmallButton(icon: "iphone", title: "Пульт") { withAnimation(DS.spring) { AppDelegate.shared?.deck.showRemote = true } }
                }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    var remoteButton: some View {
        Button { withAnimation(DS.spring) { AppDelegate.shared?.deck.showRemote = true } } label: {
            Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(RemoteServer.shared.enabled ? AnyShapeStyle(deckGrad) : AnyShapeStyle(Color.white.opacity(0.55)))
                .frame(width: 20, height: 18).contentShape(Rectangle())
        }.buttonStyle(PressScale()).help("Пульт для iPhone")
    }

    func control(_ icon: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        HoverIcon(icon: icon, size: size, action: action)
    }

    func time(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Кнопка-иконка: белеет и подрастает при наведении (как в Spotify)
struct HoverIcon: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.72))
                .frame(width: 24, height: 26).contentShape(Rectangle())
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(PressScale())
        .onHover { h in withAnimation(DS.snappy) { hover = h } }
    }
}

/// Тонкая полоса как в Spotify: при наведении толще, заливка цветная и появляется ползунок
struct ScrubBar: View {
    let value: Double
    let change: (Double) -> Void
    let commit: (Double) -> Void
    @State private var hover = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = min(max(value, 0), 1)
            let active = hover || dragging
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: active ? 5 : 3.5)
                Capsule().fill(active ? AnyShapeStyle(deckGrad) : AnyShapeStyle(Color.white))
                    .frame(width: max(active ? 5 : 3.5, w * v), height: active ? 5 : 3.5)
                Circle().fill(.white).frame(width: 11, height: 11).shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: w * v - 5.5).opacity(active ? 1 : 0).scaleEffect(active ? 1 : 0.4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in dragging = true; change(min(max(e.location.x / w, 0), 1)) }
                .onEnded { e in dragging = false; commit(min(max(e.location.x / w, 0), 1)) })
            .onHover { h in withAnimation(DS.snappy) { hover = h } }
            .animation(DS.snappy, value: active)
        }
        .frame(height: 14)
    }
}

/// Пляшущие столбики «играет»
struct EqualizerBars: View {
    static let green = Color(red: 0.12, green: 0.84, blue: 0.38)
    static func level(_ t: Double, _ i: Int) -> CGFloat {
        let k = Double(i)
        return CGFloat(0.35 + 0.65 * abs(sin(t * (5.1 + k * 1.7) + k * 1.3)))
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { tl in
            bars(tl.date.timeIntervalSinceReferenceDate)
        }
    }
    func bars(_ t: Double) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(accent).frame(width: 2.4)
                    .scaleEffect(x: 1, y: Self.level(t, i), anchor: .bottom)
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    let store: ClipboardStore
    @State private var query = ""

    var filtered: [ClipItem] {
        let base = store.items.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
        guard !query.isEmpty else { return base }
        return base.filter { $0.preview.localizedCaseInsensitiveContains(query) || ($0.sourceApp ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text3)
                TextField("", text: $query, prompt: Text("Поиск по истории…").foregroundStyle(DS.text3)).textFieldStyle(.plain).font(DS.font(12))
                Text(String(format: "%03d", store.items.count)).font(ND.mono).tracking(1).foregroundStyle(DS.text3)
                Button { store.clear() } label: { Image(systemName: "trash").font(.system(size: 10.5)).foregroundStyle(DS.text2) }
                    .buttonStyle(PressScale()).help("Очистить историю")
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ND.soft))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { item in ClipRow(item: item, store: store) }
                }
            }
            if store.items.isEmpty {
                Text("Скопируйте что-нибудь — история появится здесь. Пароли из менеджеров не сохраняются.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).frame(maxHeight: .infinity)
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let store: ClipboardStore
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            if let img = store.image(item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 34, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let hex = colorHex {
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: hex)).frame(width: 22, height: 22)
            } else {
                Image(systemName: item.kindIcon).font(.system(size: 10.5, weight: .medium)).foregroundStyle(hover ? accent : DS.text3)
                    .frame(width: 22, height: 22)
            }
            Text(item.preview.replacingOccurrences(of: "\n", with: " ⏎ ")).font(.system(size: 12, design: item.kindIcon == "curlybraces" || item.kindIcon == "terminal" ? .monospaced : .default))
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            if store.flash == item.id {
                Text("Скопировано").font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
            } else if hover {
                if item.kindIcon == "link", let t = item.text, let u = URL(string: t.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    icon("safari") { NSWorkspace.shared.open(u) }
                }
                icon(item.pinned ? "pin.slash" : "pin") { store.togglePin(item) }
                icon("xmark") { store.remove(item) }
            } else {
                if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(accent) }
                Text(item.sourceApp ?? "").font(.system(size: 10)).foregroundStyle(DS.text3).lineLimit(1)
                Text(item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))).font(.system(size: 9, design: .monospaced)).foregroundStyle(DS.text3)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? ND.soft : .clear))
        .overlay(alignment: .leading) {   // LED-метка у строки под курсором
            Capsule().fill(accent).frame(width: 2, height: hover ? 12 : 0).shadow(color: accent.opacity(0.8), radius: 2).offset(x: -1)
        }
        .animation(DS.snappy, value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.copy(item) }
        .onDrag {
            if let t = item.text { return NSItemProvider(object: t as NSString) }
            if let f = item.files?.first { return NSItemProvider(contentsOf: URL(fileURLWithPath: f)) ?? NSItemProvider() }
            if let f = item.imageFile { return NSItemProvider(contentsOf: store.imgDir.appendingPathComponent(f)) ?? NSItemProvider() }
            return NSItemProvider()
        }
    }

    var colorHex: String? {
        guard item.kindIcon == "paintpalette", let t = item.text else { return nil }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func icon(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 11)).frame(width: 20, height: 18).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
    }
}

extension Color {
    init(hex: String) {
        let h = hex.replacingOccurrences(of: "#", with: "")
        let v = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: - Shelf

struct ShelfTab: View {
    let store: ShelfStore
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DeckLabel(text: store.urls.isEmpty ? "Полка" : "Полка · \(store.urls.count)")
                Spacer()
                if !store.urls.isEmpty {
                    GhostIcon(icon: "airplayaudio", help: "AirDrop") { store.airdrop() }
                    GhostIcon(icon: "folder", help: "Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting(store.urls) }
                    GhostIcon(icon: "trash", help: "Очистить") { store.clear() }
                }
            }
            ZStack {
                // уголки видоискателя; при перетаскивании — сходятся и загораются
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(targeted ? accent.opacity(0.07) : Color.clear)
                CornerBrackets(len: targeted ? 22 : 14)
                    .stroke(targeted ? accent : Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: targeted ? accent.opacity(0.7) : .clear, radius: 4)
                    .padding(targeted ? 4 : 0)
                    .animation(DS.spring, value: targeted)
                if store.urls.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 16, weight: .medium)).foregroundStyle(targeted ? accent : DS.text3)
                            .symbolEffect(.bounce, value: targeted)
                        Text("Брось файлы сюда — заберёшь потом").font(DS.font(11.5)).foregroundStyle(DS.text2)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(store.urls, id: \.self) { u in ShelfItem(url: u, store: store) }
                        }.padding(8)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { store.add([url]) } }
                    }
                }
                return true
            }
        }
    }
}

struct ShelfItem: View {
    let url: URL
    let store: ShelfStore
    @State private var hover = false
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: fileIcon(url.path)).resizable().frame(width: 36, height: 36)
            Text(url.lastPathComponent).font(.system(size: 9)).lineLimit(1).truncationMode(.middle).frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? ND.soft : .clear))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { store.remove(url) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            }
        }
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Открыть") { NSWorkspace.shared.open(url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Скопировать путь") { copyToPasteboard(url.path) }
            Button("Убрать с полки") { store.remove(url) }
        }
    }
}

// MARK: - Launcher

struct LauncherTab: View {
    let store: LauncherStore
    @State private var targeted = false
    let cols = [GridItem(.adaptive(minimum: 66), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DeckLabel(text: "Закреплённые")
                    Spacer()
                    GhostIcon(icon: "plus", help: "Добавить приложение или папку") { addViaPanel() }
                }
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(store.pinned, id: \.self) { p in LaunchTile(path: p, store: store, pinned: true) }
                }
                if !store.frequent.isEmpty {
                    DeckLabel(text: "Часто используемые").padding(.top, 4)
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(store.frequent, id: \.self) { p in LaunchTile(path: p, store: store, pinned: false) }
                    }
                }
            }
        }
        .overlay { if targeted { CornerBrackets(len: 20).stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).shadow(color: accent.opacity(0.7), radius: 4) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { store.add([url]) } } }
            }
            return true
        }
    }

    func addViaPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK { store.add(p.urls) }
    }
}

struct LaunchTile: View {
    let path: String
    let store: LauncherStore
    let pinned: Bool
    @State private var hover = false

    var name: String {
        let n = (path as NSString).lastPathComponent
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: fileIcon(path)).resizable().frame(width: 32, height: 32)
            Text(name).font(DS.font(10, .medium)).foregroundStyle(hover ? DS.text : DS.text2).lineLimit(1).truncationMode(.middle).padding(.horizontal, 3)
        }
        .frame(width: 66, height: 56)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? ND.soft : .clear))
        .overlay(alignment: .bottom) { if hover { LEDDash(width: 10).offset(y: 1) } }
        .scaleEffect(hover ? 1.04 : 1)
        .animation(DS.spring, value: hover)
        .onHover { hover = $0 }
        .onTapGesture { store.open(path); AppDelegate.shared?.close() }
        .contextMenu {
            Button("Открыть") { store.open(path) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            if LauncherStore.isFolder(path) {
                Button("Открыть в Терминале") { LauncherStore.openFolder(path, with: "com.apple.Terminal") }
                Button("Открыть в VS Code") { LauncherStore.openFolder(path, with: "com.microsoft.VSCode") }
                Button("Открыть в Cursor") { LauncherStore.openFolder(path, with: "com.todesktop.230313mzl4w4u92") }
            }
            Button("Скопировать путь") { copyToPasteboard(path) }
            Divider()
            if pinned {
                Button("Сдвинуть влево") { store.move(path, by: -1) }
                Button("Сдвинуть вправо") { store.move(path, by: 1) }
                Button("Открепить") { store.remove(path) }
            } else {
                Button("Закрепить") { store.add([URL(fileURLWithPath: path)]) }
            }
        }
    }
}

// MARK: - HUD громкости и яркости

/// Значок громкости/яркости, плавно меняющийся при смене уровня
struct HUDIcon: View {
    let hud: HUDController
    var size: CGFloat
    var body: some View {
        Image(systemName: hud.icon)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(hud.kind == .volume && hud.muted ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(deckGrad))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: hud.pulse)
    }
}

struct HUDPercent: View {
    let hud: HUDController
    var size: CGFloat
    var body: some View {
        Text("\(Int((hud.shownLevel * 100).rounded()))")
            .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText(value: hud.shownLevel))
            .foregroundStyle(.white.opacity(0.9))
    }
}

/// Полоска уровня с подсветкой
struct HUDBar: View {
    let hud: HUDController
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(deckGrad)
                    .frame(width: max(hud.shownLevel > 0 ? height : 0, g.size.width * hud.shownLevel))
                    .shadow(color: accent.opacity(0.8), radius: 3)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Островок вверху: значок — полоса — проценты
struct IslandHUD: View {
    let deck: DeckState
    var body: some View {
        let hud = deck.hud
        HStack(spacing: 8) {
            HUDIcon(hud: hud, size: 11).frame(width: 18)
            if deck.solo && deck.hasNotch { Spacer(minLength: deck.notchWidth) }
            HUDBar(hud: hud).frame(height: deck.islandHeight)
            HUDPercent(hud: hud, size: 10.5).frame(width: 24, alignment: .trailing)
        }
        .padding(.leading, deck.hiddenPart + (deck.solo ? 12 : 6))
        .padding(.trailing, deck.solo ? 12 : 10)
        .frame(height: deck.islandHeight)
    }
}

/// Круг в углу: уровень заполняет кольцо по краю
struct BubbleHUD: View {
    let hud: HUDController
    var body: some View {
        let lw: CGFloat = 3.6
        ZStack {
            Circle().fill(.black)
            Circle().fill(RadialGradient(colors: [accent.opacity(0.28 * hud.shownLevel + 0.06), .clear],
                                         center: .center, startRadius: 0, endRadius: DeckState.bubble / 2))
            Circle().stroke(.white.opacity(0.12), lineWidth: lw).padding(lw / 2 + 1)
            Circle().trim(from: 0, to: hud.shownLevel)
                .stroke(AngularGradient(colors: [accentB, accent, accentB], center: .center),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lw / 2 + 1)
                .shadow(color: accent.opacity(0.9), radius: 3)
            VStack(spacing: 0) {
                HUDIcon(hud: hud, size: 14)
                HUDPercent(hud: hud, size: 9.5)
            }
        }
        .clipShape(Circle())
    }
}

/// При раскрытой панели — капсула снизу
struct PanelHUD: View {
    let hud: HUDController
    var body: some View {
        HStack(spacing: 10) {
            HUDIcon(hud: hud, size: 12).frame(width: 18)
            HUDBar(hud: hud, height: 5).frame(width: 150, height: 14)
            HUDPercent(hud: hud, size: 11).frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 14).frame(height: 32)
        .background(Capsule().fill(.black.opacity(0.9))
            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.7)))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
    }
}
