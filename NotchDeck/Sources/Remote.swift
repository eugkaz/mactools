import AppKit
import SwiftUI
import Network
import SystemConfiguration
import CoreImage

/// Пульт для iPhone: маленький HTTP-сервер только в домашней сети.
/// Страница-пульт открывается в Safari по QR-коду (в нём секретный ключ), её можно добавить на «Домой».
/// Изменения отдаются «долгим опросом»: запрос висит, пока что-то не поменяется, — мгновенно и без нагрузки.
final class RemoteServer {
    static let shared = RemoteServer()
    static let port: UInt16 = 47800

    weak var media: MediaController?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "nd.remote")
    private var waiters: [(NWConnection, Int)] = []     // соединения, ждущие изменений (+ версия, с которой ждут)
    private(set) var version = 1
    private var volCache: (Double, Date) = (50, .distantPast)

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "remoteOn") }
        set { UserDefaults.standard.set(newValue, forKey: "remoteOn"); newValue ? start() : stop() }
    }

    var token: String {
        if let t = UserDefaults.standard.string(forKey: "remoteKey"), !t.isEmpty { return t }
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let t = String((0..<10).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(t, forKey: "remoteKey")
        return t
    }

    /// Новый ключ — старые телефоны отключатся
    func resetToken() { UserDefaults.standard.removeObject(forKey: "remoteKey"); _ = token }

    var hostName: String {
        if let n = SCDynamicStoreCopyLocalHostName(nil) as String? { return n + ".local" }
        return "localhost"
    }

    var ip: String? {
        var addr: String?
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0 else { return nil }
        defer { freeifaddrs(ifa) }
        var p = ifa
        while let cur = p {
            let i = cur.pointee
            if i.ifa_addr.pointee.sa_family == UInt8(AF_INET), let name = String(validatingUTF8: i.ifa_name), name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(i.ifa_addr, socklen_t(i.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let s = String(cString: host)
                if !s.hasPrefix("169.254") { addr = s; if name == "en0" { break } }
            }
            p = i.ifa_next
        }
        return addr
    }

    /// Имя Mac в сети (.local) не меняется, в отличие от IP, — ярлык на «Домой» не сломается
    var url: String { "http://\(hostName):\(Self.port)/?k=\(token)" }

    func start() {
        guard listener == nil else { return }
        _ = RemotePage.icon                            // иконку рисуем заранее, на главном потоке
        _ = token
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi           // только домашняя сеть (Wi-Fi), не наружу
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!) else { return }
        l.service = NWListener.Service(name: "NotchDeck", type: "_http._tcp")
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.queue.async { self?.listener?.cancel(); self?.listener = nil } }
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        queue.async {
            self.listener?.cancel(); self.listener = nil
            self.waiters.forEach { $0.0.cancel() }; self.waiters.removeAll()
        }
    }

    /// Что-то поменялось (трек, пауза, обложка, громкость) — будим ждущих
    func changed() {
        queue.async {
            self.version += 1
            let w = self.waiters; self.waiters.removeAll()
            for (c, _) in w { self.sendState(c) }
        }
    }

    // MARK: HTTP

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8),
                  let line = req.split(separator: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { c.cancel(); return }
            self.route(c, method: String(parts[0]), target: String(parts[1]))
        }
    }

    private func route(_ c: NWConnection, method: String, target: String) {
        let comps = URLComponents(string: target)
        let path = comps?.path ?? "/"
        var q: [String: String] = [:]
        comps?.queryItems?.forEach { q[$0.name] = $0.value ?? "" }
        // Страница и иконка открыты (в них нет данных), всё остальное — только с ключом
        switch path {
        case "/": return send(c, 200, "text/html; charset=utf-8", Data(RemotePage.html.utf8))
        case "/icon.png": return send(c, 200, "image/png", RemotePage.icon)
        case "/manifest.json": return send(c, 200, "application/manifest+json", Data(RemotePage.manifest.utf8))
        default: break
        }
        guard q["k"] == token else { return send(c, 403, "text/plain", Data("forbidden".utf8)) }
        switch path {
        case "/state":
            let since = Int(q["v"] ?? "") ?? 0
            if since >= version {
                waiters.append((c, since))
                // не дольше 25 с — потом отдаём как есть (страница сразу переспросит)
                queue.asyncAfter(deadline: .now() + 25) { [weak self] in
                    guard let self, let i = self.waiters.firstIndex(where: { $0.0 === c }) else { return }
                    self.waiters.remove(at: i); self.sendState(c)
                }
            } else { sendState(c) }
        case "/art":
            DispatchQueue.main.async {
                let d = self.media?.artData
                self.queue.async { d.map { self.send(c, 200, "image/jpeg", $0, cache: true) } ?? self.send(c, 404, "text/plain", Data()) }
            }
        case "/cmd":
            let a = q["a"] ?? ""
            DispatchQueue.main.async {
                guard let m = self.media else { return }
                switch a {
                case "toggle": m.command("playpause")
                case "next": m.command("next track")
                case "prev": m.command("previous track")
                case "seek": if let t = Double(q["t"] ?? "") { m.seek(t) }
                case "skip": if let d = Double(q["d"] ?? "") { m.skip(d) }
                case "vol": if let v = Double(q["v"] ?? "") { m.setVolume(max(0, min(100, v))) }
                default: break
                }
                self.changed()
            }
            send(c, 200, "application/json", Data("{\"ok\":true}".utf8))
        default:
            send(c, 404, "text/plain", Data("not found".utf8))
        }
    }

    private func sendState(_ c: NWConnection) {
        let v = version
        DispatchQueue.main.async {
            guard let m = self.media else { return }
            // громкость читаем не чаще раза в 2 с (AppleScript)
            if Date().timeIntervalSince(self.volCache.1) > 2,
               let vol = AppleScript.run("output volume of (get volume settings)")?.int32Value {
                self.volCache = (Double(vol), Date()); m.volume = Double(vol)
            }
            let th = Theme.shared
            let o: [String: Any] = [
                "v": v, "app": m.source ?? "", "title": m.title, "artist": m.artist, "album": m.album,
                "playing": m.isPlaying, "duration": m.duration, "position": m.livePosition(Date()),
                "volume": self.volCache.0, "art": m.artKey,
                "a": th.a.hex, "b": th.b.hex, "bg": th.bg?.hex ?? "#1b2a4a",
                "ca": th.ca.hex, "cb": th.cb.hex, "cbg": th.cbg?.hex ?? "#1b2a4a",
                "ui": Prefs.shared.json,
            ]
            let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
            self.queue.async { self.send(c, 200, "application/json", d) }
        }
    }

    private func send(_ c: NWConnection, _ code: Int, _ type: String, _ body: Data, cache: Bool = false) {
        let status = code == 200 ? "OK" : (code == 403 ? "Forbidden" : "Not Found")
        let head = "HTTP/1.1 \(code) \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + (cache ? "Cache-Control: max-age=86400\r\n" : "Cache-Control: no-store\r\n")
            + "Connection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    /// QR-код ссылки (с ключом) — для панели
    func qr(size: CGFloat) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(url.utf8), "inputCorrectionLevel": "M"]),
              let out = f.outputImage else { return nil }
        let k = size / out.extent.width * 2
        let scaled = out.transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}

