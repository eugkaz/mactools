import AppKit
import Observation

enum Phase: Equatable {
    case choosing
    case working(String)
    case done([URL], String)
    case failed(String)
}

@Observable
final class ShiftyModel {
    var urls: [URL] = []
    var actions: [ShiftAction] = []
    var phase: Phase = .choosing { didSet { onPhase?(phase) } }
    @ObservationIgnored var onPhase: ((Phase) -> Void)?
    var pinned = false
    var hovered: ShiftAction?
    var appearTick = 0

    @ObservationIgnored var onEdit: ((URL) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private var hideWork: DispatchWorkItem?

    var title: String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) файлов"
    }

    func load(_ urls: [URL], pinned: Bool) {
        hideWork?.cancel()
        self.urls = urls
        self.pinned = pinned
        phase = .choosing
        hovered = nil
        actions = Catalog.actions(for: urls)
    }

    var isBusy: Bool {
        if case .choosing = phase { return false }
        return true
    }

    func perform(_ a: ShiftAction) {
        guard case .choosing = phase else { return }
        if a.isEdit {
            if let u = urls.first { onEdit?(u) }
            onClose?()
            return
        }
        let urls = self.urls
        phase = .working(a.title)
        Task { @MainActor in
            do {
                let outs = try await a.run(urls)
                self.phase = .done(outs, a.copiesToClipboard ? "Скопировано в буфер" : "Готово: \(a.title)")
                if a.copiesToClipboard { NSSound(named: "Pop")?.play() } else { NSSound(named: "Glass")?.play() }
                self.scheduleHide(a.copiesToClipboard ? 1.2 : 5)
            } catch {
                self.phase = .failed(error.localizedDescription)
                NSSound(named: "Basso")?.play()
                self.scheduleHide(8)
            }
        }
    }

    func scheduleHide(_ delay: Double) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onClose?() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func cancelHide() { hideWork?.cancel() }
}
