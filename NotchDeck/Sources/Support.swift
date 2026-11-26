import AppKit

enum Persist {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchDeck")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func save<T: Encodable>(_ v: T, _ name: String) {
        if let data = try? JSONEncoder().encode(v) { try? data.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic) }
    }

    static func load<T: Decodable>(_ t: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }
}

enum Shell {
    /// Запуск команды и сбор вывода (через временный файл — без риска переполнить pipe).
    static func run(_ exe: String, _ args: [String], timeout: Double = 30) async -> (Int32, String) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("nd-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: log) else { return (-1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        return await withCheckedContinuation { cont in
            p.terminationHandler = { proc in
                try? handle.close()
                let out = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: log)
                cont.resume(returning: (proc.terminationStatus, out))
            }
            do { try p.run() } catch {
                cont.resume(returning: (-1, error.localizedDescription))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
    }

    static func zsh(_ cmd: String, timeout: Double = 30) async -> (Int32, String) {
        await run("/bin/zsh", ["-lc", cmd], timeout: timeout)
    }

    static func inTerminal(_ cmd: String) {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        AppleScript.run("tell application \"Terminal\"\nactivate\ndo script \"\(esc)\"\nend tell")
    }
}

enum AppleScript {
    private static var cache: [String: NSAppleScript] = [:]

    /// Скрипты компилируются один раз и переиспользуются (раньше компилировались каждые 1.5 с).
    @discardableResult
    static func run(_ src: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let c = cache[src] { script = c } else {
            guard let s = NSAppleScript(source: src) else { return nil }
            var e: NSDictionary?
            s.compileAndReturnError(&e)
            if cache.count > 40 { cache.removeAll() }
            cache[src] = s
            script = s
        }
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        return err == nil ? r : nil
    }
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}
