import AppKit
import CoreAudio
import AudioToolbox
import ApplicationServices
import Observation
import SwiftUI

/// Перехват клавиш громкости и яркости: системный HUD не показывается, значение рисует NotchDeck.
/// Нужен доступ «Универсальный доступ» (Accessibility) — иначе событие нельзя «съесть».
@Observable
final class HUDController {
    enum Kind { case volume, brightness }

    var kind: Kind = .volume
    var level: Double = 0          // 0…1
    var muted = false
    var visible = false
    /// растёт при каждом нажатии — для «толчка» анимации
    var pulse = 0

    var icon: String {
        switch kind {
        case .brightness: return level < 0.01 ? "sun.min" : "sun.max.fill"
        case .volume:
            if muted || level < 0.001 { return "speaker.slash.fill" }
            return level < 0.34 ? "speaker.wave.1.fill" : (level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        }
    }
    var shownLevel: Double { kind == .volume && muted ? 0 : level }

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var hideWork: DispatchWorkItem?
    @ObservationIgnored private var retry: Timer?
    @ObservationIgnored private var lastOwnChange = Date.distantPast
    @ObservationIgnored private var watchedDevice: AudioObjectID = 0
    @ObservationIgnored private var brightnessRamp: Timer?
    @ObservationIgnored fileprivate static weak var current: HUDController?

    func start() {
        HUDController.current = self
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            // ждём, пока пользователь выдаст доступ, и подключаемся сами
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if AXIsProcessTrusted() { t.invalidate(); self?.installTap() }
            }
        } else { installTap() }
        watchVolume()
    }

    // MARK: Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << 14)   // NSSystemDefined: медиа-клавиши, громкость, яркость
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: hudTapCallback, userInfo: nil) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    fileprivate func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// true — событие обработано и «съедено»
    fileprivate func handle(_ cg: CGEvent) -> Bool {
        guard let e = NSEvent(cgEvent: cg), e.subtype.rawValue == 8 else { return false }
        let key = Int((e.data1 & 0xFFFF0000) >> 16)
        let down = ((e.data1 & 0xFF00) >> 8) == 0xA
        let mods = e.modifierFlags.intersection([.option, .shift, .command, .control])
        // ⌥ без ⇧ — системное поведение (открыть настройки звука/дисплея)
        if mods.contains(.option) && !mods.contains(.shift) { return false }
        let fine = mods.contains(.option) && mods.contains(.shift)   // ⌥⇧ — мелкий шаг 1%, обычный — 5%
        let step = fine ? 0.01 : 0.05
        switch key {
        case 0, 1, 7:   // NX_KEYTYPE_SOUND_UP / SOUND_DOWN / MUTE
            guard let dev = Audio.outputDevice(), Audio.hasVolume(dev) else { return false }
            if down { volumeKey(key, dev: dev, step: step) }
            return true
        case 2, 3:      // NX_KEYTYPE_BRIGHTNESS_UP / DOWN
            guard Brightness.available else { return false }
            if down { brightnessKey(up: key == 2, step: step) }
            return true
        default: return false
        }
    }

    private func volumeKey(_ key: Int, dev: AudioObjectID, step: Double) {
        var v = Double(Audio.volume(dev))
        var m = Audio.isMuted(dev)
        switch key {
        case 7:
            m.toggle()
            // включили звук на нулевой громкости — даём одно деление, иначе «включение» ничего не меняет
            if !m && v < 0.001 { v = step; Audio.setVolume(dev, Float(v)) }
            Audio.setMuted(dev, m)
        default:
            v = key == 0 ? v + step : v - step
            v = (v / step).rounded() * step          // ровные деления, как у системы
            v = min(1, max(0, v))
            if v < 0.001 {
                // у многих устройств громкость 0 — это лишь минимальный уровень, а не тишина: как и macOS, ставим mute
                v = 0
                Audio.setVolume(dev, 0)
                m = true; Audio.setMuted(dev, true)
            } else {
                Audio.setVolume(dev, Float(v))
                if m { m = false; Audio.setMuted(dev, false) }
            }
        }
        lastOwnChange = Date()
        show(.volume, level: v, muted: m)
    }

    private func brightnessKey(up: Bool, step: Double) {
        let cur = Double(Brightness.get())
        var v = up ? cur + step : cur - step
        v = min(1, max(0, (v / step).rounded() * step))
        rampBrightness(from: cur, to: v)
        show(.brightness, level: v, muted: false)
    }

    /// Плавная смена яркости (~90 мс), как у системы
    private func rampBrightness(from a: Double, to b: Double) {
        brightnessRamp?.invalidate()
        var i = 0
        let n = 6
        brightnessRamp = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { t in
            i += 1
            Brightness.set(Float(a + (b - a) * Double(i) / Double(n)))
            if i >= n { t.invalidate() }
        }
    }

    // MARK: Показ

    func show(_ k: Kind, level l: Double, muted m: Bool) {
        let appearing = !visible || kind != k
        if appearing {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { kind = k; muted = m; if !visible { level = l } }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            visible = true
            kind = k
            level = l
            muted = m
            pulse += 1
        }
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.visible = false }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }

    // MARK: Громкость, изменённая не клавишами (Пункт управления, AirPods и т.п.)

    private func watchVolume() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.attachDevice()
        }
        attachDevice()
    }

    private func attachDevice() {
        guard let dev = Audio.outputDevice(), dev != watchedDevice else { return }
        watchedDevice = dev
        for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(dev, &addr, .main) { [weak self] _, _ in
                guard let self, dev == self.watchedDevice, Date().timeIntervalSince(self.lastOwnChange) > 0.4 else { return }
                self.show(.volume, level: Double(Audio.volume(dev)), muted: Audio.isMuted(dev))
            }
        }
    }
}

private func hudTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        HUDController.current?.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type.rawValue == 14, let hud = HUDController.current, hud.handle(event) { return nil }
    return Unmanaged.passUnretained(event)
}

// MARK: - CoreAudio

enum Audio {
    static func outputDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr && id != 0 ? id : nil
    }

    private static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func hasVolume(_ dev: AudioObjectID) -> Bool {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(dev, &a) && AudioObjectIsPropertySettable(dev, &a, &settable) == noErr && settable.boolValue
    }

    static func volume(_ dev: AudioObjectID) -> Float {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v)
        return v
    }

    static func setVolume(_ dev: AudioObjectID, _ v: Float) {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var val = Float32(v)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &val)
    }

    static func isMuted(_ dev: AudioObjectID) -> Bool {
        var a = addr(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &a) else { return false }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m)
        return m != 0
    }

    static func setMuted(_ dev: AudioObjectID, _ m: Bool) {
        var a = addr(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &a) else { return }
        var val: UInt32 = m ? 1 : 0
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
    }
}

// MARK: - Яркость встроенного дисплея (DisplayServices, приватный)

enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = dlsym(lib, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = dlsym(lib, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }

    static var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var available: Bool {
        guard let d = display, let g = getFn, setFn != nil else { return false }
        var v: Float = 0
        return g(d, &v) == 0
    }

    static func get() -> Float {
        guard let d = display, let g = getFn else { return 0 }
        var v: Float = 0
        _ = g(d, &v)
        return v
    }

    static func set(_ v: Float) {
        guard let d = display, let s = setFn else { return }
        _ = s(d, min(1, max(0, v)))
    }
}
