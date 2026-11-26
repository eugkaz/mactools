import AppKit
import Observation
import CryptoKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Text transforms

enum Transform: String, CaseIterable, Identifiable {
    case jsonPretty = "JSON ✨", jsonMin = "JSON min", b64e = "Base64 →", b64d = "Base64 ←", urle = "URL →", urld = "URL ←",
         jwt = "JWT", ts = "Timestamp", sha = "SHA-256", md5 = "MD5", upper = "UPPER", lower = "lower", count = "Счёт"
    var id: String { rawValue }

    func apply(_ s: String) throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .jsonPretty, .jsonMin:
            let obj = try JSONSerialization.jsonObject(with: Data(t.utf8), options: [.fragmentsAllowed])
            let opts: JSONSerialization.WritingOptions = self == .jsonPretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
            return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: opts), as: UTF8.self)
        case .b64e: return Data(s.utf8).base64EncodedString()
        case .b64d:
            guard let d = Self.b64(t), let r = String(data: d, encoding: .utf8) else { throw DevError("Не Base64") }
            return r
        case .urle: return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?/"))) ?? s
        case .urld: return s.removingPercentEncoding ?? s
        case .jwt:
            let parts = t.split(separator: ".")
            guard parts.count >= 2 else { throw DevError("Не похоже на JWT") }
            var out: [String] = []
            for (i, p) in parts.prefix(2).enumerated() {
                guard let d = Self.b64(String(p)) else { throw DevError("Битый JWT") }
                var str = String(decoding: d, as: UTF8.self)
                if let pretty = try? Transform.jsonPretty.apply(str) { str = pretty }
                out.append((i == 0 ? "// header\n" : "// payload\n") + str)
            }
            if let d = Self.b64(String(parts[1])), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let exp = obj["exp"] as? Double {
                let date = Date(timeIntervalSince1970: exp)
                out.append("// exp: \(date.formatted(date: .abbreviated, time: .standard))" + (date < Date() ? " — ИСТЁК" : " — действителен"))
            }
            return out.joined(separator: "\n\n")
        case .ts:
            if t.isEmpty { return "\(Int(Date().timeIntervalSince1970))" }
            if var n = Double(t) {
                if n > 1e12 { n /= 1000 }
                let d = Date(timeIntervalSince1970: n)
                let iso = ISO8601DateFormatter()
                return "\(d.formatted(date: .complete, time: .standard))\nISO: \(iso.string(from: d))\nUTC: \(d.formatted(.iso8601))"
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: t) ?? ISO8601DateFormatter().date(from: t) { return "\(Int(d.timeIntervalSince1970))" }
            throw DevError("Введите число или ISO-дату (пусто = сейчас)")
        case .sha: return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .md5: return Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .count:
            let words = s.split { $0.isWhitespace || $0.isNewline }.count
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false).count
            return "Символов: \(s.count)\nБез пробелов: \(s.filter { !$0.isWhitespace }.count)\nСлов: \(words)\nСтрок: \(lines)\nБайт (UTF-8): \(s.utf8.count)"
        }
    }

    static func b64(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str += "=" }
        return Data(base64Encoded: str)
    }
}

struct DevError: LocalizedError {
    let m: String
    init(_ m: String) { self.m = m }
    var errorDescription: String? { m }
}

// MARK: - Ports

struct PortEntry: Identifiable, Hashable {
    var id: String { "\(pid):\(port)" }
    let command: String
    let pid: Int32
    let port: String
    let address: String
}

@Observable
final class PortsStore {
    var entries: [PortEntry] = []
    var loading = false

    func refresh() {
        loading = true
        Task {
            let (_, out) = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
            var seen = Set<String>()
            var list: [PortEntry] = []
            for line in out.split(separator: "\n").dropFirst() {
                let p = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard p.count >= 9, let pid = Int32(p[1]) else { continue }
                let name = p[p.count - 2]
                guard let colon = name.lastIndex(of: ":") else { continue }
                let port = String(name[name.index(after: colon)...])
                let e = PortEntry(command: p[0].replacingOccurrences(of: "\\x20", with: " "), pid: pid, port: port, address: String(name[..<colon]))
                if seen.insert(e.id).inserted { list.append(e) }
            }
            entries = list.sorted { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) }
            loading = false
        }
    }

    func kill(_ e: PortEntry, force: Bool = false) {
        Darwin.kill(e.pid, force ? SIGKILL : SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }
}

// MARK: - Snippets

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var inTerminal = false
}

