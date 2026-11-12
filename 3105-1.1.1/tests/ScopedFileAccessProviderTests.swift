import Foundation

@main
struct ScopedFileAccessProviderTests {
    static func main() throws {
        let suiteName = "ScopedFileAccessProviderTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated test preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileManager = FileManager.default
        let folderURL = fileManager.temporaryDirectory
            .appendingPathComponent("ScopedFileAccessProviderTests-\(UUID().uuidString)", isDirectory: true)
        let outsideURL = fileManager.temporaryDirectory
            .appendingPathComponent("ScopedFileAccessProviderOutside-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: folderURL)
            try? fileManager.removeItem(at: outsideURL)
        }

        let store = BookmarkStore(defaults: defaults, storageKey: "test.authorizedFolders")
        let provider = makeProvider(
            store: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, _, accessor in try accessor(url) }
        )
        let bookmark = try provider.addFolder(at: folderURL)
        let persisted = BookmarkStore(defaults: defaults, storageKey: "test.authorizedFolders")
        let loadedBookmark = try persisted.folder(id: bookmark.id)
        precondition(loadedBookmark == bookmark, "Bookmark should persist")
        let resolvedPath = try ScopedFileAccessProvider(bookmarkStore: persisted)
            .rootPath(for: bookmark.id)
        precondition(
            URL(fileURLWithPath: resolvedPath).standardizedFileURL == folderURL.standardizedFileURL,
            "Bookmark should resolve to the selected folder"
        )

        try testAccessLifecycle(folderURL: folderURL, store: persisted, bookmark: bookmark)
        try testRevokedAccess(folderURL: folderURL, store: persisted, bookmark: bookmark)
        try testCoordinatedURLs(folderURL: folderURL, store: persisted, bookmark: bookmark)
        try testPathRejections(folderURL: folderURL, outsideURL: outsideURL, store: persisted, bookmark: bookmark)
        try testFileOperations(folderURL: folderURL, store: persisted, bookmark: bookmark)
        try testReplacement(folderURL: folderURL)

