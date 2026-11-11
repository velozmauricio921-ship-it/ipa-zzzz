import Foundation

enum StorageAccessKind: String, Hashable {
    case appOwned
    case userSelected
    case legacyContainer
}

struct StorageLocation: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitleKey: String
    let rootURL: URL
    let accessKind: StorageAccessKind
    let authorizedFolderID: UUID?
}

protocol StorageProvider {
    func listFiles(at location: URL, within authorizedRoot: URL) -> StorageAccessResult<[FileEntry]>
}

struct FileSystemStorageProvider: StorageProvider {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func appOwnedLocations(fileManager: FileManager = .default) -> [StorageLocation] {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return [
            documents.map {
                StorageLocation(
                    id: "app-documents",
                    title: "browser.documents",
                    subtitleKey: "browser.owned_location_subtitle",
                    rootURL: $0,
                    accessKind: .appOwned,
                    authorizedFolderID: nil
                )
            },
            support.map {
                StorageLocation(
                    id: "app-support",
                    title: "browser.application_support",
                    subtitleKey: "browser.owned_location_subtitle",
                    rootURL: $0,
                    accessKind: .appOwned,
                    authorizedFolderID: nil
                )
            }
        ].compactMap { $0 }
    }

    func listFiles(at location: URL, within authorizedRoot: URL) -> StorageAccessResult<[FileEntry]> {
        let root = authorizedRoot.standardizedFileURL
        let target = location.standardizedFileURL
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            return .failure(.unsafePath)
        }
        guard validatePath(target, from: root) else {
            return .failure(.unsafePath)
        }

        do {
            let children = try fileManager.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            )
            let entries = children.compactMap { child -> FileEntry? in
                guard !child.lastPathComponent.hasPrefix("."),
                      let values = try? child.resourceValues(
                        forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                      ),
                      values.isSymbolicLink != true else {
                    return nil
                }
                let isDirectory = values.isDirectory == true
                guard isDirectory || values.isRegularFile == true else { return nil }
                return FileEntry(
                    name: child.lastPathComponent,
                    path: child.path,
                    isDirectory: isDirectory,
                    size: Int64(values.fileSize ?? 0)
                )
            }
            return .success(entries.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .failure(.accessDenied)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return .failure(.locationUnavailable)
        } catch {
            return .failure(.readFailed(error.localizedDescription))
        }
    }

    private func validatePath(_ target: URL, from root: URL) -> Bool {
        let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else { return false }

        let relativePath = target.path == root.path
            ? ""
            : String(target.path.dropFirst(root.path.count + 1))
        var cursor = root
        let components = relativePath.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            cursor.appendPathComponent(component)
            guard let values = try? cursor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else {
                return false
            }
            if index < components.count - 1, values.isDirectory != true { return false }
        }
        return true
    }
}