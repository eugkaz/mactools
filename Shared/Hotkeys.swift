import AppKit
import Carbon.HIToolbox

/// Глобальные сочетания клавиш (Carbon, без доступа к клавиатуре)
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    nonisolated static let ctrlOpt = UInt32(controlKey | optionKey)
    nonisolated static let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)

    @discardableResult
    func register(_ key: Int, _ mods: UInt32, _ action: @escaping () -> Void) -> UInt32 {
        install()
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: OSType(0x4F524254), id: id), GetApplicationEventTarget(), 0, &ref)
        if st == noErr, let ref { refs[id] = ref; actions[id] = action }
        return id
    }
    func unregister(_ id: UInt32) {
        if let r = refs[id] { UnregisterEventHotKey(r) }
        refs[id] = nil; actions[id] = nil
    }
    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Человекочитаемая подпись
    nonisolated static func label(_ key: Int, _ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        let names: [Int: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↵", 49: "Space", 51: "⌫", 24: "=", 27: "−",
                                    8: "C", 32: "U", 34: "I", 38: "J", 40: "K", 2: "D", 3: "F", 5: "G", 14: "E", 17: "T", 35: "P", 41: ";"]
        return s + (names[key] ?? "?")
    }
}
