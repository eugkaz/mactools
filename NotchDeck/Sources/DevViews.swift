import AppKit
import SwiftUI

struct DevTab: View {
    let ports: PortsStore
    let snippets: SnippetStore
    @AppStorage("devSection") private var section = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlatSegmented(items: [(0, "Утилиты"), (1, "Порты"), (2, "Команды")], selection: section) { section = $0 }
                .padding(.leading, 2)
            switch section {
            case 1: PortsView(store: ports)
            case 2: SnippetsView(store: snippets)
            default: UtilitiesView()
            }
        }
    }
}

struct UtilitiesView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?
    let cols = [GridItem(.adaptive(minimum: 62), spacing: 4)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                editor($input, placeholder: "Вход")
                editor(.constant(error ?? output), placeholder: "Результат", readOnly: true)
                    .foregroundStyle(error != nil ? Color.orange : Color.white)
            }
            ScrollView { VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    SmallButton(icon: "doc.on.clipboard", title: "Буфер") { input = NSPasteboard.general.string(forType: .string) ?? "" }
                    SmallButton(icon: "doc.on.doc", title: "Копия") { copyToPasteboard(output) }
                    SmallButton(icon: "arrow.up", title: nil) { input = output }
                }
                LazyVGrid(columns: cols, spacing: 5) {
                    ForEach(Transform.allCases) { t in
                        Button { run(t) } label: { Text(t.rawValue).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).pill() }
                            .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 5) {
                    SmallButton(icon: "number", title: "UUID") { output = UUID().uuidString.lowercased(); error = nil; copyToPasteboard(output) }
                    SmallButton(icon: "eyedropper", title: "Пипетка") { pickColor() }
                    SmallButton(icon: "key", title: "Пароль") { output = password(); error = nil; copyToPasteboard(output) }
                }
            } }
            .frame(width: 200)
        }
    }

    func editor(_ text: Binding<String>, placeholder: String, readOnly: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .disabled(readOnly && text.wrappedValue.isEmpty)
            if text.wrappedValue.isEmpty {
                Text(placeholder).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).padding(.leading, 5).allowsHitTesting(false)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ND.soft))
    }

    func run(_ t: Transform) {
        do { output = try t.apply(input); error = nil } catch { self.error = error.localizedDescription }
    }

    func pickColor() {
        NSColorSampler().show { c in
            guard let c = c?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            output = "\(hex)\nrgb(\(Int(round(c.redComponent * 255))), \(Int(round(c.greenComponent * 255))), \(Int(round(c.blueComponent * 255))))"
            error = nil
            copyToPasteboard(hex)
        }
    }

    func password() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*-_=+")
        var g = SystemRandomNumberGenerator()
        return String((0..<20).map { _ in chars.randomElement(using: &g)! })
    }
}

struct PortsView: View {
    let store: PortsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                DeckLabel(text: "Слушающие TCP-порты")
                if store.loading { ProgressView().controlSize(.mini) }
                Spacer()
                GhostIcon(icon: "arrow.clockwise", help: "Обновить") { store.refresh() }
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.entries) { e in
                        HStack(spacing: 10) {
                            LiveDot(color: Accent.mint.a, active: true)
                            Text(":" + e.port).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).frame(width: 62, alignment: .leading).foregroundStyle(accent)
                            Text(e.command).font(.system(size: 12, weight: .medium)).frame(width: 100, alignment: .leading).lineLimit(1)
                            Text("pid \(e.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            GhostIcon(icon: "safari", help: "Открыть в браузере") { NSWorkspace.shared.open(URL(string: "http://localhost:\(e.port)")!) }
                            GhostIcon(icon: "xmark.octagon", help: "Завершить процесс (ПКМ — kill -9)") { store.kill(e) }
                                .contextMenu { Button("kill -9") { store.kill(e, force: true) } }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ND.soft))
                    }
                    if store.entries.isEmpty && !store.loading {
                        Text("Нет открытых портов (показываются процессы текущего пользователя)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding()
                    }
                }
            }
        }
        .onAppear { store.refresh() }
    }
}

