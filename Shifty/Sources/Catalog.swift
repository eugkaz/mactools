import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct ShiftAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var isEdit = false
    var copiesToClipboard = false
    let run: ([URL]) async throws -> [URL]
}

enum Catalog {
    static func each(_ f: @escaping (URL) async throws -> URL) -> ([URL]) async throws -> [URL] {
        { urls in
            var r: [URL] = []
            for u in urls { r.append(try await f(u)) }
            return r
        }
    }

    static func actions(for urls: [URL]) -> [ShiftAction] {
        guard !urls.isEmpty else { return [] }
        let kinds = Set(urls.map(Files.kind))
        let exts = Set(urls.map { $0.pathExtension.lowercased() })
        let ff = Tools.ffmpegPath != nil
        let single = urls.count == 1
        var list: [ShiftAction] = []

        func add(_ id: String, _ title: String, _ sub: String, _ icon: String, same: [String] = [],
                 _ f: @escaping (URL) async throws -> URL) {
            if !same.isEmpty && exts.isSubset(of: Set(same)) { return }
            list.append(ShiftAction(id: id, title: title, subtitle: sub, icon: icon, run: each(f)))
        }
        func edit(_ sub: String) {
            if single { list.append(ShiftAction(id: "edit", title: "Редактор", subtitle: sub, icon: "slider.horizontal.3", isEdit: true, run: { _ in [] })) }
        }

        if kinds.count == 1, let k = kinds.first {
            switch k {
            case .image:
                edit("дизайн, текст, фильтры")
                add("png", "PNG", "без потерь", "photo", same: ["png"]) { try await Imaging.convert($0, ext: "png", uti: UTType.png.identifier) }
                add("jpg", "JPEG", "качество 90%", "photo.fill", same: ["jpg", "jpeg"]) { try await Imaging.convert($0, ext: "jpg", uti: UTType.jpeg.identifier) }
                add("heic", "HEIC", "компактно", "camera", same: ["heic"]) { try await Imaging.convert($0, ext: "heic", uti: UTType.heic.identifier, quality: 0.8) }
                if Imaging.canWrite(Imaging.webp) {
                    add("webp", "WebP", "для веба", "globe", same: ["webp"]) { try await Imaging.convert($0, ext: "webp", uti: Imaging.webp, quality: 0.85) }
                }
                if Imaging.canWrite("public.avif") {
                    add("avif", "AVIF", "для веба", "sparkles", same: ["avif"]) { try await Imaging.convert($0, ext: "avif", uti: "public.avif", quality: 0.75) }
                }
                add("tiff", "TIFF", "для печати", "printer", same: ["tif", "tiff"]) { try await Imaging.convert($0, ext: "tiff", uti: UTType.tiff.identifier) }
                list.append(ShiftAction(id: "pdf", title: "PDF", subtitle: single ? "документ" : "один альбом", icon: "doc.richtext",
                                        run: { urls in [try Imaging.mergeToPDF(urls)] }))
                if Imaging.canWrite("com.apple.icns") {
                    add("icns", "ICNS", "иконка Mac", "app.dashed") { try await Imaging.convert($0, ext: "icns", uti: "com.apple.icns", squareSize: 1024) }
                }
                if Imaging.canWrite("com.microsoft.ico") {
                    add("ico", "ICO", "favicon 256", "star.square") { try await Imaging.convert($0, ext: "ico", uti: "com.microsoft.ico", squareSize: 256) }
                }
                add("small", "Сжать", "JPEG 70%", "arrow.down.right.and.arrow.up.left") {
                    try await Imaging.convert($0, ext: "jpg", uti: UTType.jpeg.identifier, quality: 0.7, suffix: " (сжато)")
                }
                add("half", "50%", "уменьшить", "minus.magnifyingglass") { src in
                    let ext = src.pathExtension.lowercased()
                    let uti = UTType(filenameExtension: ext)?.identifier ?? UTType.png.identifier
                    let ok = Imaging.canWrite(uti)
                    return try await Imaging.convert(src, ext: ok ? ext : "png", uti: ok ? uti : UTType.png.identifier, scale: 0.5, suffix: " (50%)")
                }

            case .video:
                edit("монтаж, текст, музыка")
                if ff {
                    add("mp4", "MP4", "H.264", "film", same: ["mp4"]) { try await Media.ff($0, ext: "mp4", Media.mp4Args) }
                    add("mov", "MOV", "QuickTime", "film.stack", same: ["mov"]) { try await Media.ff($0, ext: "mov", Media.mp4Args) }
                    add("hevc", "HEVC", "H.265, легче", "bolt") { try await Media.ff($0, ext: "mp4", Media.hevcArgs, suffix: " (HEVC)") }
                    add("webm", "WebM", "VP9 для веба", "globe", same: ["webm"]) { try await Media.ff($0, ext: "webm", Media.webmArgs) }
                    add("gif", "GIF", "анимация", "photo.stack") { try await Media.ff($0, ext: "gif", ["-filter_complex", Media.gifFilter, "-loop", "0"]) }
                    add("mp3", "MP3", "только звук", "music.note") { try await Media.ff($0, ext: "mp3", ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]) }
                    add("m4a", "M4A", "только звук", "waveform") { try await Media.ff($0, ext: "m4a", ["-vn", "-c:a", "aac", "-b:a", "192k"]) }
                    add("compress", "Сжать", "720p, CRF 28", "arrow.down.right.and.arrow.up.left") { try await Media.ff($0, ext: "mp4", Media.compressArgs, suffix: " (сжато)") }
                } else {
                    add("mp4", "MP4", "H.264", "film", same: ["mp4"]) { try await Media.av($0, preset: AVAssetExportPresetHighestQuality, type: .mp4, ext: "mp4") }
                    add("mov", "MOV", "QuickTime", "film.stack", same: ["mov"]) { try await Media.av($0, preset: AVAssetExportPresetHighestQuality, type: .mov, ext: "mov") }
                    add("hevc", "HEVC", "H.265", "bolt") { try await Media.av($0, preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4, ext: "mp4", suffix: " (HEVC)") }
                    add("m4a", "M4A", "только звук", "waveform") { try await Media.av($0, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a") }
                    add("compress", "Сжать", "720p", "arrow.down.right.and.arrow.up.left") { try await Media.av($0, preset: AVAssetExportPreset1280x720, type: .mp4, ext: "mp4", suffix: " (сжато)") }
                }
                add("frame", "Кадр", "PNG превью", "photo.on.rectangle") { try await Media.frame($0) }

            case .audio:
                edit("обрезка")
                if ff {
                    add("mp3", "MP3", "320 VBR", "music.note", same: ["mp3"]) { try await Media.ff($0, ext: "mp3", ["-vn", "-c:a", "libmp3lame", "-q:a", "0"]) }
                    add("m4a", "M4A", "AAC 256k", "waveform", same: ["m4a"]) { try await Media.ff($0, ext: "m4a", ["-vn", "-c:a", "aac", "-b:a", "256k"]) }
                    add("wav", "WAV", "без сжатия", "waveform.path", same: ["wav"]) { try await Media.ff($0, ext: "wav", ["-vn", "-c:a", "pcm_s16le"]) }
                    add("flac", "FLAC", "lossless", "hifispeaker", same: ["flac"]) { try await Media.ff($0, ext: "flac", ["-vn", "-c:a", "flac"]) }
                    add("opus", "Opus", "голос/веб", "mic", same: ["opus", "ogg"]) { try await Media.ff($0, ext: "opus", ["-vn", "-c:a", "libopus", "-b:a", "96k"]) }
                    add("aiff", "AIFF", "Apple PCM", "waveform.circle", same: ["aiff", "aif"]) { try await Media.ff($0, ext: "aiff", ["-vn"]) }
                } else {
                    add("m4a", "M4A", "AAC 256k", "waveform", same: ["m4a"]) { try await Media.afconvert($0, ext: "m4a", ["-f", "m4af", "-d", "aac", "-b", "256000"]) }
                    add("wav", "WAV", "без сжатия", "waveform.path", same: ["wav"]) { try await Media.afconvert($0, ext: "wav", ["-f", "WAVE", "-d", "LEI16"]) }
                    add("aiff", "AIFF", "Apple PCM", "waveform.circle", same: ["aiff", "aif"]) { try await Media.afconvert($0, ext: "aiff", ["-f", "AIFF", "-d", "BEI16"]) }
                    add("flac", "FLAC", "lossless", "hifispeaker", same: ["flac"]) { try await Media.afconvert($0, ext: "flac", ["-f", "flac", "-d", "flac"]) }
                }

            case .text:
                if single && Files.isPlainText(urls[0]) { edit("быстрая правка") }
                add("pdf", "PDF", "для печати", "doc.richtext") { try await Docs.toPDF($0) }
                add("docx", "DOCX", "Word", "doc.text", same: ["docx"]) { try await Docs.textutil($0, format: "docx", ext: "docx") }
                add("txt", "TXT", "чистый текст", "text.alignleft", same: ["txt"]) { try await Docs.textutil($0, format: "txt", ext: "txt") }
                add("rtf", "RTF", "форматированный", "textformat", same: ["rtf"]) { try await Docs.textutil($0, format: "rtf", ext: "rtf") }
                add("html", "HTML", "веб-страница", "chevron.left.forwardslash.chevron.right", same: ["html", "htm"]) { try await Docs.textutil($0, format: "html", ext: "html") }
                add("odt", "ODT", "LibreOffice", "doc", same: ["odt"]) { try await Docs.textutil($0, format: "odt", ext: "odt") }

            case .pdf:
                add("png", "PNG", "все страницы", "photo.on.rectangle.angled") { try await PDFTools.toImages($0) }
                add("txt", "TXT", "извлечь текст", "text.alignleft") { try PDFTools.toText($0) }
                add("compress", "Сжать", "для экрана", "arrow.down.right.and.arrow.up.left") { try PDFTools.compress($0) }
                if !single {
                    list.append(ShiftAction(id: "merge", title: "Склеить", subtitle: "в один PDF", icon: "rectangle.stack", run: { [try PDFTools.merge($0)] }))
                }

            case .folder, .other:
                break
            }
        }

        add("zip", "ZIP", "архив", "doc.zipper", same: ["zip"]) { try await Universal.zip($0) }
        list.append(ShiftAction(id: "path", title: "Путь", subtitle: "скопировать", icon: "link", copiesToClipboard: true, run: { urls in
            Universal.copy(urls.map(\.path).joined(separator: "\n")); return []
        }))
        if single && kinds != [.folder] {
            list.append(ShiftAction(id: "b64", title: "Base64", subtitle: "в буфер", icon: "number", copiesToClipboard: true, run: { urls in
                try Universal.base64(urls[0]); return []
            }))
        }
        return list
    }
}
