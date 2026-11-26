import Foundation
import AVFoundation
import AppKit

/// Данные записи: курсор и клики (нормализованы 0…1, начало — левый верхний угол)
struct RecMeta: Codable {
    var duration: Double = 0
    var pixelW = 0, pixelH = 0
    var samples: [[Double]] = []      // [t, x, y]
    var clicks: [[Double]] = []       // [t, x, y]
    var customCursor = true
    var created = Date()
}

/// Настройки оформления (живут вместе с записью)
struct Style: Codable, Equatable {
    var bg = 0
    var padding = 0.07
    var radius = 0.018
    var shadow = 0.6
    var zoom = 2.0
    var autoZoom = true
    var cursorSize = 1.5
    var smoothCursor = true
    var ripple = true
    var outWidth = 1920
    var trimStart = 0.0
    var trimEnd: Double? = nil
}

struct ZoomSeg: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var scale: Double
    var enabled = true
}

/// Запись на диске: video.mov + meta.json + edit.json в папке ~/Movies/Reel/<имя>.reel/
struct Recording: Identifiable, Hashable {
    let dir: URL
    var id: URL { dir }
    var video: URL { dir.appendingPathComponent("video.mov") }
    var metaURL: URL { dir.appendingPathComponent("meta.json") }
    var editURL: URL { dir.appendingPathComponent("edit.json") }
    var thumbURL: URL { dir.appendingPathComponent("thumb.jpg") }
    var name: String { dir.deletingPathExtension().lastPathComponent }

    static var root: URL {
        let u = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Reel")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func new() -> Recording {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'в' HH.mm.ss"
        let d = root.appendingPathComponent("Запись \(f.string(from: Date())).reel")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Recording(dir: d)
    }
    static func all() -> [Recording] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items.filter { $0.pathExtension == "reel" && FileManager.default.fileExists(atPath: $0.appendingPathComponent("video.mov").path) }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            .map(Recording.init)
    }

    func loadMeta() -> RecMeta { (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(RecMeta.self, from: $0) } ?? RecMeta() }
    func saveMeta(_ m: RecMeta) { try? JSONEncoder().encode(m).write(to: metaURL) }

    struct Edit: Codable { var style: Style; var segs: [ZoomSeg] }
    func loadEdit() -> Edit? { (try? Data(contentsOf: editURL)).flatMap { try? JSONDecoder().decode(Edit.self, from: $0) } }
    func saveEdit(_ e: Edit) { try? JSONEncoder().encode(e).write(to: editURL) }

    var thumbnail: NSImage? { NSImage(contentsOf: thumbURL) }
    func makeThumbnail() async {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        g.maximumSize = CGSize(width: 480, height: 300)
        g.appliesPreferredTrackTransform = true
        if let (img, _) = try? await g.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: thumbURL)
        }
    }
}

extension URL {
    var creationDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
