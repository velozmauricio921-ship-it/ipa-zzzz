import Foundation

struct ScopedFolderBookmark: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let bookmarkData: Data

    func replacingBookmarkData(_ data: Data) -> ScopedFolderBookmark {
        ScopedFolderBookmark(id: id, name: name, bookmarkData: data)
    }
}

enum ScopedFileAccessError: Error, LocalizedError {
    case invalidFolder
    case accessDenied
    case folderMissing
    case bookmarkUnavailable
    case pathOutsideFolder
    case symbolicLinkUnsupported
    case cannotReadFolder
    case coordinationFailed
    case pathInspectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            return NSLocalizedString("files.scope.error.invalid_folder", comment: "")
        case .accessDenied:
            return NSLocalizedString("files.scope.error.access_denied", comment: "")
        case .folderMissing:
            return NSLocalizedString("files.scope.error.folder_missing", comment: "")
        case .bookmarkUnavailable:
            return NSLocalizedString("files.scope.error.bookmark_unavailable", comment: "")
        case .pathOutsideFolder:
            return NSLocalizedString("files.scope.error.outside_folder", comment: "")
        case .symbolicLinkUnsupported:
            return NSLocalizedString("files.scope.error.symlink", comment: "")
        case .cannotReadFolder:
            return NSLocalizedString("files.scope.error.cannot_read", comment: "")
        case .coordinationFailed:
            return NSLocalizedString("files.scope.error.coordination_failed", comment: "")
        case .pathInspectionFailed:
            return NSLocalizedString("files.scope.error.cannot_read", comment: "")
        }
    }
}

enum ScopedFileAccessIntent {
    case read
    case write
}

struct BookmarkStore {
    static let shared = BookmarkStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "files.authorizedFolders"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func folders() throws -> [ScopedFolderBookmark] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try PropertyListDecoder().decode([ScopedFolderBookmark].self, from: data)
        } catch {
            throw ScopedFileAccessError.bookmarkUnavailable
        }
    }

    func folder(id: UUID) throws -> ScopedFolderBookmark {
        guard let folder = try folders().first(where: { $0.id == id }) else {
            throw ScopedFileAccessError.bookmarkUnavailable
        }
        return folder
    }

    func save(_ folder: ScopedFolderBookmark) throws {
        var storedFolders = try folders()
        storedFolders.removeAll { $0.id == folder.id }
        storedFolders.append(folder)
        do {
            defaults.set(try PropertyListEncoder().encode(storedFolders), forKey: storageKey)
        } catch {
            throw ScopedFileAccessError.bookmarkUnavailable
        }
    }

    func remove(id: UUID) throws {
        let remaining = try folders().filter { $0.id != id }
        do {
            defaults.set(try PropertyListEncoder().encode(remaining), forKey: storageKey)
        } catch {
            throw ScopedFileAccessError.bookmarkUnavailable
        }
    }
}

struct ScopedFileItem: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64

    var id: String { path }
}

struct ScopedFileAccessProvider {
    typealias BookmarkResolver = (Data) throws -> (url: URL, isStale: Bool)
    typealias AccessCoordinator = (URL, ScopedFileAccessIntent, (URL) throws -> Void) throws -> Void

    private let bookmarkStore: BookmarkStore
    private let fileManager: FileManager
    private let bookmarkResolver: BookmarkResolver
    private let startAccessing: (URL) -> Bool
    private let stopAccessing: (URL) -> Void
    private let coordinate: AccessCoordinator
    private let isSymbolicLink: (URL) throws -> Bool

    init(
        bookmarkStore: BookmarkStore = .shared,
        fileManager: FileManager = .default,
        bookmarkResolver: BookmarkResolver? = nil,
        startAccessing: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        coordinate: AccessCoordinator? = nil,
        isSymbolicLink: ((URL) throws -> Bool)? = nil
    ) {
        self.bookmarkStore = bookmarkStore
        self.fileManager = fileManager
        self.bookmarkResolver = bookmarkResolver ?? Self.resolveBookmark
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
        self.coordinate = coordinate ?? ScopedFileAccessProvider.coordinateURL
        self.isSymbolicLink = isSymbolicLink ?? Self.inspectSymbolicLink
    }