extension Color {
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#4a6cff" }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - Окно «Пульт для iPhone» внутри панели

struct RemoteSheet: View {
    @Binding var shown: Bool
    @State private var on = RemoteServer.shared.enabled
    @State private var qr: NSImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white)
                if on, let qr { Image(nsImage: qr).interpolation(.none).resizable().padding(5) }
                else { Image(systemName: "iphone.slash").font(.system(size: 26)).foregroundStyle(.black.opacity(0.35)) }
            }
            .frame(width: 92, height: 92)
            .shadow(color: accent.opacity(0.4), radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Пульт для iPhone").font(DS.font(14, .bold))
                    Spacer()
                    Toggle("", isOn: $on).toggleStyle(GlowToggleStyle(accent: deckAccent)).labelsHidden()
                        .onChange(of: on) { _, v in RemoteServer.shared.enabled = v; refresh() }
                    Button { withAnimation(DS.spring) { shown = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                            .frame(width: 20, height: 20).background(Circle().fill(.white.opacity(0.08)))
                    }.buttonStyle(PressScale())
                }
                Text(on ? "Наведите камеру iPhone на код. Потом «Поделиться» → «На экран Домой» — будет как приложение."
                        : "Включите — и управляйте музыкой на Mac с iPhone в той же Wi-Fi сети.")
                    .font(DS.font(10.5)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                if on {
                    HStack(spacing: 6) {
                        Text(RemoteServer.shared.url.replacingOccurrences(of: "http://", with: ""))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Новый ключ") { RemoteServer.shared.resetToken(); refresh() }
                            .buttonStyle(.plain).font(DS.font(9.5, .semibold)).foregroundStyle(accent)
                            .help("Отключить все телефоны и выдать новый код")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .onAppear(perform: refresh)
    }

    func refresh() { qr = on ? RemoteServer.shared.qr(size: 160) : nil }
}
