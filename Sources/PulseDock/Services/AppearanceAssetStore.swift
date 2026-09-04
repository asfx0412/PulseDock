import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns only PulseDock's processed background copies.  Original user files
/// are never referenced after import, so moving or deleting the source image
/// cannot break the UI.  PNG output intentionally drops EXIF/GPS metadata.
enum AppearanceAssetStore {
    enum StoreError: LocalizedError {
        case unsupportedFormat
        case tooLarge
        case tooManyPixels
        case dimensionsTooLarge
        case unreadable
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "仅支持 PNG、JPEG 或 HEIC 图片"
            case .tooLarge: "图片文件不能超过 25 MB"
            case .tooManyPixels: "图片像素不能超过 8000 万"
            case .dimensionsTooLarge: "图片单边不能超过 16384 像素"
            case .unreadable: "无法读取这张图片"
            case .writeFailed: "无法保存处理后的背景图"
            }
        }
    }

    private static let maxFileBytes = 25 * 1_024 * 1_024
    private static let maxPixels = 80_000_000
    private static let maxDimension = 16_384

    static func importImage(at source: URL, maximumPixelSize: Int) throws -> String {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let type = values.contentType,
              [UTType.png, .jpeg, .heic].contains(where: { type.conforms(to: $0) }) else { throw StoreError.unsupportedFormat }
        guard (values.fileSize ?? 0) <= maxFileBytes else { throw StoreError.tooLarge }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw StoreError.unreadable }
        guard width <= maxDimension, height <= maxDimension else { throw StoreError.dimensionsTooLarge }
        guard width > 0, height > 0, width <= maxPixels / max(1, height) else { throw StoreError.tooManyPixels }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { throw StoreError.unreadable }
        let id = UUID().uuidString.lowercased()
        let destination = imageURL(id)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(id).tmp")
        try FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
        guard let writer = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw StoreError.writeFailed }
        // Only the generated pixel data goes into PNG; source EXIF/GPS does not.
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw StoreError.writeFailed }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return id
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw StoreError.writeFailed
        }
    }

    static func image(for id: String?) -> NSImage? {
        guard let id, isSafeID(id) else { return nil }
        return NSImage(contentsOf: imageURL(id))
    }

    static func remove(id: String?) {
        guard let id, isSafeID(id) else { return }
        try? FileManager.default.removeItem(at: imageURL(id))
    }

    static func removeUnused(keeping ids: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directoryURL(), includingPropertiesForKeys: nil) else { return }
        for url in contents where url.pathExtension == "png" {
            let id = url.deletingPathExtension().lastPathComponent
            if !ids.contains(id), isSafeID(id) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func directoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PulseDock", isDirectory: true).appendingPathComponent("Appearance", isDirectory: true)
    }

    private static func imageURL(_ id: String) -> URL { directoryURL().appendingPathComponent(id).appendingPathExtension("png") }
    private static func isSafeID(_ id: String) -> Bool { UUID(uuidString: id) != nil }
}