        try persisted.remove(id: bookmark.id)
        let remainingBookmarks = try persisted.folders()
        precondition(remainingBookmarks.isEmpty, "Removed bookmark should not be listed")
        print("Scoped file access and replacement tests passed")
    }

    private static func makeProvider(
        store: BookmarkStore,
        startAccessing: @escaping (URL) -> Bool,
        stopAccessing: @escaping (URL) -> Void,
        coordinate: ScopedFileAccessProvider.AccessCoordinator,
        bookmarkResolver: @escaping ScopedFileAccessProvider.BookmarkResolver = {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: $0,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        },
        inspectSymbolicLink: @escaping (URL) throws -> Bool = { url in
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard let isSymbolicLink = values.isSymbolicLink else {
                throw ScopedFileAccessError.pathInspectionFailed
            }
            return isSymbolicLink
        }
    ) -> ScopedFileAccessProvider {
        return ScopedFileAccessProvider(
            bookmarkStore: store,
            bookmarkResolver: bookmarkResolver,
            startAccessing: startAccessing,
            stopAccessing: stopAccessing,
            coordinate: coordinate,
            isSymbolicLink: inspectSymbolicLink
        )
    }

    private static func testAccessLifecycle(
        folderURL: URL,
        store: BookmarkStore,
        bookmark: ScopedFolderBookmark
    ) throws {
        var starts = 0
        var stops = 0
        var coordinationCount = 0
        var coordinatedRead = false
        let provider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 },
            coordinate: { url, intent, accessor in
                coordinationCount += 1
                if case .read = intent { coordinatedRead = true }
                try accessor(url)
            }
        )
        let itemURL = folderURL.appendingPathComponent("lifecycle.txt")
        try Data("readable".utf8).write(to: itemURL)
        let contents = try provider.withAccess(to: bookmark.id, path: itemURL.path) {
            try Data(contentsOf: $0)
        }
        precondition(contents == Data("readable".utf8), "Read should execute inside coordination")
        precondition(starts == 1 && stops == 1, "Security-scoped access should be balanced")
        precondition(coordinationCount == 1, "Read should be coordinated exactly once")
        precondition(coordinatedRead, "Read intent should use read coordination")

        var staleResolutionCount = 0
        let staleProvider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, _, accessor in try accessor(url) },
            bookmarkResolver: { _ in
                staleResolutionCount += 1
                return (folderURL, true)
            }
        )
        _ = try staleProvider.withAccess(to: bookmark.id, path: folderURL.path) { $0.path }
        precondition(staleResolutionCount == 1, "An obsolete bookmark should be refreshed")
        let refreshedBookmark = try store.folder(id: bookmark.id)
        precondition(!refreshedBookmark.bookmarkData.isEmpty, "Refreshed bookmark should persist")

        do {
            try provider.withAccess(to: bookmark.id, path: itemURL.path) { _ -> Void in
                throw TestFailure.injected
            }
            preconditionFailure("Operation errors should escape the access wrapper")
        } catch TestFailure.injected {
            precondition(stops == 2, "Access should stop when an operation throws")
        }
    }

    private static func testRevokedAccess(
        folderURL: URL,
        store: BookmarkStore,
        bookmark: ScopedFolderBookmark
    ) throws {
        var stops = 0
        let provider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in false },
            stopAccessing: { _ in stops += 1 },
            coordinate: { url, _, accessor in try accessor(url) }
        )
        do {
            _ = try provider.withAccess(to: bookmark.id, path: folderURL.path) { $0.path }
            preconditionFailure("Revoked access should be rejected")
        } catch ScopedFileAccessError.accessDenied {
            precondition(stops == 0, "A denied access must not be stopped")
        }
    }

    private static func testCoordinatedURLs(
        folderURL: URL,
        store: BookmarkStore,
        bookmark: ScopedFolderBookmark
    ) throws {
        let requestedURL = folderURL.appendingPathComponent("requested.txt")
        let coordinatedURL = folderURL.appendingPathComponent("provider-location.txt")
        try Data("requested".utf8).write(to: requestedURL)
        try Data("coordinated".utf8).write(to: coordinatedURL)
        var intents: [ScopedFileAccessIntent] = []
        var coordinatedWrite = false
        let provider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, intent, accessor in
                intents.append(intent)
                if case .write = intent { coordinatedWrite = true }
                try accessor(coordinatedURL)
                precondition(url == requestedURL, "Coordinator should receive the requested URL")
            }
        )
        let actualPath = try provider.withAccess(
            to: bookmark.id,
            path: requestedURL.path,
            intent: .write
        ) { $0.path }
        precondition(actualPath == coordinatedURL.path, "Operation should receive the provider URL")
        precondition(intents.count == 1, "Write should use the coordinator")
        precondition(coordinatedWrite, "Write intent should use write coordination")
    }

    private static func testPathRejections(
        folderURL: URL,
        outsideURL: URL,
        store: BookmarkStore,
        bookmark: ScopedFolderBookmark
    ) throws {
        let outsideItem = outsideURL.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outsideItem)
        let provider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, _, accessor in try accessor(url) }
        )
        do {
            _ = try provider.withAccess(to: bookmark.id, path: outsideItem.path) { $0.path }
            preconditionFailure("External paths should be rejected")
        } catch ScopedFileAccessError.pathOutsideFolder {}

        let linkURL = folderURL.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideItem)
        do {
            _ = try provider.withAccess(to: bookmark.id, path: linkURL.path) { $0.path }
            preconditionFailure("Symbolic links should be rejected")
        } catch ScopedFileAccessError.symbolicLinkUnsupported {}

        let inspectionURL = folderURL.appendingPathComponent("inspection-error.txt")
        try Data().write(to: inspectionURL)
        let inspectionFailureProvider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, _, accessor in try accessor(url) },
            isSymbolicLink: { url in
                if url == inspectionURL {
                    throw TestFailure.injected
                }
                return false
            }
        )
        do {
            _ = try inspectionFailureProvider.withAccess(
                to: bookmark.id,
                path: inspectionURL.path
            ) { $0.path }
            preconditionFailure("Inspection errors should reject access")
        } catch ScopedFileAccessError.pathInspectionFailed {}
    }

    private static func testFileOperations(
        folderURL: URL,
        store: BookmarkStore,
        bookmark: ScopedFolderBookmark
    ) throws {
        let provider = ScopedFileAccessProvider(
            bookmarkStore: store,
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            coordinate: { url, _, accessor in try accessor(url) }
        )
        try provider.withAccess(to: bookmark.id, path: folderURL.path, intent: .write) { directory in
            let created = directory.appendingPathComponent("created.txt")
            precondition(FileManager.default.createFile(atPath: created.path, contents: Data("one".utf8)))
            let copied = directory.appendingPathComponent("copied.txt")
            try FileManager.default.copyItem(at: created, to: copied)
            let copiedContents = try Data(contentsOf: copied)
            precondition(copiedContents == Data("one".utf8), "Copy should preserve file contents")
            let moved = directory.appendingPathComponent("moved.txt")
            try FileManager.default.moveItem(at: copied, to: moved)
            let movedContents = try Data(contentsOf: moved)
            precondition(movedContents == Data("one".utf8), "Move should preserve file contents")
            try FileManager.default.removeItem(at: moved)
            precondition(FileManager.default.fileExists(atPath: created.path), "Create should persist")
            precondition(!FileManager.default.fileExists(atPath: copied.path), "Copy source should remain distinct")
            precondition(!FileManager.default.fileExists(atPath: moved.path), "Delete should remove the moved item")
        }
    }

    private static func testReplacement(folderURL: URL) throws {
        let targetURL = folderURL.appendingPathComponent("replace-target.txt")
        let sourceURL = folderURL.appendingPathComponent("replace-source.txt")
        try Data("old contents".utf8).write(to: targetURL)
        try Data("new contents".utf8).write(to: sourceURL)
        let result = try FileReplacementService.replace(target: targetURL, with: sourceURL)
        precondition(result.byteCount == Int64("new contents".utf8.count), "Result should report copied bytes")
        let replacedContents = try Data(contentsOf: targetURL)
        precondition(replacedContents == Data("new contents".utf8), "Replacement should publish verified data")

        try Data("old again".utf8).write(to: targetURL)
        do {
            _ = try FileReplacementService.replace(
                target: targetURL,
                with: folderURL.appendingPathComponent("missing-source.txt")
            )
            preconditionFailure("A missing source should fail replacement")
        } catch FileReplacementError.sourceMissing {
            let preservedContents = try Data(contentsOf: targetURL)
            precondition(preservedContents == Data("old again".utf8), "Missing source should preserve old data")
        }

        let interruptedBackup = folderURL.appendingPathComponent(
            ".3105-replacement-backup-\(targetURL.lastPathComponent)-interrupted"
        )
        let interruptedStage = folderURL.appendingPathComponent(
            ".3105-replacement-stage-\(targetURL.lastPathComponent)-interrupted"
        )
        try Data("before interruption".utf8).write(to: interruptedBackup)
        try Data("partial stage".utf8).write(to: interruptedStage)
        try Data("published before interruption".utf8).write(to: targetURL)
        do {
            _ = try FileReplacementService.replace(
                target: targetURL,
                with: folderURL.appendingPathComponent("missing-source.txt")
            )
            preconditionFailure("A missing source should fail after interrupted recovery")
        } catch FileReplacementError.sourceMissing {
            let recoveredContents = try Data(contentsOf: targetURL)
            precondition(
                recoveredContents == Data("before interruption".utf8),
                "Interrupted replacement should restore the saved original"
            )
            precondition(!FileManager.default.fileExists(atPath: interruptedStage.path), "Orphan staging should be removed")
        }

        do {
            _ = try FileReplacementService.replace(
                target: targetURL,
                with: sourceURL,
                verify: { _, _ in false }
            )
            preconditionFailure("A failed verification should fail replacement")
        } catch FileReplacementError.replacementFailed {
            let restoredContents = try Data(contentsOf: targetURL)
            precondition(restoredContents == Data("old again".utf8), "Failed replacement should restore old data")
        }

        do {
            _ = try FileReplacementService.replace(
                target: targetURL,
                with: sourceURL,
                verify: { _, _ in throw TestFailure.injected }
            )
            preconditionFailure("An interrupted verification should fail replacement")
        } catch FileReplacementError.replacementFailed {
            let restoredContents = try Data(contentsOf: targetURL)
            precondition(restoredContents == Data("old again".utf8), "Interrupted replacement should roll back")
        }
    }

    private enum TestFailure: Error {
        case injected
    }
}