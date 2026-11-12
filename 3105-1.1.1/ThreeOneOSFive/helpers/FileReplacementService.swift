import Foundation
import Darwin
import UniformTypeIdentifiers

enum ReplacementPickerPolicy {
    static let allowedContentTypes: [UTType] = [.data]
    static let copiesSelectedDocument = true
    static let presentationDelay: TimeInterval = 0.35

    static func accepts(_ type: UTType) -> Bool {
        type.conforms(to: .data) && !type.conforms(to: .folder)
    }
}

struct FileReplacementSelection: Equatable {
    let targetURL: URL
    let targetName: String
    let sourceURL: URL
}

struct FileReplacementRequest: Identifiable, Equatable {
    let id: UUID
    let targetURL: URL
    let targetName: String

    init(id: UUID = UUID(), targetURL: URL, targetName: String) {
        self.id = id
        self.targetURL = targetURL
        self.targetName = targetName
    }

    func selection(from urls: [URL]) throws -> FileReplacementSelection {
        guard let sourceURL = urls.first else {
            throw FileReplacementError.sourceMissing
        }
        return FileReplacementSelection(
            targetURL: targetURL,
            targetName: targetName,
            sourceURL: sourceURL
        )
    }
}

enum FileReplacementError: Error, Equatable, LocalizedError {
    case targetMissing
    case sourceMissing
    case targetIsDirectory
    case sourceIsDirectory
    case sameFile
    case symbolicLinkUnsupported
    case sourceTooLarge
    case replacementFailed
    case recoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing: return "The target file no longer exists."
        case .sourceMissing: return "The selected replacement file is unavailable."
        case .targetIsDirectory: return "Folders cannot be replaced with this action."
        case .sourceIsDirectory: return "Select a file, not a folder."
        case .sameFile: return "A file cannot replace itself."
        case .symbolicLinkUnsupported: return "Symbolic links are not supported."
        case .sourceTooLarge: return "The selected file is too large."
        case .replacementFailed: return "The file could not be replaced safely."
        case .recoveryRequired(let backupPath):
            return "The replacement failed. The previous file is preserved at \(backupPath)."
        }
    }
}

struct FileReplacementResult: Equatable {
    let targetURL: URL
    let byteCount: Int64
}

enum FileReplacementService {
    private static let chunkSize = 1_024 * 1_024

