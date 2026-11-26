import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ShiftyError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

enum FileKind { case image, video, audio, pdf, text, folder, other }

enum Files {
    static let videoExt: Set<String> = ["mkv", "webm", "avi", "flv", "wmv", "m4v", "mts", "ts", "mpg", "mpeg", "3gp"]
    static let audioExt: Set<String> = ["ogg", "opus", "flac", "wma", "mp3", "wav", "aiff", "aif", "m4a", "aac", "caf"]
    static let richTextExt: Set<String> = ["doc", "docx", "odt", "rtf", "rtfd", "html", "htm", "webarchive"]

    static func kind(_ url: URL) -> FileKind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return .folder }
        let ext = url.pathExtension.lowercased()
        if videoExt.contains(ext) { return .video }
        if audioExt.contains(ext) { return .audio }
        if richTextExt.contains(ext) { return .text }
        guard let t = UTType(filenameExtension: ext) else { return .other }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .audiovisualContent) { return .video }
        if isPlainText(url) { return .text }
        return .other
    }

    static func isPlainText(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["md", "txt", "log", "env", "yml", "yaml", "toml", "ini", "conf", "csv"].contains(ext) { return true }
        guard let t = UTType(filenameExtension: ext) else { return false }
        return t.conforms(to: .plainText) || t.conforms(to: .sourceCode) || t.conforms(to: .json)
            || t.conforms(to: .xml) || t.conforms(to: .shellScript) || t.conforms(to: .propertyList)
    }

    static func outputURL(for src: URL, ext: String, suffix: String = "") -> URL {
        let dir = src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent + suffix
        func make(_ name: String) -> URL {
            let u = dir.appendingPathComponent(name)
            return ext.isEmpty ? u : u.appendingPathExtension(ext)
        }
        var u = make(base)
        var i = 2
        while FileManager.default.fileExists(atPath: u.path) { u = make("\(base) \(i)"); i += 1 }
        return u
    }
}

enum Tools {
    static let ffmpegPath: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) async throws -> String {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("shifty-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { proc in
                try? handle.close()
                let out = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: log)
                if proc.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    let tail = String(out.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: ShiftyError(tail.isEmpty ? "Ошибка (код \(proc.terminationStatus))" : tail))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    static func ffmpeg(_ args: [String]) async throws {
        guard let f = ffmpegPath else { throw ShiftyError("Нужен ffmpeg: brew install ffmpeg") }
        try await run(f, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + args)
    }
}

// MARK: - Images

enum Imaging {
    static let writable: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    static let webp = "org.webmproject.webp"

    static func canWrite(_ uti: String) -> Bool {
        writable.contains(uti) || uti == "com.apple.icns" || (uti == webp && Tools.ffmpegPath != nil)
    }

    static func load(_ url: URL, scale: Double = 1) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ShiftyError("Не удалось открыть изображение")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 4096
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 4096
        let maxPx = max(1, Int((Double(max(w, h)) * scale).rounded()))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            throw ShiftyError("Не удалось прочитать изображение")
        }
        return cg
    }

    static func flatten(_ cg: CGImage) -> CGImage {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    static func square(_ cg: CGImage, size: Int) -> CGImage {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        let s = Double(size) / Double(max(cg.width, cg.height))
        let w = Double(cg.width) * s, h = Double(cg.height) * s
        ctx.draw(cg, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    static func write(_ cg: CGImage, to out: URL, uti: String, quality: Double) async throws {
        var img = cg
        if uti == "com.apple.icns" {
            let set = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).iconset")
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: set) }
            for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                               (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
                try await write(square(cg, size: px), to: set.appendingPathComponent("icon_\(name).png"), uti: UTType.png.identifier, quality: 1)
            }
            try await Tools.run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", out.path])
            return
        }
        if uti == UTType.jpeg.identifier || uti == UTType.bmp.identifier { img = flatten(cg) }
        if writable.contains(uti) {
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else {
                throw ShiftyError("Не удалось создать файл")
            }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ShiftyError("Не удалось записать файл") }
            return
        }
        if uti == webp {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
            try await write(img, to: tmp, uti: UTType.png.identifier, quality: 1)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await Tools.ffmpeg(["-i", tmp.path, "-c:v", "libwebp", "-quality", "\(Int(quality * 100))", out.path])
            return
        }
        throw ShiftyError("Формат не поддерживается")
    }

    static func convert(_ src: URL, ext: String, uti: String, quality: Double = 0.9, scale: Double = 1,
                        suffix: String = "", squareSize: Int? = nil) async throws -> URL {
        var cg = try load(src, scale: scale)
        if let s = squareSize { cg = square(cg, size: s) }
        let out = Files.outputURL(for: src, ext: ext, suffix: suffix)
        try await write(cg, to: out, uti: uti, quality: quality)
        return out
    }

    static func mergeToPDF(_ urls: [URL]) throws -> URL {
        let doc = PDFDocument()
        for u in urls {
            let cg = try load(u)
            let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            if let page = PDFPage(image: ns) { doc.insert(page, at: doc.pageCount) }
        }
        let out = Files.outputURL(for: urls[0], ext: "pdf", suffix: urls.count > 1 ? " (альбом)" : "")
        guard doc.write(to: out) else { throw ShiftyError("Не удалось записать PDF") }
        return out
    }
}

