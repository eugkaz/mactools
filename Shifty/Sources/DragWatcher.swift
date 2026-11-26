import AppKit

/// Следит за глобальным перетаскиванием файлов: если во время drag зажат Shift — сообщает.
/// Работает без прав Универсального доступа: опрашивает кнопки мыши, модификаторы и drag-pasteboard.
final class DragWatcher {
    var onShiftDrag: (([URL]) -> Void)?
    var onMouseUp: (() -> Void)?
    var enabled = true

    private var timer: Timer?
    private var wasDown = false
    private var startCount = 0
    private var dragging = false
    private var fired = false
    private var urls: [URL] = []
    private let pb = NSPasteboard(name: .drag)

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        RunLoop.main.add(timer!, forMode: .eventTracking)
    }

    private func tick() {
        let down = NSEvent.pressedMouseButtons & 1 == 1
        if down && !wasDown {
            startCount = pb.changeCount
            dragging = false
            fired = false
            urls = []
        }
        if down && enabled {
            if !dragging && pb.changeCount != startCount { dragging = true }
            // Браузеры и Фото кладут файл в pasteboard с задержкой — перечитываем, пока пусто
            if dragging && urls.isEmpty {
                urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            }
            if dragging && !fired && !urls.isEmpty && NSEvent.modifierFlags.contains(.shift) {
                fired = true
                onShiftDrag?(urls)
            }
        }
        if !down && wasDown {
            if fired { onMouseUp?() }
            dragging = false
            fired = false
        }
        wasDown = down
    }
}