@Observable
final class SnippetStore {
    var items: [Snippet]
    var output = ""
    var running: UUID?

    init() {
        items = Persist.load([Snippet].self, "snippets") ?? [
            Snippet(name: "Мой IP", command: "echo \"Локальный: $(ipconfig getifaddr en0)\"; echo \"Внешний:   $(curl -s --max-time 5 https://api.ipify.org)\""),
            Snippet(name: "Docker ps", command: "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"),
            Snippet(name: "Brew outdated", command: "brew outdated"),
            Snippet(name: "Git: все репо", command: "for d in ~/Developer/*/.git(N); do r=${d:h}; echo \"${r:t}: $(git -C $r status -sb | head -1)\"; done"),
            Snippet(name: "Место на диске", command: "df -h / | tail -1; echo; du -sh ~/Library/Caches ~/Downloads 2>/dev/null"),
            Snippet(name: "Сбросить DNS", command: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; echo DNS сброшен", inTerminal: true),
            Snippet(name: "Brew upgrade", command: "brew update && brew upgrade", inTerminal: true),
        ]
    }

    func run(_ s: Snippet) {
        if s.inTerminal { Shell.inTerminal(s.command); return }
        running = s.id
        output = "$ \(s.command)\n"
        Task {
            let (code, out) = await Shell.zsh(s.command, timeout: 60)
            output = out.isEmpty ? "(нет вывода, код \(code))" : out
            running = nil
        }
    }

    func add(_ s: Snippet) { items.append(s); save() }
    func remove(_ s: Snippet) { items.removeAll { $0.id == s.id }; save() }
    func save() { Persist.save(items, "snippets") }
}

// MARK: - System monitor

@Observable
final class SystemMonitor {
    var cpu: Double = 0
    var memUsed: Double = 0
    var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var diskFree: Double = 0
    var diskTotal: Double = 0
    var battery: Int?
    var charging = false
    var netIn: Double = 0
    var netOut: Double = 0
    var localIP = "—"
    var caffeinated = false
    var hiddenFiles = false

    @ObservationIgnored private var prevTicks: (UInt64, UInt64)?
    @ObservationIgnored private var prevNet: (UInt64, UInt64, Date)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var assertion: IOPMAssertionID = 0

    var active = false {
        didSet {
            timer?.invalidate()
            if active {
                update()
                timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
                Task { hiddenFiles = (await Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"])).1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("1") || false }
            }
        }
    }

    var uptime: String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d)д \(h)ч" : "\(h)ч \(m)м"
    }

    func update() {
        cpu = readCPU()
        memUsed = readMem()
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }
        readBattery()
        readNet()
    }

    private func readCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) }
        }
        guard r == KERN_SUCCESS else { return cpu }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + sys + nice, total = busy + idle
        defer { prevTicks = (busy, total) }
        guard let (pb, pt) = prevTicks, total > pt else { return cpu }
        return Double(busy - pb) / Double(total - pt)
    }

    private func readMem() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return memUsed }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
               let cap = d[kIOPSCurrentCapacityKey] as? Int {
                battery = cap
                charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            }
        }
    }

    private func readNet() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var inB: UInt64 = 0, outB: UInt64 = 0
        var ip = "—"
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let name = String(cString: cur.pointee.ifa_name)
            if let addr = cur.pointee.ifa_addr {
                if addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = cur.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    inB += UInt64(d.ifi_ibytes); outB += UInt64(d.ifi_obytes)
                }
                if addr.pointee.sa_family == UInt8(AF_INET), name == "en0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    ip = String(cString: host)
                }
            }
            p = cur.pointee.ifa_next
        }
        localIP = ip
        let now = Date()
        if let (pi, po, pd) = prevNet, inB >= pi, outB >= po {
            let dt = now.timeIntervalSince(pd)
            if dt > 0 { netIn = Double(inB - pi) / dt; netOut = Double(outB - po) / dt }
        }
        prevNet = (inB, outB, now)
    }

    func toggleCaffeine() {
        if caffeinated {
            IOPMAssertionRelease(assertion)
            caffeinated = false
        } else {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn), "NotchDeck: не засыпать" as CFString, &assertion)
            caffeinated = r == kIOReturnSuccess
        }
    }

    func toggleHiddenFiles() {
        hiddenFiles.toggle()
        let v = hiddenFiles
        Task {
            _ = await Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", v ? "true" : "false"])
            _ = await Shell.run("/usr/bin/killall", ["Finder"])
        }
    }

    static func bytes(_ b: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }
}
