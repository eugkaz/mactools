import AppKit
import Observation
import UserNotifications
import SwiftUI

enum Cat: String, CaseIterable, Codable {
    case code, ai, browser, chat, fun, other
    var title: String {
        switch self { case .code: "Код"; case .ai: "ИИ"; case .browser: "Браузер"; case .chat: "Общение"; case .fun: "Отвлечения"; case .other: "Другое" }
    }
    var color: Color {
        switch self { case .code: .blue; case .ai: .purple; case .browser: .teal; case .chat: .green; case .fun: .orange; case .other: .gray }
    }
    var productive: Bool { self == .code || self == .ai }
}

struct DayStats: Codable {
    var apps: [String: Double] = [:]
    var domains: [String: Double] = [:]
    var cats: [String: Double] = [:]
    var focusSessions = 0
    var focusSeconds: Double = 0
    var total: Double { cats.values.reduce(0, +) }
    func cat(_ c: Cat) -> Double { cats[c.rawValue] ?? 0 }
}

enum Classifier {
    static let code: Set<String> = ["Xcode", "Code", "Visual Studio Code", "Cursor", "Zed", "Terminal", "iTerm2", "Warp", "Ghostty",
        "IntelliJ IDEA", "PyCharm", "WebStorm", "CLion", "GoLand", "Android Studio", "Sublime Text", "Nova", "Docker Desktop", "Docker",
        "Postman", "TablePlus", "DataGrip", "Fork", "Tower", "GitHub Desktop", "Kitty", "Alacritty", "Simulator", "Instruments",
        "Windsurf", "Jupyter", "RStudio", "Fleet", "Hyper", "Tabby", "Sourcetree", "DBeaver", "Proxyman", "Charles"]
    static let ai: Set<String> = ["Claude", "ChatGPT", "Perplexity", "LM Studio", "Ollama", "Codex"]
    static let chat: Set<String> = ["Telegram", "Slack", "Discord", "WhatsApp", "Messages", "Сообщения", "Zoom", "Mail", "Почта",
        "Microsoft Teams", "Skype", "Viber", "FaceTime", "Element", "Signal"]
    static let fun: Set<String> = ["Music", "Музыка", "Spotify", "TV", "Podcasts", "Подкасты", "Steam", "IINA", "VLC", "Яндекс Музыка", "Photos", "Фото"]
    static let browsers: [String: String] = ["Safari": "safari", "Google Chrome": "chrome", "Arc": "chrome", "Brave Browser": "chrome",
        "Microsoft Edge": "chrome", "Firefox": "none", "Zen": "none", "Yandex": "chrome", "Chromium": "chrome", "Opera": "chrome", "Vivaldi": "chrome", "Orion": "safari"]
    static let codeDomains = ["github.com", "gitlab.com", "stackoverflow.com", "developer.apple.com", "localhost", "127.0.0.1",
        "docs.", "npmjs.com", "pypi.org", "vercel.com", "leetcode.com", "habr.com", "swift.org", "kaggle.com", "huggingface.co", "medium.com"]
    static let aiDomains = ["claude.ai", "chatgpt.com", "chat.openai.com", "perplexity.ai", "gemini.google.com", "deepseek.com", "aistudio.google.com"]
    static let funDomains = ["youtube.com", "instagram.com", "tiktok.com", "vk.com", "reddit.com", "x.com", "twitter.com", "twitch.tv",
        "netflix.com", "facebook.com", "pinterest.com", "kinopoisk.ru", "rutube.ru", "9gag.com", "dzen.ru"]

    static func app(_ name: String) -> Cat {
        if code.contains(name) || name.contains("JetBrains") { return .code }
        if ai.contains(name) { return .ai }
        if chat.contains(name) { return .chat }
        if fun.contains(name) { return .fun }
        if browsers[name] != nil { return .browser }
        return .other
    }
    static func domain(_ d: String) -> Cat {
        func has(_ list: [String]) -> Bool { list.contains { d == $0 || d.hasSuffix("." + $0) || ($0.hasSuffix(".") && d.hasPrefix($0)) } }
        if has(aiDomains) { return .ai }
        if has(codeDomains) { return .code }
        if has(funDomains) { return .fun }
        return .browser
    }
}