// MARK: - Audio / Video

enum Media {
    static func ff(_ src: URL, ext: String, _ args: [String], suffix: String = "") async throws -> URL {
        let out = Files.outputURL(for: src, ext: ext, suffix: suffix)
        try await Tools.ffmpeg(["-i", src.path] + args + [out.path])
        return out
    }

    static func av(_ src: URL, preset: String, type: AVFileType, ext: String, suffix: String = "",
                   range: CMTimeRange? = nil) async throws -> URL {
        let asset = AVURLAsset(url: src)
        if type == .m4a, ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty {
            throw ShiftyError("В этом видео нет звука")
        }
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ShiftyError("Этот файл нельзя экспортировать без ffmpeg")
        }
        if let range { s.timeRange = range }
        let out = Files.outputURL(for: src, ext: ext, suffix: suffix)
        try await s.export(to: out, as: type)
        return out
    }

    static func afconvert(_ src: URL, ext: String, _ args: [String]) async throws -> URL {
        let out = Files.outputURL(for: src, ext: ext)
        try await Tools.run("/usr/bin/afconvert", args + [src.path, out.path])
        return out
    }

    static func frame(_ src: URL) async throws -> URL {
        let asset = AVURLAsset(url: src)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let dur = try await asset.load(.duration)
        let t = CMTime(seconds: min(1, dur.seconds / 2), preferredTimescale: 600)
        let (cg, _) = try await gen.image(at: t)
        let out = Files.outputURL(for: src, ext: "png", suffix: " (кадр)")
        try await Imaging.write(cg, to: out, uti: UTType.png.identifier, quality: 1)
        return out
    }

    static let gifFilter = "fps=12,scale='min(560,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4"
    static let mp4Args = ["-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
    static let hevcArgs = ["-c:v", "hevc_videotoolbox", "-q:v", "62", "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
    static let webmArgs = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good", "-cpu-used", "4", "-c:a", "libopus"]
    static let compressArgs = ["-vf", "scale='min(1280,iw)':-2", "-c:v", "libx264", "-preset", "medium", "-crf", "28", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
}

// MARK: - Documents

enum Docs {
    static func textutil(_ src: URL, format: String, ext: String) async throws -> URL {
        let out = Files.outputURL(for: src, ext: ext)
        try await Tools.run("/usr/bin/textutil", ["-convert", format, "-output", out.path, src.path])
        return out
    }

    @MainActor
    static func toPDF(_ src: URL) throws -> URL {
        let attr: NSAttributedString
        if Files.isPlainText(src) {
            let s = try String(contentsOf: src, encoding: .utf8)
            attr = NSAttributedString(string: s, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)])
        } else {
            attr = try NSAttributedString(url: src, options: [:], documentAttributes: nil)
        }
        let out = Files.outputURL(for: src, ext: "pdf")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = out
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        for m in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] { info[keyPath: m] = 42 }
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.textStorage?.setAttributedString(attr)
        tv.isVerticallyResizable = true
        tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw ShiftyError("Не удалось создать PDF") }
        return out
    }
}

enum PDFTools {
    static func toImages(_ src: URL) async throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw ShiftyError("Не удалось открыть PDF") }
        let folder = Files.outputURL(for: src, ext: "", suffix: " (страницы)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let img = page.thumbnail(of: NSSize(width: b.width * 2, height: b.height * 2), for: .mediaBox)
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let out = folder.appendingPathComponent(String(format: "page-%03d.png", i + 1))
            try await Imaging.write(cg, to: out, uti: UTType.png.identifier, quality: 1)
        }
        return folder
    }

    static func toText(_ src: URL) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw ShiftyError("Не удалось открыть PDF") }
        let out = Files.outputURL(for: src, ext: "txt")
        try (doc.string ?? "").write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func compress(_ src: URL) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw ShiftyError("Не удалось открыть PDF") }
        let out = Files.outputURL(for: src, ext: "pdf", suffix: " (сжато)")
        guard doc.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]) else {
            throw ShiftyError("Не удалось записать PDF")
        }
        return out
    }

    static func merge(_ urls: [URL]) throws -> URL {
        let doc = PDFDocument()
        for u in urls {
            guard let d = PDFDocument(url: u) else { continue }
            for i in 0..<d.pageCount { if let p = d.page(at: i) { doc.insert(p, at: doc.pageCount) } }
        }
        let out = Files.outputURL(for: urls[0], ext: "pdf", suffix: " (объединено)")
        guard doc.write(to: out) else { throw ShiftyError("Не удалось записать PDF") }
        return out
    }
}

// MARK: - Universal

enum Universal {
    static func zip(_ src: URL) async throws -> URL {
        let out = Files.outputURL(for: src, ext: "zip")
        try await Tools.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", src.path, out.path])
        return out
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    static func base64(_ src: URL) throws {
        let data = try Data(contentsOf: src)
        guard data.count < 15_000_000 else { throw ShiftyError("Файл больше 15 МБ") }
        let b = data.base64EncodedString()
        if Files.kind(src) == .image, let mime = UTType(filenameExtension: src.pathExtension)?.preferredMIMEType {
            copy("data:\(mime);base64,\(b)")
        } else {
            copy(b)
        }
    }
}
