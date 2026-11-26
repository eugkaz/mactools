import AppKit
import SwiftUI
import ServiceManagement

@MainActor
enum SettingsWindow {
    private static var win: NSWindow?
    static func show() {
        if win == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Настройки Orbit"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center(); win = w
        }
        NSApp.activate(); win?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("Общие", systemImage: "gearshape") }
            FocusTab().tabItem { Label("Фокус", systemImage: "target") }
            SnippetsTab().tabItem { Label("Сниппеты", systemImage: "text.quote") }
            KeysTab().tabItem { Label("Клавиши", systemImage: "keyboard") }
        }
        .padding(18)
        .frame(width: 560, height: 480)
    }
}

private struct GeneralTab: View {
    @State private var trusted = AX.trusted
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var snap = SnapController.shared.enabled
    @State private var gap = UserDefaults.standard.integer(forKey: "gap")
    @State private var palKey = UserDefaults.standard.integer(forKey: "paletteKey")
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Доступ к управлению окнами есть" : "Нужен доступ: Универсальный доступ → Orbit")
                    Spacer()
                    if !trusted { Button("Открыть") { AX.prompt(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } }
                }
            }
            Section("Палитра") {
                Picker("Открывать по", selection: $palKey) {
                    ForEach(Array(AppDelegate.paletteKeys.enumerated()), id: \.offset) { i, k in Text(k.label).tag(i) }
                }
                .onChange(of: palKey) { _, v in UserDefaults.standard.set(v, forKey: "paletteKey"); (NSApp.delegate as? AppDelegate)?.registerPalette() }
                Text("⌥Space занят быстрым вводом Claude, ⌃Space — сменой языка, поэтому по умолчанию ⇧⌘Space.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Окна") {
                Toggle("Прилипание при перетаскивании к краям", isOn: $snap).onChange(of: snap) { _, v in SnapController.shared.enabled = v }
                Stepper("Отступ между окнами: \(gap) pt", value: $gap, in: 0...24, step: 2).onChange(of: gap) { _, v in UserDefaults.standard.set(v, forKey: "gap") }
            }
            Section {
                Toggle("Запускать при входе", isOn: $login).onChange(of: login) { _, v in
                    try? v ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
                Button("Открыть папку скриптов (~/.orbit/scripts)") { NSWorkspace.shared.open(Scripts.dir) }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = AX.trusted }
    }
}

private struct FocusTab: View {
    @Bindable var t = FocusTracker.shared
    var body: some View {
        Form {
            Section("Помидоры") {
                Stepper("Фокус: \(t.focusMin) мин", value: $t.focusMin, in: 5...120, step: 5)
                Stepper("Перерыв: \(t.restMin) мин", value: $t.restMin, in: 1...30)
            }
            Section("Блокировать во время фокуса") {
                LabeledContent("Сайты") { TextField("", text: $t.blockSites, axis: .vertical).lineLimit(2...4) }
                LabeledContent("Приложения") { TextField("", text: $t.blockApps) }
                Text("Через запятую. Сайт заменяется заглушкой, приложение прячется.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Статистика") {
                Toggle("Учитывать сайты в браузере", isOn: $t.trackSites)
                Text("Всё хранится только на этом Маке: ~/Library/Application Support/Orbit").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SnippetsTab: View {
    @State private var items = Snippets.all
    @State private var sel: UUID?
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                List(selection: $sel) {
                    ForEach(items) { s in Text(s.name).tag(s.id) }
                }
                HStack {
                    Button { let s = Snippet(name: "Новый", text: ""); items.append(s); sel = s.id; save() } label: { Image(systemName: "plus") }
                    Button { items.removeAll { $0.id == sel }; sel = nil; save() } label: { Image(systemName: "minus") }.disabled(sel == nil)
                    Spacer()
                }
            }
            .frame(width: 170)
            if let i = items.firstIndex(where: { $0.id == sel }) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Название", text: $items[i].name).onChange(of: items[i].name) { save() }
                    TextEditor(text: $items[i].text).font(.system(size: 12, design: .monospaced))
                        .onChange(of: items[i].text) { save() }
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    Text("Подстановки: {date} {time} {clipboard} {uuid}").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Выбери сниппет слева.\nВ палитре: ↵ — вставить, ⌘↵ — скопировать.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    private func save() { Snippets.all = items }
}

private struct KeysTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                row(AppDelegate.paletteKeys[AppDelegate.paletteIndex].label, "Палитра команд")
                row("⌃⌥P", "Фокус: старт / стоп")
                Divider().padding(.vertical, 4)
                ForEach(WinAction.allCases.filter { $0.hotkey != nil }, id: \.self) { a in row(a.hotkeyLabel, a.title) }
                Text("Повторное нажатие ⌃⌥←/→/↑/↓ меняет размер: ½ → ⅔ → ⅓").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            .padding(4)
        }
    }
    private func row(_ k: String, _ t: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12, weight: .semibold, design: .rounded)).frame(width: 90, alignment: .leading)
            Text(t).font(.system(size: 12))
            Spacer()
        }
    }
}
