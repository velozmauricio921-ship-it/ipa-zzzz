import Foundation

struct ApplicationInformation: Equatable, Identifiable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

enum ContainerDiscoveryService {
    static func currentApplication() -> ApplicationInformation {
        let bundle = Bundle.main
        let identifier = bundle.bundleIdentifier ?? ""
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? identifier
        return ApplicationInformation(bundleIdentifier: identifier, displayName: name)
    }

    static func installedApplications() -> StorageAccessResult<[ApplicationInformation]> {
        .failure(.publicAppCatalogUnavailable)
    }

    static func availableLocations(
        authorizedFolders: [AuthorizedFolder],
        fileManager: FileManager = .default
    ) -> [StorageLocation] {
        let owned = FileSystemStorageProvider.appOwnedLocations(fileManager: fileManager)
        let selected = authorizedFolders.map { folder in
            StorageLocation(
                id: "user-folder-\(folder.id.uuidString)",
                title: folder.displayName,
                subtitleKey: "browser.user_selected_subtitle",
                rootURL: folder.url,
                accessKind: .userSelected,
                authorizedFolderID: folder.id
            )
        }
        return owned + selected
    }
}