    func addFolder(at url: URL) throws -> ScopedFolderBookmark {
        guard url.isFileURL, startAccessing(url) else {
            throw ScopedFileAccessError.accessDenied
        }
        defer { stopAccessing(url) }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isDirectoryKey])
        } catch {
            throw ScopedFileAccessError.pathInspectionFailed
        }
        guard values.isDirectory == true else {
            throw ScopedFileAccessError.invalidFolder
        }
        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let folder = ScopedFolderBookmark(
            id: UUID(),
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            bookmarkData: data
        )
        try bookmarkStore.save(folder)
        return folder
    }

    func rootPath(for folderID: UUID) throws -> String {
        let folder = try bookmarkStore.folder(id: folderID)
        do {
            return try bookmarkResolver(folder.bookmarkData).url.path
        } catch {
            throw ScopedFileAccessError.bookmarkUnavailable
        }
    }

    func withAccess<T>(
        to folderID: UUID,
        path: String,
        intent: ScopedFileAccessIntent = .read,
        operation: (URL) throws -> T
    ) throws -> T {
        let folder = try bookmarkStore.folder(id: folderID)
        let rootURL: URL
        let isStale: Bool
        do {
            let resolution = try bookmarkResolver(folder.bookmarkData)
            rootURL = resolution.url
            isStale = resolution.isStale
        } catch {
            throw ScopedFileAccessError.bookmarkUnavailable
        }

        guard startAccessing(rootURL) else {
            throw ScopedFileAccessError.accessDenied
        }
        defer { stopAccessing(rootURL) }

        let rootValues: URLResourceValues
        do {
            rootValues = try rootURL.resourceValues(forKeys: [.isDirectoryKey])
        } catch {
            throw ScopedFileAccessError.pathInspectionFailed
        }
        guard fileManager.fileExists(atPath: rootURL.path), rootValues.isDirectory == true else {
            throw ScopedFileAccessError.folderMissing
        }

        if isStale {
            let refreshedData = try rootURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try bookmarkStore.save(folder.replacingBookmarkData(refreshedData))
        }

        let standardizedRoot = rootURL.standardizedFileURL
        let rootPath = standardizedRoot.path
        let candidateURL = URL(fileURLWithPath: path).standardizedFileURL
        guard candidateURL.isFileURL,
              Self.contains(rootPath: rootPath, candidatePath: candidateURL.path) else {
            throw ScopedFileAccessError.pathOutsideFolder
        }
        try inspectPath(candidateURL, below: standardizedRoot)

        // Rechecking inside coordination narrows races, but path-based Foundation calls cannot
        // prevent a hostile concurrent symlink swap; absolute confinement needs descriptor-relative I/O.
        var operationResult: Result<T, Error>?
        do {
            try coordinate(candidateURL, intent) { coordinatedURL in
                operationResult = Result {
                    guard coordinatedURL.isFileURL,
                          Self.contains(
                            rootPath: standardizedRoot.path,
                            candidatePath: coordinatedURL.standardizedFileURL.path
                          ) else {
                        throw ScopedFileAccessError.pathOutsideFolder
                    }
                    try inspectPath(coordinatedURL.standardizedFileURL, below: standardizedRoot)
                    return try operation(coordinatedURL)
                }
            }
        } catch let error as ScopedFileAccessError {
            throw error
        } catch {
            throw ScopedFileAccessError.coordinationFailed
        }
        guard let operationResult else { throw ScopedFileAccessError.coordinationFailed }
        return try operationResult.get()
    }

    func listFiles(in folderID: UUID, at path: String) throws -> [ScopedFileItem] {
        try withAccess(to: folderID, path: path) { directoryURL in
            do {
                return try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                    options: []
                ).compactMap { itemURL in
                    let values = try itemURL.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
                    )
                    guard values.isSymbolicLink != true else { return nil }
                    return ScopedFileItem(
                        name: itemURL.lastPathComponent,
                        path: itemURL.path,
                        isDirectory: values.isDirectory == true,
                        size: Int64(values.fileSize ?? 0)
                    )
                }
            } catch let error as ScopedFileAccessError {
                throw error
            } catch {
                throw ScopedFileAccessError.cannotReadFolder
            }
        }
    }

    static func contains(rootPath: String, candidatePath: String) -> Bool {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let candidate = URL(fileURLWithPath: candidatePath).standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private func inspectPath(_ candidateURL: URL, below rootURL: URL) throws {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = candidateURL.path
        guard Self.contains(rootPath: rootPath, candidatePath: candidatePath) else {
            throw ScopedFileAccessError.pathOutsideFolder
        }

        let relativePath = String(candidatePath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var currentURL = rootURL.standardizedFileURL
        do {
            if try isSymbolicLink(currentURL) {
                throw ScopedFileAccessError.symbolicLinkUnsupported
            }
        } catch let error as ScopedFileAccessError {
            throw error
        } catch {
            throw ScopedFileAccessError.pathInspectionFailed
        }
        for component in relativePath.split(separator: "/") {
            currentURL.appendPathComponent(String(component))
            do {
                if try isSymbolicLink(currentURL) {
                    throw ScopedFileAccessError.symbolicLinkUnsupported
                }
            } catch let error as ScopedFileAccessError {
                throw error
            } catch {
                throw ScopedFileAccessError.pathInspectionFailed
            }
        }
    }

    private static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    private static func inspectSymbolicLink(at url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard let isSymbolicLink = values.isSymbolicLink else {
            throw ScopedFileAccessError.pathInspectionFailed
        }
        return isSymbolicLink
    }

    private static func coordinateURL(
        _ url: URL,
        _ intent: ScopedFileAccessIntent,
        accessor: (URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessorError: Error?
        switch intent {
        case .read:
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
                coordinatedURL in
                do { try accessor(coordinatedURL) } catch { accessorError = error }
            }
        case .write:
            coordinator.coordinate(
                writingItemAt: url,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedURL in
                do { try accessor(coordinatedURL) } catch { accessorError = error }
            }
        }
        if coordinationError != nil { throw ScopedFileAccessError.coordinationFailed }
        if let accessorError { throw accessorError }
    }
}