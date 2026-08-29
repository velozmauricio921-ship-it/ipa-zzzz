import Foundation

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var project: PatchProject?
    var contentKey: Data?
    var packageURL: URL
    var categoryName: String

    var id: UUID { summary.packageID }
    var isLocked: Bool { project == nil }
    var workspaceURL: URL? {
        PatchWorkspaceService.workspaceURL(projectID: id)
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

enum PatchProjectLibrary {
    private static let installNamespaceKey = "PatchProjectLibrary.installNamespace"

    private static func appNamespace() -> String {
        if let stored = UserDefaults.standard.string(forKey: installNamespaceKey), !stored.isEmpty {
            return stored
        }

        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: installNamespaceKey)
        return generated
    }

    static func legacyPackageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("PatchProjects", isDirectory: true)
    }

    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent(appNamespace(), isDirectory: true)
            .appendingPathComponent("PatchProjects", isDirectory: true)

        let legacyRoot = try legacyPackageRootURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: legacyRoot.path),
           legacyRoot.path != root.path {
            do {
                try? fileManager.removeItem(at: legacyRoot)
            }
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func preloadedRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Preloaded", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        ensurePreloadedPackagesInstalled(fileManager: fileManager)

        guard let root = try? packageRootURL(fileManager: fileManager) else { return [] }
        let preloadedRoot = (try? preloadedRootURL(fileManager: fileManager)) ?? root

        let rootURLs = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        let preloadedURLs = recursivePackageURLs(in: preloadedRoot, fileManager: fileManager)

        let urls = rootURLs + preloadedURLs

        var byID: [UUID: PatchLibraryItem] = [:]
        for url in urls where url.pathExtension.lowercased() == "3105" {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let categoryName = inferredCategoryName(for: url, libraryRoot: root, preloadedRoot: preloadedRoot)
                let decoded: DecodedPatchPackage?
                if let contentKey = try? PatchKeyStore.load(for: summary) {
                    decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
                } else if summary.isPasswordProtected {
                    // If password-protected and no key available, keep locked
                    decoded = nil
                } else {
                    // For public packages, still attempt decode without contentKey
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                let item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url,
                    categoryName: categoryName
                )
                if summary.schemaVersion >= 2, let project = decoded?.project {
                    do {
                        _ = try PatchWorkspaceService.ensureWorkspace(for: project)
                    } catch {
                        log("patch: workspace unavailable for \(project.id.uuidString)")
                    }
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent)")
            }
        }
        return byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
    }

    private static func recursivePackageURLs(
        in root: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return enumerator?.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension.lowercased() == "3105",
                  !url.path.contains("/.3105-") else {
                return nil
            }
            return url
        } ?? []
    }

    private static func inferredCategoryName(
        for url: URL,
        libraryRoot: URL,
        preloadedRoot: URL
    ) -> String {
        let path = url.deletingLastPathComponent().path

        if path.hasPrefix(preloadedRoot.path) {
            let relative = path.replacingOccurrences(of: preloadedRoot.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relative.isEmpty {
                return relative.split(separator: "/").last.map(String.init) ?? "General"
            }
        }

        if path.hasPrefix(libraryRoot.path) {
            let relative = path.replacingOccurrences(of: libraryRoot.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relative.isEmpty {
                return relative.split(separator: "/").last.map(String.init) ?? "General"
            }
        }

        return "General"
    }

    static func readPackage(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("3105")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("3105")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        fileManager: FileManager = .default
    ) throws {
        let previousData = try existingURL.map { try readPackage(at: $0) }
        var savedURL: URL?
        do {
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2 {
                _ = try PatchWorkspaceService.replaceWorkspace(
                    with: decoded.project,
                    fileManager: fileManager
                )
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: [.atomic, .completeFileProtection]
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
    }

    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              let baseProject = item.project,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        let workspace = try PatchWorkspaceService.ensureWorkspace(
            for: baseProject,
            fileManager: fileManager
        )
        let project = try PatchWorkspaceService.snapshot(
            baseProject: baseProject,
            workspaceURL: workspace,
            fileManager: fileManager
        )
        let original = try readPackage(at: item.packageURL)
        let updated = try PatchPackageCodec.update(
            original,
            project: project,
            contentKey: contentKey,
            schemaVersion: PatchPackageCodec.latestSchemaVersion
        )
        _ = try save(
            data: updated,
            projectName: project.name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return project
    }

    static func ensurePreloadedPackagesInstalled(fileManager: FileManager = .default) {
        guard let libraryRoot = try? packageRootURL(fileManager: fileManager) else { return }

        let preloadedRoot: URL
        do {
            preloadedRoot = try preloadedRootURL(fileManager: fileManager)
        } catch {
            log("preload: failed to prepare preloaded cache — \(error.localizedDescription)")
            return
        }

        do {
            if fileManager.fileExists(atPath: preloadedRoot.path) {
                try fileManager.removeItem(at: preloadedRoot)
            }
            try fileManager.createDirectory(at: preloadedRoot, withIntermediateDirectories: true)
        } catch {
            log("preload: failed to clear stale preloaded cache — \(error.localizedDescription)")
        }

        var bundleURLs: [URL] = []

        if let resourceRoot = Bundle.main.resourceURL {
            let directPreloaded = resourceRoot.appendingPathComponent("Preloaded", isDirectory: true)
            if fileManager.fileExists(atPath: directPreloaded.path),
               let urls = try? fileManager.contentsOfDirectory(
                at: directPreloaded,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
               ) {
                bundleURLs += urls.filter { $0.pathExtension.lowercased() == "3105" }
            }

            if bundleURLs.isEmpty,
               let recursive = try? fileManager.recursiveFiles(in: resourceRoot, matchingExtension: "3105") {
                bundleURLs += recursive.filter { $0.path.contains("/Preloaded/") || $0.deletingLastPathComponent().lastPathComponent == "Preloaded" }
            }

            if let nested = try? fileManager.recursiveFiles(in: directPreloaded, matchingExtension: "3105") {
                bundleURLs += nested.filter { $0.path.hasPrefix(directPreloaded.path) }
            }
        }

        if bundleURLs.isEmpty,
           let paths = Bundle.main.paths(forResourcesOfType: "3105", inDirectory: "Preloaded") as [String]? {
            bundleURLs += paths.map { URL(fileURLWithPath: $0) }
        }

        guard !bundleURLs.isEmpty else {
            log("preload: no bundled .3105 files found in app resources")
            return
        }

        let uniqueBundleURLs = Dictionary(uniqueKeysWithValues: bundleURLs.map { ($0.lastPathComponent, $0) }).values
        let bundleNames = Set(uniqueBundleURLs.map { $0.lastPathComponent })

        for sourceURL in uniqueBundleURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let sourceRoot = Bundle.main.resourceURL?.appendingPathComponent("Preloaded", isDirectory: true)
            let relativePath = sourceURL.path.hasPrefix(sourceRoot?.path ?? "")
                ? sourceURL.path.replacingOccurrences(of: sourceRoot?.path ?? "", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : sourceURL.lastPathComponent
            let destinationURL = preloadedRoot.appendingPathComponent(relativePath)
            do {
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                log("preload: copied bundled package \(sourceURL.lastPathComponent) to cache")
            } catch {
                log("preload: failed to copy \(sourceURL.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        do {
            let existing = try fileManager.contentsOfDirectory(
                at: libraryRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            let stalePreloadedFiles = existing.filter {
                $0.pathExtension.lowercased() == "3105" &&
                bundleNames.contains($0.lastPathComponent)
            }
            for stale in stalePreloadedFiles {
                try? fileManager.removeItem(at: stale)
            }
        } catch {
            log("preload: failed to prune stale library copies")
        }
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch" : String(result)
    }
}
