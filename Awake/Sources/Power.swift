import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// Запрет сна через IOPMAssertion (без пароля)
final class SleepAssertion {
    private var sys: IOPMAssertionID = 0
    private var disp: IOPMAssertionID = 0

    func apply(system: Bool, display: Bool) {
        set(&sys, on: system, type: kIOPMAssertionTypePreventUserIdleSystemSleep)
        set(&disp, on: system && display, type: kIOPMAssertionTypePreventUserIdleDisplaySleep)
    }
    private func set(_ id: inout IOPMAssertionID, on: Bool, type: String) {
        if on, id == 0 {
            IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Awake: AI agents are working" as CFString, &id)
        } else if !on, id != 0 {
            IOPMAssertionRelease(id); id = 0
        }
    }
}

/// Режим «закрытая крышка»: pmset disablesleep (нужны права root)
enum Lid {
    static let sudoersPath = "/etc/sudoers.d/awake-pmset"

    static var sleepDisabled: Bool {
        let out = Sh.run("/usr/bin/pmset", ["-g"]).out
        for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
        }
        return false
    }

    /// Работает ли pmset через sudo без пароля
    static var passwordless: Bool {
        Sh.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-g"]).code == 0 && FileManager.default.fileExists(atPath: sudoersPath)
    }

    static var isClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(root) }
        guard let v = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool else { return false }
        return v
    }

    /// interactive = можно показать окно с паролем
    @discardableResult
    static func set(_ on: Bool, interactive: Bool) -> Bool {
        let v = on ? "1" : "0"
        if Sh.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", v]).code == 0 { return true }
        guard interactive else { return false }
        return admin("/usr/bin/pmset -a disablesleep \(v)")
    }

    /// Разовая настройка: разрешить только эти две команды pmset без пароля
    static func installPasswordless() -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -g\n"
        let tmp = NSTemporaryDirectory() + "awake-sudoers"
        try? rule.write(toFile: tmp, atomically: true, encoding: .utf8)
        // проверяем синтаксис visudo перед установкой, иначе можно сломать sudo
        return admin("/usr/sbin/visudo -cf '\(tmp)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp)' \(sudoersPath)")
    }
    static func removePasswordless() -> Bool { admin("/bin/rm -f \(sudoersPath)") }

    private static func admin(_ cmd: String) -> Bool {
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        return Sh.run("/usr/bin/osascript", ["-e", script]).code == 0
    }
}

struct BatteryInfo: Equatable { var percent: Int; var onAC: Bool; var present: Bool }

enum Battery {
    static func read() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryInfo(percent: 100, onAC: true, present: false)
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            let mx = max(1, d[kIOPSMaxCapacityKey] as? Int ?? 100)
            return BatteryInfo(percent: cur * 100 / mx, onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue, present: true)
        }
        return BatteryInfo(percent: 100, onAC: true, present: false)
    }
}

enum Sh {
    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> (code: Int32, out: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
