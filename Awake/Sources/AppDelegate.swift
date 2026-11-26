import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: MenuBarPanel!
    private var model: AwakeModel!
    private var icon: EyeIcon!

    func applicationDidFinishLaunching(_ n: Notification) {
        model = AwakeModel()
        if Snapshot.dir != nil { snapshots(); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        icon = EyeIcon(button: item.button!)
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let m = model!
        panel = MenuBarPanel(width: 348) {
            AwakeView(m: m, quit: { NSApp.terminate(nil) }, close: { [weak self] in self?.panel.close() })
        }
        panel.onClose = { [weak self] in self?.model.visible = false; self?.model.setFast(false) }
        model.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    private func refreshIcon() {
        icon.state = model.batteryBlocked ? .battery : !model.isAwake ? .asleep : model.anyActive ? .working : .awake
        icon.lid = model.isAwake && model.lidApplied
        item.button?.toolTip = model.isAwake ? "Awake: Mac не уснёт" : "Awake: обычный сон"
    }

    @objc private func click() {
        if let e = NSApp.currentEvent, e.type == .rightMouseUp || e.modifierFlags.contains(.option) {
            model.manualOn ? model.stopManual() : model.keep(minutes: nil)
            icon.pulse(); return
        }
        if panel.isShown { panel.close(); return }
        model.tick()
        model.visible = true
        model.setFast(true)
        panel.show(from: item.button!)
    }

    private func snapshots() {
        model.visible = false
        Snapshot.save("awake", AwakeView(m: model, quit: {}, close: {}))
        model.keep(minutes: 60)
        Snapshot.save("awake_on", AwakeView(m: model, quit: {}, close: {}))
        model.stopManual()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ n: Notification) { model.shutdown() }
}