struct SnippetsView: View {
    let store: SnippetStore
    @State private var adding = false
    @State private var name = ""
    @State private var cmd = ""
    @State private var term = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.items) { s in
                            HStack {
                                Image(systemName: s.inTerminal ? "terminal" : "play.fill").font(.system(size: 9.5)).foregroundStyle(DS.text3).frame(width: 14)
                                Text(s.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                if store.running == s.id { ProgressView().controlSize(.mini) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ND.soft))
                            .contentShape(Rectangle())
                            .onTapGesture { store.run(s) }
                            .help(s.command)
                            .contextMenu {
                                Button("Запустить") { store.run(s) }
                                Button("Открыть в Терминале") { Shell.inTerminal(s.command) }
                                Button("Скопировать команду") { copyToPasteboard(s.command) }
                                Button("Удалить") { store.remove(s) }
                            }
                        }
                    }
                }
                if adding {
                    TextField("Название", text: $name).textFieldStyle(.roundedBorder).controlSize(.small)
                    TextField("Команда (zsh)", text: $cmd).textFieldStyle(.roundedBorder).controlSize(.small).font(.system(size: 11, design: .monospaced))
                    HStack {
                        Toggle("В Терминале", isOn: $term).controlSize(.small)
                        Spacer()
                        Button("Отмена") { adding = false }.controlSize(.small)
                        Button("Добавить") {
                            store.add(Snippet(name: name.isEmpty ? cmd : name, command: cmd, inTerminal: term))
                            name = ""; cmd = ""; term = false; adding = false
                        }.controlSize(.small).disabled(cmd.isEmpty)
                    }
                } else {
                    SmallButton(icon: "plus", title: "Своя команда") { adding = true }
                }
            }
            .frame(width: 170)
            ScrollView {
                Text(store.output.isEmpty ? "Нажмите на команду — вывод появится здесь.\nПКМ — открыть в Терминале, копировать, удалить." : store.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(store.output.isEmpty ? .white.opacity(0.4) : .white.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.4)))
        }
    }
}

// MARK: - System

struct SystemTab: View {
    let sys: SystemMonitor
    @State private var dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                gauge("CPU", sys.cpu, "\(Int(sys.cpu * 100))%", "cpu")
                HairDivider(vertical: true)
                gauge("Память", sys.memUsed / max(sys.memTotal, 1), SystemMonitor.bytes(sys.memUsed), "memorychip")
                HairDivider(vertical: true)
                gauge("Диск", sys.diskTotal > 0 ? 1 - sys.diskFree / sys.diskTotal : 0, SystemMonitor.bytes(sys.diskFree), "internaldrive")
                if let b = sys.battery {
                    HairDivider(vertical: true)
                    gauge(sys.charging ? "Батарея ⚡︎" : "Батарея", Double(b) / 100, "\(b)%", "battery.75percent")
                }
            }
            .padding(.horizontal, 4).padding(.top, 2)
            HStack(spacing: 14) {
                info("arrow.down", "\(SystemMonitor.bytes(sys.netIn))/с")
                info("arrow.up", "\(SystemMonitor.bytes(sys.netOut))/с")
                info("wifi", sys.localIP)
                info("clock", sys.uptime)
                Spacer()
            }
            DeckLabel(text: "Быстрые действия")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                SmallButton(icon: sys.caffeinated ? "cup.and.saucer.fill" : "cup.and.saucer", title: sys.caffeinated ? "Не засыпать: вкл" : "Не засыпать", active: sys.caffeinated) { sys.toggleCaffeine() }
                SmallButton(icon: sys.hiddenFiles ? "eye" : "eye.slash", title: "Скрытые файлы", active: sys.hiddenFiles) { sys.toggleHiddenFiles() }
                SmallButton(icon: "circle.lefthalf.filled", title: "Тёмная тема", active: dark) {
                    AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
                    dark.toggle()
                }
                SmallButton(icon: "camera.viewfinder", title: "Скрин в буфер") {
                    AppDelegate.shared?.close()
                    Task { _ = await Shell.run("/usr/sbin/screencapture", ["-i", "-c"]) }
                }
                SmallButton(icon: "display", title: "Погасить экран") { Task { _ = await Shell.run("/usr/bin/pmset", ["displaysleepnow"]) } }
                SmallButton(icon: "chart.bar", title: "Мониторинг") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
            }
        } }
    }

    /// Показатель: моно-подпись, крупное значение, сегментный LED-индикатор
    func gauge(_ title: String, _ v: Double, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title.uppercased()).font(ND.mono).tracking(1.2).foregroundStyle(DS.text3).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: icon).font(.system(size: 8.5, weight: .medium)).foregroundStyle(DS.text3)
            }
            Text(label).font(DS.font(15, .semibold, rounded: true)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            LEDMeter(value: v)
        }
        .frame(maxWidth: .infinity)
    }

    func info(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.text3)
            Text(text).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(DS.text2)
        }
    }
}
