import AppKit
import CryptoKit

enum Outcome { case close, keep, setQuery(String) }

struct Cmd: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String = "command"
    var icon: NSImage? = nil
    var hint: String = ""
    var keywords: String = ""
    var tint: String = "accent"
    var score: Double = 0
    var run: @MainActor () -> Outcome
    var alt: (@MainActor () -> Outcome)? = nil      // ⌘↵
    var altHint: String = ""
}

struct Snippet: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var text: String }

@MainActor
enum Snippets {
    static var all: [Snippet] {
        get { (UserDefaults.standard.data(forKey: "snippets").flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) }) ?? defaults }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "snippets") }
    }
    static let defaults = [
        Snippet(name: "Подпись", text: "С уважением,\n"),
        Snippet(name: "Сегодняшняя дата", text: "{date}"),
        Snippet(name: "Shebang bash", text: "#!/usr/bin/env bash\nset -euo pipefail\n"),
        Snippet(name: "console.log", text: "console.log('🔥', );"),
    ]
    static func expand(_ t: String) -> String {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        return t.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
            .replacingOccurrences(of: "{time}", with: tf.string(from: Date()))
            .replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
            .replacingOccurrences(of: "{uuid}", with: UUID().uuidString.lowercased())
    }
}

@MainActor
enum Actions {
    static func copy(_ s: String, _ label: String? = nil) -> Outcome {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        Toast.show("📋 " + (label ?? "Скопировано: " + String(s.prefix(40)).replacingOccurrences(of: "\n", with: " ")))
        return .close
    }
    /// Вставить текст в приложение, которое было активно до палитры
    static func paste(_ s: String) -> Outcome {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)
        pb.clearContents(); pb.setString(s, forType: .string)
        guard AX.trusted else { Toast.show("📋 Скопировано (для автовставки дай доступ в Универсальном доступе)"); return .close }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let d = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true); d?.flags = .maskCommand
            let u = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false); u?.flags = .maskCommand
            d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let old { pb.clearContents(); pb.setString(old, forType: .string) }
            }
        }
        return .close
    }
    static func open(_ url: String) -> Outcome {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        return .close
    }
    nonisolated static func sh(_ cmd: String) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", cmd]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static var clipboard: String { NSPasteboard.general.string(forType: .string) ?? "" }
}

// MARK: - Индексы

@MainActor
final class Index {
    static let shared = Index()
    struct AppEntry { let name: String; let url: URL }
    private(set) var apps: [AppEntry] = []
    private(set) var repos: [URL] = []
    private var icons: [URL: NSImage] = [:]

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var found: [AppEntry] = []
            let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                        NSHomeDirectory() + "/Applications"]
            for d in dirs {
                for n in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where n.hasSuffix(".app") {
                    found.append(AppEntry(name: String(n.dropLast(4)), url: URL(fileURLWithPath: d).appendingPathComponent(n)))
                }
            }
            // git-репозитории в типичных местах (глубина 3)
            var repos: [URL] = []
            let home = URL(fileURLWithPath: NSHomeDirectory())
            for base in ["Developer", "Projects", "projects", "dev", "code", "Code", "Documents", "Desktop", "GitHub", "src"] {
                let root = home.appendingPathComponent(base)
                Self.findRepos(root, depth: 0, into: &repos)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apps = found; self.repos = Array(Set(repos)).sorted { $0.path < $1.path } }
            }
        }
    }
    nonisolated private static func findRepos(_ u: URL, depth: Int, into out: inout [URL]) {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.appendingPathComponent(".git").path) { out.append(u); return }
        guard depth < 3, let kids = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for k in kids where (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let n = k.lastPathComponent
            if ["node_modules", "build", "dist", ".build", "Pods", "venv", "DerivedData", "Library"].contains(n) { continue }
            findRepos(k, depth: depth + 1, into: &out)
        }
    }
    func icon(_ url: URL) -> NSImage {
        if let i = icons[url] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path); i.size = NSSize(width: 32, height: 32)
        icons[url] = i; return i
    }
    var editor: URL? {
        for b in ["com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "dev.zed.Zed", "com.exafunction.windsurf", "com.apple.dt.Xcode"] {
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) { return u }
        }
        return nil
    }
}

// MARK: - Сборка списка

