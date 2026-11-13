import Foundation

protocol FileDiscoveryEngine {
    var providerID: FileDiscoveryProviderID { get }

    func canHandle(_ source: FileDiscoverySource) -> Bool
    func availability(for source: FileDiscoverySource) -> FileDiscoveryAvailability
    func discover(from source: FileDiscoverySource) -> DiscoveryResult
}

struct AppSandboxFileDiscoveryEngine: FileDiscoveryEngine {
    let providerID: FileDiscoveryProviderID = .appSandbox

    func canHandle(_ source: FileDiscoverySource) -> Bool {
        if case .appSandbox = source { return true }
        return false
    }

    func availability(for source: FileDiscoverySource) -> FileDiscoveryAvailability {
        guard let directoryURL = directoryURL(for: source),
              isWithinAppSandbox(directoryURL),
              isDirectory(directoryURL) else {
            return .unavailable
        }
        return .available
    }

    func discover(from source: FileDiscoverySource) -> DiscoveryResult {
        guard let directoryURL = directoryURL(for: source),
              isWithinAppSandbox(directoryURL),
              isDirectory(directoryURL) else {
            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .unavailable,
                status: .sourceUnavailable,
                permissionState: .notRequired,
                error: .sourceUnavailable
            )
        }

        do {
            let items = try enumerateChildren(of: directoryURL)
            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .available,
                status: items.isEmpty ? .empty : .available,
                permissionState: .notRequired,
                items: items
            )
        } catch {
            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .available,
                status: .enumerationFailed,
                permissionState: .notRequired,
                error: .enumerationFailed(error.localizedDescription)
            )
        }
    }

    private func directoryURL(for source: FileDiscoverySource) -> URL? {
        guard case .appSandbox(let location) = source else { return nil }
        let fileManager = FileManager.default
        let searchPath: FileManager.SearchPathDirectory
        switch location {
        case .documents:
            searchPath = .documentDirectory
        case .library:
            searchPath = .libraryDirectory
        case .caches:
            searchPath = .cachesDirectory
        }
        return fileManager.urls(for: searchPath, in: .userDomainMask).first?.standardizedFileURL
    }

    private func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
            return false
        }
        return values.isDirectory == true
    }

    private func isWithinAppSandbox(_ url: URL) -> Bool {
        let sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == sandboxRoot || path.hasPrefix(sandboxRoot + "/")
    }

    fileprivate func enumerateChildren(of directoryURL: URL) throws -> [DiscoveredFile] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { return nil }
            guard values.isDirectory == true || values.isRegularFile == true else { return nil }
            return DiscoveredFile(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values.isDirectory == true,
                sizeBytes: values.fileSize.map(Int64.init)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct UserSelectedFileDiscoveryEngine: FileDiscoveryEngine {
    let providerID: FileDiscoveryProviderID = .userSelectedDocuments

    func canHandle(_ source: FileDiscoverySource) -> Bool {
        if case .userSelected = source { return true }
        return false
    }

    func availability(for source: FileDiscoverySource) -> FileDiscoveryAvailability {
        guard case .userSelected(let url) = source, url.isFileURL else {
            return .unavailable
        }
        return .available
    }

    func discover(from source: FileDiscoverySource) -> DiscoveryResult {
        guard case .userSelected(let rawURL) = source, rawURL.isFileURL else {
            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .unavailable,
                status: .sourceUnavailable,
                permissionState: .notGranted,
                error: .invalidSource
            )
        }

        let url = rawURL.standardizedFileURL
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        let isInAppSandbox = isWithinAppSandbox(url)
        guard didStartAccessing || isInAppSandbox else {
            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .available,
                status: .permissionNotGranted,
                permissionState: .notGranted,
                error: .permissionDenied
            )
        }

        let lease = didStartAccessing ? SecurityScopedAccessLease(url: url) : nil
        let permissionState: DiscoveryPermissionState = didStartAccessing ? .granted : .notRequired

        do {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            guard values.isSymbolicLink != true else {
                lease?.release()
                return failure(
                    source: source,
                    status: .enumerationFailed,
                    permissionState: permissionState,
                    error: .unsupportedItem
                )
            }

            let items: [DiscoveredFile]
            if values.isDirectory == true {
                items = try AppSandboxFileDiscoveryEngine().enumerateChildren(of: url)
            } else if values.isRegularFile == true {
                items = [DiscoveredFile(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: false,
                    sizeBytes: values.fileSize.map(Int64.init)
                )]
            } else {
                lease?.release()
                return failure(
                    source: source,
                    status: .enumerationFailed,
                    permissionState: permissionState,
                    error: .unsupportedItem
                )
            }

            if items.isEmpty {
                lease?.release()
                return DiscoveryResult(
                    selectedProvider: providerID,
                    source: source,
                    availability: .available,
                    status: .empty,
                    permissionState: permissionState
                )
            }

            return DiscoveryResult(
                selectedProvider: providerID,
                source: source,
                availability: .available,
                status: .available,
                permissionState: permissionState,
                items: items,
                accessLease: lease
            )
        } catch {
            lease?.release()
            return failure(
                source: source,
                status: .enumerationFailed,
                permissionState: permissionState,
                error: .enumerationFailed(error.localizedDescription)
            )
        }
    }

    private func isWithinAppSandbox(_ url: URL) -> Bool {
        let sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == sandboxRoot || path.hasPrefix(sandboxRoot + "/")
    }

    private func failure(
        source: FileDiscoverySource,
        status: DiscoveryStatus,
        permissionState: DiscoveryPermissionState,
        error: DiscoveryError
    ) -> DiscoveryResult {
        DiscoveryResult(
            selectedProvider: providerID,
            source: source,
            availability: .available,
            status: status,
            permissionState: permissionState,
            error: error
        )
    }
}