    static func replace(
        target targetURL: URL,
        with sourceURL: URL,
        fileManager: FileManager = .default,
        verify: ((URL, URL) throws -> Bool)? = nil
    ) throws -> FileReplacementResult {
        try recoverInterruptedReplacement(for: targetURL, fileManager: fileManager)
        let targetValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        let sourceValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        guard targetValues.isSymbolicLink != true,
              sourceValues.isSymbolicLink != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard targetValues.isDirectory != true else {
            throw FileReplacementError.targetIsDirectory
        }
        guard sourceValues.isDirectory != true else {
            throw FileReplacementError.sourceIsDirectory
        }
        guard targetURL.standardizedFileURL.resolvingSymlinksInPath()
                != sourceURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileReplacementError.sameFile
        }
        let targetAttributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        let parentURL = targetURL.deletingLastPathComponent()
        let transactionID = UUID().uuidString
        let targetName = targetURL.lastPathComponent
        let stagingURL = parentURL.appendingPathComponent(
            ".3105-replacement-stage-\(targetName)-\(transactionID)"
        )
        let backupStagingURL = parentURL.appendingPathComponent(
            ".3105-replacement-backup-stage-\(targetName)-\(transactionID)"
        )
        let backupURL = parentURL.appendingPathComponent(
            ".3105-replacement-backup-\(targetName)-\(transactionID)"
        )
        let retainedTargetAttributes = retainedAttributes(from: targetAttributes)
        var keepBackup = false
        defer {
            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: backupStagingURL)
            if !keepBackup { try? fileManager.removeItem(at: backupURL) }
        }
        guard createCopy(
            of: targetURL,
            at: backupStagingURL,
            attributes: retainedTargetAttributes,
            fileManager: fileManager
        ) else {
            throw FileReplacementError.replacementFailed
        }
        guard rename(backupStagingURL.path, backupURL.path) == 0 else {
            throw FileReplacementError.replacementFailed
        }

        let copied: Int64
        do {
            copied = try copyContents(
                from: sourceURL,
                to: stagingURL,
                attributes: retainedTargetAttributes,
                fileManager: fileManager
            )
        } catch let error as FileReplacementError {
            throw error
        } catch {
            throw FileReplacementError.replacementFailed
        }

        var installed = false
        do {
            let currentValues = try values(
                for: targetURL,
                missingError: .targetMissing,
                fileManager: fileManager
            )
            guard currentValues.isSymbolicLink != true else {
                throw FileReplacementError.symbolicLinkUnsupported
            }
            guard currentValues.isDirectory != true else {
                throw FileReplacementError.targetIsDirectory
            }
            guard rename(stagingURL.path, targetURL.path) == 0 else {
                throw FileReplacementError.replacementFailed
            }
            installed = true
            let verifyFiles = verify ?? Self.filesMatch
            guard try verifyFiles(sourceURL, targetURL) else {
                throw FileReplacementError.replacementFailed
            }
        } catch {
            guard installed else { throw error }
            guard rename(backupURL.path, targetURL.path) == 0 else {
                keepBackup = true
                throw FileReplacementError.recoveryRequired(backupURL.path)
            }
            if let error = error as? FileReplacementError { throw error }
            throw FileReplacementError.replacementFailed
        }
        return FileReplacementResult(targetURL: targetURL, byteCount: copied)
    }

    private static func createCopy(
        of sourceURL: URL,
        at destinationURL: URL,
        attributes: [FileAttributeKey: Any],
        fileManager: FileManager
    ) -> Bool {
        do {
            _ = try copyContents(
                from: sourceURL,
                to: destinationURL,
                attributes: attributes,
                fileManager: fileManager
            )
            return true
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return false
        }
    }

    private static func copyContents(
        from sourceURL: URL,
        to destinationURL: URL,
        attributes: [FileAttributeKey: Any],
        fileManager: FileManager
    ) throws -> Int64 {
        if !fileManager.fileExists(atPath: destinationURL.path),
           !fileManager.createFile(
                atPath: destinationURL.path,
                contents: nil,
                attributes: nil
           ) {
            throw FileReplacementError.replacementFailed
        }
        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? source.close()
            try? destination.close()
        }

        var copied: Int64 = 0
        while let data = try source.read(upToCount: chunkSize), !data.isEmpty {
            let (nextCount, overflow) = copied.addingReportingOverflow(Int64(data.count))
            guard !overflow else { throw FileReplacementError.sourceTooLarge }
            copied = nextCount
            try destination.write(contentsOf: data)
        }
        try destination.synchronize()
        try fileManager.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        return copied
    }

    private static func filesMatch(_ sourceURL: URL, _ destinationURL: URL) throws -> Bool {
        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forReadingFrom: destinationURL)
        defer {
            try? source.close()
            try? destination.close()
        }
        while true {
            let sourceData = try source.read(upToCount: chunkSize)
            let destinationData = try destination.read(upToCount: chunkSize)
            guard sourceData == destinationData else { return false }
            guard let sourceData, !sourceData.isEmpty else { return true }
        }
    }

    private static func recoverInterruptedReplacement(
        for targetURL: URL,
        fileManager: FileManager
    ) throws {
        let parentURL = targetURL.deletingLastPathComponent()
        let targetName = targetURL.lastPathComponent
        let backupPrefix = ".3105-replacement-backup-\(targetName)-"
        let stagePrefix = ".3105-replacement-stage-\(targetName)-"
        let backupStagePrefix = ".3105-replacement-backup-stage-\(targetName)-"
        let items: [URL]
        do {
            items = try fileManager.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw FileReplacementError.replacementFailed
        }
        let backups = items.filter { $0.lastPathComponent.hasPrefix(backupPrefix) }
        guard backups.count <= 1 else {
            throw FileReplacementError.recoveryRequired(backups[0].path)
        }
        if let backup = backups.first, rename(backup.path, targetURL.path) != 0 {
            throw FileReplacementError.recoveryRequired(backup.path)
        }
        for item in items where item.lastPathComponent.hasPrefix(stagePrefix)
            || item.lastPathComponent.hasPrefix(backupStagePrefix)
            || (item.lastPathComponent.hasPrefix(backupPrefix) && item != backups.first) {
            do {
                try fileManager.removeItem(at: item)
            } catch {
                throw FileReplacementError.replacementFailed
            }
        }
    }

    private static func values(
        for url: URL,
        missingError: FileReplacementError,
        fileManager: FileManager
    ) throws -> URLResourceValues {
        guard fileManager.fileExists(atPath: url.path) else { throw missingError }
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw missingError
        }
    }

    private static func retainedAttributes(
        from attributes: [FileAttributeKey: Any]
    ) -> [FileAttributeKey: Any] {
        var result: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] {
            result[.posixPermissions] = permissions
        }
        if let protection = attributes[.protectionKey] {
            result[.protectionKey] = protection
        }
        return result
    }
}
