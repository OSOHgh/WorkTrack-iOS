import Foundation
import UniformTypeIdentifiers

enum AttachmentStoreError: LocalizedError {
    case invalidRelativePath
    case unreadableSourceFile(URL)

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            return "无效的附件存储路径"
        case .unreadableSourceFile(let url):
            return "无法读取所选文件：\(url.lastPathComponent)"
        }
    }
}

final class AttachmentStore: Sendable {
    static let shared = AttachmentStore()

    private let baseDirectoryURL: URL

    init(baseDirectoryURL: URL? = nil) {
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        }
    }

    func saveImageData(_ data: Data, suggestedName: String = "screenshot.jpg") throws -> AttachmentItem {
        try ensureBaseDirectoryExists()

        let sanitizedName = sanitizeFileName(suggestedName, fallback: "screenshot.jpg")
        let relativePath = "\(UUID().uuidString)_\(sanitizedName)"
        let destinationURL = baseDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)

        try data.write(to: destinationURL, options: .atomic)

        return AttachmentItem(
            fileName: sanitizedName,
            relativePath: relativePath,
            kind: .image,
            fileSize: Int64(data.count),
            createdAt: Date()
        )
    }

    func importFile(from sourceURL: URL) throws -> AttachmentItem {
        try ensureBaseDirectoryExists()

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let originalName = sanitizeFileName(sourceURL.lastPathComponent, fallback: "attachment")
        let relativePath = "\(UUID().uuidString)_\(originalName)"
        let destinationURL = baseDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AttachmentStoreError.unreadableSourceFile(sourceURL)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let kind = inferAttachmentKind(for: sourceURL)

        return AttachmentItem(
            fileName: originalName,
            relativePath: relativePath,
            kind: kind,
            fileSize: fileSize,
            createdAt: Date()
        )
    }

    func fileURL(for item: AttachmentItem) -> URL {
        resolvedURL(forRelativePath: item.relativePath) ?? baseDirectoryURL.appendingPathComponent(item.fileName)
    }

    func deleteAttachment(_ item: AttachmentItem) {
        guard let url = resolvedURL(forRelativePath: item.relativePath) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func readData(for item: AttachmentItem) -> Data? {
        guard let url = resolvedURL(forRelativePath: item.relativePath) else { return nil }
        return try? Data(contentsOf: url)
    }

    func restoreAttachmentFile(relativePath: String, data: Data) throws {
        try ensureBaseDirectoryExists()
        guard let destinationURL = resolvedURL(forRelativePath: relativePath) else {
            throw AttachmentStoreError.invalidRelativePath
        }

        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        try data.write(to: destinationURL, options: .atomic)
    }

    // MARK: - Private Helpers

    private func ensureBaseDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: baseDirectoryURL.path) {
            try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func resolvedURL(forRelativePath relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            return nil
        }

        let baseStandardized = baseDirectoryURL.standardizedFileURL
        let candidate = baseStandardized.appendingPathComponent(trimmed).standardizedFileURL
        let basePrefix = baseStandardized.path.hasSuffix("/") ? baseStandardized.path : baseStandardized.path + "/"
        guard candidate.path.hasPrefix(basePrefix) else {
            return nil
        }
        return candidate
    }

    private func sanitizeFileName(_ name: String, fallback: String) -> String {
        let lastComponent = URL(fileURLWithPath: name).lastPathComponent
        let cleaned = lastComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func inferAttachmentKind(for url: URL) -> AttachmentKind {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext), utType.conforms(to: .image) {
            return .image
        }
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
        return imageExtensions.contains(ext) ? .image : .document
    }
}