@MainActor
enum Catalog {
    static func usage(_ id: String) -> Double { UserDefaults.standard.double(forKey: "use." + id) }
    static func used(_ id: String) { UserDefaults.standard.set(usage(id) + 1, forKey: "use." + id) }

    static func results(_ raw: String) -> [Cmd] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        var out = dynamic(q)
        var pool = staticCommands()
        pool += Index.shared.apps.map { a in
            Cmd(id: "app." + a.url.path, title: a.name, subtitle: "Приложение", icon: Index.shared.icon(a.url), hint: "открыть",
                run: { NSWorkspace.shared.open(a.url); return .close },
                alt: { NSWorkspace.shared.activateFileViewerSelecting([a.url]); return .close }, altHint: "в Finder")
        }
        if q.isEmpty {
            // пусто: самые используемые + подсказки
            let top = pool.filter { usage($0.id) > 0 }.sorted { usage($0.id) > usage($1.id) }.prefix(6)
            let tips = pool.filter { $0.id.hasPrefix("tip.") || ["focus.start", "win.leftHalf", "win.rightHalf", "win.maximize", "report"].contains($0.id) }
            var seen = Set<String>()
            return (Array(top) + tips).filter { seen.insert($0.id).inserted }
        }
        for var c in pool {
            let s = match(q, c.title + " " + c.keywords)
            guard s > 0 else { continue }
            c.score = s + min(usage(c.id), 20) * 0.6
            out.append(c)
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(40))
    }

    /// Нечёткое совпадение: начало > начало слова > подстрока > подпоследовательность
    static func match(_ q: String, _ text: String) -> Double {
        let q = q.lowercased(), t = text.lowercased()
        if t.hasPrefix(q) { return 100 - Double(t.count) * 0.05 }
        if t.contains(" " + q) || t.contains("." + q) || t.contains("-" + q) { return 80 }
        if t.contains(q) { return 60 }
        // транслитерация раскладки: «ыфафкш» → «safari»
        let flipped = Layout.flip(q)
        if flipped != q, t.hasPrefix(flipped) || t.contains(" " + flipped) { return 70 }
        var it = t.makeIterator(); var hits = 0
        for ch in q { while let c = it.next() { if c == ch { hits += 1; break } } }
        return hits == q.count && q.count >= 2 ? 30 : 0
    }

    // MARK: постоянные команды
    static func staticCommands() -> [Cmd] {
        var c: [Cmd] = []
        // окна
        for a in WinAction.allCases {
            c.append(Cmd(id: "win." + a.rawValue, title: "Окно: " + a.title, subtitle: "Окна", symbol: a.symbol, hint: a.hotkeyLabel,
                         keywords: "window окно snap", tint: "blue",
                         run: { WindowManager.shared.perform(a); return .close }))
        }
        for l in Layouts.all {
            c.append(Cmd(id: "layout." + l.name, title: "Набор окон: " + l.name, subtitle: "\(l.items.count) приложений", symbol: "square.grid.2x2.fill",
                         keywords: "layout набор workspace", tint: "blue", run: { Layouts.apply(l); return .close }))
        }
        c.append(Cmd(id: "layout.save", title: "Сохранить текущие окна как набор…", subtitle: "Окна", symbol: "square.and.arrow.down",
                     keywords: "layout набор save сохранить", tint: "blue", run: { .setQuery("save ") }))
        // фокус
        let ft = FocusTracker.shared
        if ft.phase == .idle {
            c.append(Cmd(id: "focus.start", title: "Начать фокус \(ft.focusMin) мин", subtitle: "Блокирует отвлекающие сайты и приложения",
                         symbol: "target", hint: "⌃⌥P", keywords: "focus pomodoro помидор фокус работа", tint: "orange",
                         run: { ft.startFocus(); return .close }))
        } else {
            c.append(Cmd(id: "focus.stop", title: "Остановить \(ft.phase == .focus ? "фокус" : "перерыв") (\(ft.remaining))",
                         symbol: "stop.circle", keywords: "focus stop стоп фокус", tint: "orange", run: { ft.stop(); return .close }))
        }
        c.append(Cmd(id: "report", title: "Отчёт за день", subtitle: summaryLine(), symbol: "chart.bar.xaxis",
                     keywords: "report stats статистика время отчёт", tint: "orange", run: { ReportWindow.show(); return .close }))
        // разработчику
        c.append(Cmd(id: "tip.port", title: "Освободить порт…", subtitle: "напиши: port 3000", symbol: "network",
                     keywords: "port порт kill lsof", tint: "red", run: { .setQuery("port ") }))
        c.append(Cmd(id: "uuid", title: "UUID", subtitle: "сгенерировать и скопировать", symbol: "number", keywords: "uuid guid id",
                     run: { Actions.copy(UUID().uuidString.lowercased()) }))
        c.append(Cmd(id: "ts", title: "Unix-время сейчас", subtitle: "\(Int(Date().timeIntervalSince1970))", symbol: "clock",
                     keywords: "timestamp unix время ts epoch", run: { Actions.copy("\(Int(Date().timeIntervalSince1970))") }))
        c.append(Cmd(id: "json", title: "Форматировать JSON из буфера", symbol: "curlybraces", keywords: "json pretty format",
                     run: { jsonFormat(Actions.clipboard, pretty: true) }))
        c.append(Cmd(id: "jsonmin", title: "Сжать JSON из буфера", symbol: "curlybraces", keywords: "json minify min",
                     run: { jsonFormat(Actions.clipboard, pretty: false) }))
        c.append(Cmd(id: "b64", title: "Base64: закодировать буфер", symbol: "lock.doc", keywords: "base64 b64 encode",
                     run: { Actions.copy(Data(Actions.clipboard.utf8).base64EncodedString()) }))
        c.append(Cmd(id: "b64d", title: "Base64: раскодировать буфер", symbol: "lock.open", keywords: "base64 b64d decode",
                     run: { b64decode(Actions.clipboard) }))
        c.append(Cmd(id: "ip", title: "Мой IP-адрес", subtitle: localIP(), symbol: "wifi", keywords: "ip адрес network сеть",
                     run: { Actions.copy(localIP()) },
                     alt: { let (_, o) = Actions.sh("curl -s --max-time 4 https://api.ipify.org"); return Actions.copy(o, "Внешний IP: " + o) },
                     altHint: "внешний"))
        c.append(Cmd(id: "lorem", title: "Lorem ipsum", symbol: "text.alignleft", keywords: "lorem текст рыба",
                     run: { Actions.paste("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.") }))
        // репозитории
        let ed = Index.shared.editor
        for r in Index.shared.repos {
            c.append(Cmd(id: "repo." + r.path, title: r.lastPathComponent, subtitle: (r.path as NSString).abbreviatingWithTildeInPath,
                         symbol: "chevron.left.forwardslash.chevron.right", hint: ed.map { "в " + $0.deletingPathExtension().lastPathComponent } ?? "в Finder",
                         keywords: "repo git проект", tint: "green",
                         run: { if let ed { NSWorkspace.shared.open([r], withApplicationAt: ed, configuration: NSWorkspace.OpenConfiguration()) } else { NSWorkspace.shared.open(r) }; return .close },
                         alt: { .setQuery("git " + r.lastPathComponent) }, altHint: "ветки"))
        }
        // сниппеты
        for s in Snippets.all {
            c.append(Cmd(id: "snip." + s.id.uuidString, title: s.name, subtitle: "Сниппет · " + s.text.prefix(50).replacingOccurrences(of: "\n", with: " ⏎ "),
                         symbol: "text.quote", hint: "вставить", keywords: "snippet сниппет", tint: "pink",
                         run: { Actions.paste(Snippets.expand(s.text)) }, alt: { Actions.copy(Snippets.expand(s.text)) }, altHint: "копировать"))
        }
        // скрипты пользователя
        for s in Scripts.list() {
            c.append(Cmd(id: "script." + s.lastPathComponent, title: s.deletingPathExtension().lastPathComponent, subtitle: "Скрипт",
                         symbol: "terminal", hint: "запустить", keywords: "script скрипт run", tint: "green",
                         run: { Scripts.run(s); return .close }))
        }
        // система
        let sys: [(String, String, String, String, () -> Outcome)] = [
            ("sys.lock", "Заблокировать экран", "lock.fill", "lock блок", { lockScreen(); return .close }),
            ("sys.displaysleep", "Выключить экран", "display", "sleep display экран", { _ = Actions.sh("pmset displaysleepnow"); return .close }),
            ("sys.dark", "Тёмная / светлая тема", "circle.lefthalf.filled", "dark mode тема", {
                var e: NSDictionary?
                NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")?.executeAndReturnError(&e)
                return .close }),
            ("sys.hidden", "Показать/скрыть скрытые файлы", "eye", "hidden файлы finder", {
                let (_, v) = Actions.sh("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null")
                _ = Actions.sh("defaults write com.apple.finder AppleShowAllFiles -bool \(v == "1" || v.lowercased() == "true" ? "false" : "true"); killall Finder")
                return .close }),
            ("sys.dock", "Перезапустить Dock", "dock.rectangle", "dock", { _ = Actions.sh("killall Dock"); return .close }),
            ("sys.dns", "Сбросить кэш DNS", "network.badge.shield.half.filled", "dns flush", {
                var e: NSDictionary?
                NSAppleScript(source: "do shell script \"dscacheutil -flushcache; killall -HUP mDNSResponder\" with administrator privileges")?.executeAndReturnError(&e)
                Toast.show("DNS сброшен"); return .close }),
            ("sys.settings", "Настройки Orbit", "gearshape", "settings настройки", { SettingsWindow.show(); return .close }),
        ]
        for s in sys { c.append(Cmd(id: s.0, title: s.1, subtitle: "Система", symbol: s.2, keywords: s.3, tint: "gray", run: s.4)) }
        return c
    }

    // MARK: команды из ввода
    static func dynamic(_ q: String) -> [Cmd] {
        var out: [Cmd] = []
        let lower = q.lowercased()
        func arg(_ prefix: String) -> String? {
            guard lower.hasPrefix(prefix + " ") else { return nil }
            return String(q.dropFirst(prefix.count + 1))
        }
        // калькулятор
        if let v = Calc.eval(q) {
            let s = Calc.format(v)
            out.append(Cmd(id: "calc", title: "= " + s, subtitle: q, symbol: "plusminus", hint: "копировать", tint: "green", score: 1000,
                           run: { Actions.copy(s) }))
        }
        // порт
        if let p = arg("port") ?? (lower.hasPrefix(":") ? String(q.dropFirst()) : nil), let port = Int(p.trimmingCharacters(in: .whitespaces)) {
            let (_, o) = Actions.sh("lsof -nP -iTCP:\(port) -sTCP:LISTEN -Fpc")
            var pid = "", name = ""
            for l in o.split(separator: "\n") {
                if l.hasPrefix("p"), pid.isEmpty { pid = String(l.dropFirst()) }
                if l.hasPrefix("c"), name.isEmpty { name = String(l.dropFirst()) }
            }
            if pid.isEmpty {
                out.append(Cmd(id: "port.free", title: "Порт \(port) свободен", symbol: "checkmark.circle", tint: "green", score: 1000, run: { .keep }))
            } else {
                out.append(Cmd(id: "port.kill", title: "Освободить порт \(port)", subtitle: "\(name) · pid \(pid)", symbol: "xmark.octagon.fill",
                               hint: "↵ завершить", tint: "red", score: 1000,
                               run: { _ = Actions.sh("kill \(pid)"); Toast.show("💥 \(name) завершён, порт \(port) свободен"); return .close },
                               alt: { _ = Actions.sh("kill -9 \(pid)"); Toast.show("💥 kill -9 \(name)"); return .close }, altHint: "kill -9"))
            }
        }
        // процессы
        if let n = arg("kill"), !n.isEmpty {
            for app in NSWorkspace.shared.runningApplications where (app.localizedName ?? "").lowercased().contains(n.lowercased()) {
                let nm = app.localizedName ?? "?"
                out.append(Cmd(id: "kill.\(app.processIdentifier)", title: "Завершить " + nm, subtitle: "pid \(app.processIdentifier)",
                               icon: app.icon, hint: "↵", tint: "red", score: 900,
                               run: { app.terminate(); return .close }, alt: { app.forceTerminate(); return .close }, altHint: "принудительно"))
            }
        }
        // кодирование с аргументом
        if let t = arg("b64") { out.append(Cmd(id: "b64x", title: Data(t.utf8).base64EncodedString(), subtitle: "Base64", symbol: "lock.doc", score: 900, run: { Actions.copy(Data(t.utf8).base64EncodedString()) })) }
        if let t = arg("b64d"), let d = Data(base64Encoded: t), let s = String(data: d, encoding: .utf8) {
            out.append(Cmd(id: "b64dx", title: s, subtitle: "из Base64", symbol: "lock.open", score: 900, run: { Actions.copy(s) }))
        }
        if let t = arg("url"), let e = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            out.append(Cmd(id: "urlx", title: e, subtitle: "URL-кодирование", symbol: "link", score: 900, run: { Actions.copy(e) }))
        }
        if let t = arg("urld"), let d = t.removingPercentEncoding {
            out.append(Cmd(id: "urldx", title: d, subtitle: "URL-декодирование", symbol: "link", score: 900, run: { Actions.copy(d) }))
        }
        for (k, f) in [("sha256", { (d: Data) in SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }),
                       ("md5", { (d: Data) in Insecure.MD5.hash(data: d).map { String(format: "%02x", $0) }.joined() })] {
            if let t = arg(k) { let h = f(Data(t.utf8)); out.append(Cmd(id: k, title: h, subtitle: k.uppercased(), symbol: "number.square", score: 900, run: { Actions.copy(h) })) }
        }
        // время
        if let t = arg("ts"), let n = Double(t.trimmingCharacters(in: .whitespaces)) {
            let d = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
            let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy HH:mm:ss"
            let iso = ISO8601DateFormatter().string(from: d)
            out.append(Cmd(id: "tsx", title: f.string(from: d), subtitle: iso, symbol: "clock", score: 900, run: { Actions.copy(f.string(from: d)) },
                           alt: { Actions.copy(iso) }, altHint: "ISO"))
        }
        // цвет
        if let hex = parseHex(q) {
            let (r, g, b) = hex
            let s = "rgb(\(r), \(g), \(b))"
            out.append(Cmd(id: "color", title: s, subtitle: String(format: "#%02X%02X%02X · SwiftUI: Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b, Double(r) / 255, Double(g) / 255, Double(b) / 255),
                           symbol: "paintpalette.fill", score: 900, run: { Actions.copy(s) },
                           alt: { Actions.copy(String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", Double(r) / 255, Double(g) / 255, Double(b) / 255)) }, altHint: "SwiftUI"))
        }
        // git-ветки
        if let name = arg("git") {
            let n = name.trimmingCharacters(in: .whitespaces).lowercased()
            for r in Index.shared.repos where r.lastPathComponent.lowercased().hasPrefix(n) && !n.isEmpty {
                let (_, cur) = Actions.sh("git -C '\(r.path)' branch --show-current")
                let (_, list) = Actions.sh("git -C '\(r.path)' for-each-ref --sort=-committerdate --count=12 --format='%(refname:short)' refs/heads")
                for b in list.split(separator: "\n").map(String.init) {
                    let isCur = b == cur
                    out.append(Cmd(id: "branch.\(r.path).\(b)", title: b, subtitle: r.lastPathComponent + (isCur ? " · текущая" : ""),
                                   symbol: isCur ? "checkmark.circle.fill" : "arrow.triangle.branch", hint: isCur ? "" : "↵ переключить", tint: "green", score: 900,
                                   run: {
                                       let (code, o) = Actions.sh("git -C '\(r.path)' switch '\(b)'")
                                       Toast.show(code == 0 ? "🌿 \(r.lastPathComponent): \(b)" : "⚠️ " + (o.split(separator: "\n").first.map(String.init) ?? "ошибка"))
                                       return .close
                                   }))
                }
                break
            }
        }
        // сохранить набор окон
        if let name = arg("save"), !name.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(Cmd(id: "layout.savex", title: "Сохранить окна как «\(name)»", symbol: "square.and.arrow.down.fill", tint: "blue", score: 1000,
                           run: { Layouts.saveCurrent(name: name); Toast.show("🪟 Набор «\(name)» сохранён"); return .close }))
        }
        // фокус на N минут
        if let m = arg("focus").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) ?? arg("фокус").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            out.append(Cmd(id: "focusx", title: "Фокус \(m) мин", symbol: "target", tint: "orange", score: 1000,
                           run: { FocusTracker.shared.startFocus(minutes: m); return .close }))
        }
        // ссылка
        if (lower.hasPrefix("http://") || lower.hasPrefix("https://")) && !q.contains(" ") {
            out.append(Cmd(id: "openurl", title: "Открыть " + q, symbol: "safari", score: 1000, run: { Actions.open(q) }))
        }
        // поиск в сети (в конце)
        if q.count >= 2 {
            let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            out.append(Cmd(id: "web.google", title: "Google: " + q, symbol: "magnifyingglass", tint: "gray", score: 5, run: { Actions.open("https://www.google.com/search?q=" + e) }))
            out.append(Cmd(id: "web.github", title: "GitHub: " + q, symbol: "chevron.left.forwardslash.chevron.right", tint: "gray", score: 4, run: { Actions.open("https://github.com/search?type=repositories&q=" + e) }))
            out.append(Cmd(id: "web.claude", title: "Спросить Claude: " + q, symbol: "sparkles", tint: "purple", score: 4, run: { Actions.open("https://claude.ai/new?q=" + e) }))
        }
        return out
    }

    static func summaryLine() -> String {
        let t = FocusTracker.shared.today
        let parts = Cat.allCases.filter { t.cat($0) >= 60 }.sorted { t.cat($0) > t.cat($1) }.prefix(3).map { "\($0.title) \(dur(t.cat($0)))" }
        return parts.isEmpty ? "пока пусто" : parts.joined(separator: " · ")
    }
    static func dur(_ s: Double) -> String {
        let m = Int(s / 60); return m >= 60 ? "\(m / 60) ч \(m % 60) м" : "\(m) м"
    }

    private static func jsonFormat(_ s: String, pretty: Bool) -> Outcome {
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: o, options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { Toast.show("⚠️ В буфере не JSON"); return .close }
        return Actions.copy(str, pretty ? "JSON отформатирован и скопирован" : "JSON сжат и скопирован")
    }
    private static func b64decode(_ s: String) -> Outcome {
        guard let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)), let t = String(data: d, encoding: .utf8) else {
            Toast.show("⚠️ В буфере не Base64"); return .close
        }
        return Actions.copy(t)
    }
    private static func parseHex(_ q: String) -> (Int, Int, Int)? {
        var h = q.trimmingCharacters(in: .whitespaces)
        guard h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    }
    static func localIP() -> String {
        var addr = "—"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return addr }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard i.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: i.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(i.ifa_addr, socklen_t(i.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            addr = String(cString: host); break
        }
        return addr
    }
    private static func lockScreen() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let d = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: true); d?.flags = [.maskCommand, .maskControl]
        let u = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: false); u?.flags = [.maskCommand, .maskControl]
        d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
    }
}