enum Browser {
    private static var cache: [String: NSAppleScript] = [:]
    static func script(_ src: String) -> NSAppleScript? {
        if let s = cache[src] { return s }
        guard let s = NSAppleScript(source: src) else { return nil }
        s.compileAndReturnError(nil); cache[src] = s; return s
    }
    static func url(app: String) -> String? {
        guard let kind = Classifier.browsers[app], kind != "none" else { return nil }
        let src = kind == "safari"
            ? "tell application \"\(app)\" to if (count of windows) > 0 then return URL of current tab of front window"
            : "tell application \"\(app)\" to if (count of windows) > 0 then return URL of active tab of front window"
        var err: NSDictionary?
        return script(src)?.executeAndReturnError(&err).stringValue
    }
    static func setURL(app: String, _ url: String) {
        guard let kind = Classifier.browsers[app], kind != "none" else { return }
        let src = kind == "safari"
            ? "tell application \"\(app)\" to set URL of current tab of front window to \"\(url)\""
            : "tell application \"\(app)\" to set URL of active tab of front window to \"\(url)\""
        var err: NSDictionary?
        _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
    }
    static func domain(_ url: String) -> String? {
        guard let h = URL(string: url)?.host?.lowercased() else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

@MainActor @Observable
final class FocusTracker {
    static let shared = FocusTracker()

    enum Phase: Equatable { case idle, focus, rest }
    private(set) var phase: Phase = .idle
    private(set) var phaseEnd: Date?
    private(set) var phaseLength: Double = 1
    private(set) var today = DayStats()
    private(set) var currentApp = ""
    private(set) var currentDomain: String?
    var onTick: (() -> Void)?

    // настройки
    var focusMin = UserDefaults.standard.object(forKey: "focusMin") as? Int ?? 25 { didSet { UserDefaults.standard.set(focusMin, forKey: "focusMin") } }
    var restMin = UserDefaults.standard.object(forKey: "restMin") as? Int ?? 5 { didSet { UserDefaults.standard.set(restMin, forKey: "restMin") } }
    var blockSites = UserDefaults.standard.string(forKey: "blockSites") ?? "youtube.com, instagram.com, tiktok.com, vk.com, reddit.com, x.com, twitch.tv"
        { didSet { UserDefaults.standard.set(blockSites, forKey: "blockSites") } }
    var blockApps = UserDefaults.standard.string(forKey: "blockApps") ?? "Telegram, Discord"
        { didSet { UserDefaults.standard.set(blockApps, forKey: "blockApps") } }
    var trackSites = UserDefaults.standard.object(forKey: "trackSites") as? Bool ?? true { didSet { UserDefaults.standard.set(trackSites, forKey: "trackSites") } }

    private var dayKey = FocusTracker.key(Date())
    private var timer: Timer?
    private var lastURLCheck = Date.distantPast
    private var lastSave = Date()
    private let tickSec: Double = 5

    private init() {
        today = Self.load(dayKey)
        timer = Timer.scheduledTimer(withTimeInterval: tickSec, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: учёт времени
    private func tick() {
        let now = Date()
        let k = Self.key(now)
        if k != dayKey { save(); dayKey = k; today = Self.load(k) }

        if let end = phaseEnd, now >= end { phaseFinished() }
        if phase == .focus { today.focusSeconds += tickSec }

        // отошёл от Мака — не считаем
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        guard idle < 120, let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName,
              app.bundleIdentifier != Bundle.main.bundleIdentifier, !["loginwindow", "ScreenSaverEngine"].contains(name) else { onTick?(); return }
        currentApp = name
        today.apps[name, default: 0] += tickSec
        var cat = Classifier.app(name)
        if Classifier.browsers[name] != nil {
            if trackSites || phase == .focus, now.timeIntervalSince(lastURLCheck) >= 10 {
                lastURLCheck = now
                let u = Browser.url(app: name)
                currentDomain = u.flatMap(Browser.domain)
                if phase == .focus, let d = currentDomain, blocked(domain: d) { blockSite(app: name, d) }
            }
            if let d = currentDomain {
                today.domains[d, default: 0] += tickSec
                cat = Classifier.domain(d)
            }
        } else { currentDomain = nil }
        today.cats[cat.rawValue, default: 0] += tickSec
        if now.timeIntervalSince(lastSave) > 60 { save() }
        onTick?()
    }

    private func activated(_ app: NSRunningApplication?) {
        lastURLCheck = .distantPast
        guard phase == .focus, let app, let name = app.localizedName else { return }
        let list = Self.split(blockApps)
        if list.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            app.hide()
            Toast.show("🎯 \(name) подождёт · осталось \(remaining)")
        }
    }

    private func blocked(domain d: String) -> Bool {
        Self.split(blockSites).contains { d == $0 || d.hasSuffix("." + $0) }
    }
    private func blockSite(app: String, _ d: String) {
        Browser.setURL(app: app, Self.focusPage(domain: d, remaining: remaining).absoluteString)
        Toast.show("🎯 \(d) заблокирован до конца фокуса")
    }

    // MARK: помидоры
    func startFocus(minutes: Int? = nil) {
        let m = Double(minutes ?? focusMin)
        phase = .focus; phaseLength = m * 60; phaseEnd = Date().addingTimeInterval(m * 60)
        lastURLCheck = .distantPast
        Toast.show("🎯 Фокус \(Int(m)) мин. Отвлекающее заблокировано")
        onTick?()
    }
    func startRest() {
        phase = .rest; phaseLength = Double(restMin) * 60; phaseEnd = Date().addingTimeInterval(phaseLength)
        onTick?()
    }
    func stop() { phase = .idle; phaseEnd = nil; onTick?() }

    private func phaseFinished() {
        if phase == .focus {
            today.focusSessions += 1; save()
            notify("Фокус завершён 🎉", "Сессий сегодня: \(today.focusSessions). Перерыв \(restMin) мин.")
            NSSound(named: "Glass")?.play()
            startRest()
        } else {
            notify("Перерыв окончен", "Готов к следующему фокусу? ⌃⌥P")
            NSSound(named: "Hero")?.play()
            stop()
        }
    }

    var progress: Double {
        guard let e = phaseEnd else { return 0 }
        return min(1, max(0, 1 - e.timeIntervalSinceNow / phaseLength))
    }
    var remaining: String {
        guard let e = phaseEnd else { return "" }
        let s = max(0, Int(e.timeIntervalSinceNow))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: хранение
    func save() {
        try? JSONEncoder().encode(today).write(to: Self.url(dayKey))
        lastSave = Date()
    }
    static func load(_ k: String) -> DayStats {
        (try? Data(contentsOf: url(k))).flatMap { try? JSONDecoder().decode(DayStats.self, from: $0) } ?? DayStats()
    }
    static func dir() -> URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbit/days")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ k: String) -> URL { dir().appendingPathComponent(k + ".json") }
    static func key(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    static func days(_ n: Int) -> [(Date, DayStats)] {
        (0..<n).reversed().map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            return (d, key(d) == shared.dayKey ? shared.today : load(key(d)))
        }
    }
    static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    func notify(_ t: String, _ b: String) {
        let c = UNMutableNotificationContent(); c.title = t; c.body = b
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Локальная страница-заглушка для заблокированного сайта
    static func focusPage(domain: String, remaining: String) -> URL {
        let u = dir().deletingLastPathComponent().appendingPathComponent("focus.html")
        let html = """
        <!doctype html><meta charset=utf-8><title>Фокус</title>
        <style>body{margin:0;height:100vh;display:grid;place-items:center;font:16px -apple-system,sans-serif;
        background:radial-gradient(circle at 30% 20%,#ff9a4d,#e0245e 60%,#4a0f3b);color:#fff;text-align:center}
        h1{font-size:64px;margin:0}p{opacity:.85}</style>
        <div><h1>🎯</h1><h2>\(domain) подождёт</h2><p>Фокус идёт. Осталось примерно \(remaining).</p></div>
        """
        try? html.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}
