import Foundation

struct AgentProc: Identifiable, Hashable {
    let id: Int32          // pid
    let name: String
    var cpu: Double        // свой CPU + дочерние процессы (сборки, тесты, git…)
    var dir: String = ""
}

/// Ищет запущенных ИИ-агентов и меряет их активность
enum AgentScanner {
    /// CLI: имя исполняемого файла (или скрипта, если запущен через node/python)
    static let cli: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "aider": "Aider", "gemini": "Gemini CLI",
        "opencode": "OpenCode", "goose": "Goose", "cursor-agent": "Cursor Agent", "amp": "Amp",
        "qwen": "Qwen Code", "crush": "Crush", "ollama": "Ollama", "llama-server": "llama.cpp",
        "mlx_lm.server": "MLX", "openhands": "OpenHands", "cline": "Cline",
    ]
    /// Приложения: часть пути к главному бинарнику
    static let apps: [String: String] = [
        "/Claude.app/Contents/MacOS/Claude": "Claude", "/ChatGPT.app/Contents/MacOS/ChatGPT": "ChatGPT",
        "/Cursor.app/Contents/MacOS/Cursor": "Cursor", "/Codex.app/Contents/MacOS/": "Codex",
        "/LM Studio.app/Contents/MacOS/": "LM Studio", "/Windsurf.app/Contents/MacOS/": "Windsurf",
    ]
    static let runners: Set<String> = ["node", "bun", "deno", "python", "python3", "npx", "uv", "uvx"]

    static func scan(extra: [String]) -> [AgentProc] {
        let out = Sh.run("/bin/ps", ["-axo", "pid=,ppid=,pcpu=,args="]).out
        struct Row { let pid: Int32; let ppid: Int32; let cpu: Double; let args: String }
        var rows: [Row] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let cpu = Double(parts[2]) else { continue }
            rows.append(Row(pid: pid, ppid: ppid, cpu: cpu, args: String(parts[3])))
        }
        var children: [Int32: [Int32]] = [:]
        var cpuOf: [Int32: Double] = [:]
        for r in rows { children[r.ppid, default: []].append(r.pid); cpuOf[r.pid] = r.cpu }
        func treeCPU(_ pid: Int32, depth: Int = 0) -> Double {
            guard depth < 12 else { return 0 }
            return (cpuOf[pid] ?? 0) + (children[pid] ?? []).reduce(0) { $0 + treeCPU($1, depth: depth + 1) }
        }
        let extraSet = Set(extra.map { $0.lowercased() }.filter { !$0.isEmpty })
        var found: [AgentProc] = []
        var matchedPids = Set<Int32>()
        for r in rows where r.pid != getpid() {
            guard let name = identify(r.args, extra: extraSet) else { continue }
            matchedPids.insert(r.pid)
            found.append(AgentProc(id: r.pid, name: name, cpu: 0))
        }
        // не считаем вложенных агентов дважды (агент внутри агента)
        let parentOf = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0.ppid) })
        func hasAgentAncestor(_ pid: Int32) -> Bool {
            var p = parentOf[pid] ?? 1, n = 0
            while p > 1, n < 30 { if matchedPids.contains(p) { return true }; p = parentOf[p] ?? 1; n += 1 }
            return false
        }
        return found.filter { !hasAgentAncestor($0.id) }.map { a in
            var a = a; a.cpu = (treeCPU(a.id)).rounded(); return a
        }
    }

    private static func identify(_ args: String, extra: Set<String>) -> String? {
        for (frag, name) in apps where args.hasPrefix("/") && args.contains(frag) {
            // только главный процесс, не Helper-ы
            if let r = args.range(of: frag), !args[r.upperBound...].hasPrefix(" Helper"),
               !args.contains("Helper") { return name }
        }
        let toks = args.split(separator: " ").prefix(3).map { String($0) }
        guard let first = toks.first else { return nil }
        var cands = [(first as NSString).lastPathComponent]
        if runners.contains(cands[0].lowercased()) || cands[0].hasPrefix("python"), toks.count > 1 {
            cands.append((toks[1] as NSString).lastPathComponent)
            if toks[1] == "-m", toks.count > 2 { cands.append(toks[2]) }
        }
        for c in cands {
            let k = c.lowercased()
            if let n = cli[k] { return n }
            if extra.contains(k) { return c }
        }
        return nil
    }

    /// Папка, в которой работает агент (lsof без лишнего)
    static func cwd(_ pid: Int32) -> String {
        let out = Sh.run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]).out
        guard let line = out.split(separator: "\n").first(where: { $0.hasPrefix("n") }) else { return "" }
        return (String(line.dropFirst()) as NSString).abbreviatingWithTildeInPath
    }
}