/// Набрал в русской раскладке — всё равно найдём
enum Layout {
    static let ru = Array("йцукенгшщзхъфывапролджэячсмитьбю")
    static let en = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")
    static func flip(_ s: String) -> String {
        String(s.map { c in ru.firstIndex(of: c).map { en[$0] } ?? c })
    }
}

/// Свои скрипты: ~/.orbit/scripts/*.sh
enum Scripts {
    static var dir: URL {
        let d = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".orbit/scripts")
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let ex = d.appendingPathComponent("Пример — свободное место.sh")
            try? "#!/bin/zsh\n# Любой скрипт в этой папке появится в палитре Orbit.\n# Последняя строка вывода покажется уведомлением.\ndf -h / | awk 'NR==2 {print \"Свободно: \" $4}'\n"
                .write(to: ex, atomically: true, encoding: .utf8)
        }
        return d
    }
    static func list() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["sh", "zsh", "py", "js", "rb"].contains($0.pathExtension) }.sorted { $0.path < $1.path }
    }
    @MainActor static func run(_ u: URL) {
        Toast.show("▶︎ " + u.deletingPathExtension().lastPathComponent)
        DispatchQueue.global().async {
            let interp = ["py": "python3", "js": "node", "rb": "ruby"][u.pathExtension] ?? "zsh"
            let (code, out) = Actions.sh("cd ~ && \(interp) '\(u.path)'")
            let last = out.split(separator: "\n").last.map(String.init) ?? (code == 0 ? "Готово" : "Ошибка \(code)")
            DispatchQueue.main.async { MainActor.assumeIsolated { Toast.show((code == 0 ? "✅ " : "⚠️ ") + last) } }
        }
    }
}
