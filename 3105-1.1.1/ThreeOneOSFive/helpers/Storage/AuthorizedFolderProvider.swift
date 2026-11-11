import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AuthorizedFolder: Identifiable, Hashable {
    let id: UUID
    let url: URL

    var displayName: String { url.lastPathComponent }
}

@MainActor
final class AuthorizedFolderProvider: ObservableObject {
    @Published private(set) var folders: [AuthorizedFolder] = []

    func add(_ url: URL) -> StorageAccessResult<AuthorizedFolder> {
        guard url.isFileURL, url.startAccessingSecurityScopedResource() else {
            return .failure(.accessDenied)
        }

        let standardizedURL = url.standardizedFileURL
        if let existing = folders.first(where: { $0.url.standardizedFileURL == standardizedURL }) {
            url.stopAccessingSecurityScopedResource()
            return .success(existing)
        }

        let values = try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            url.stopAccessingSecurityScopedResource()
            return .failure(.locationUnavailable)
        }

        let folder = AuthorizedFolder(id: UUID(), url: url)
        folders.append(folder)
        return .success(folder)
    }

    func remove(_ folder: AuthorizedFolder) {
        guard let index = folders.firstIndex(of: folder) else { return }
        folders.remove(at: index).url.stopAccessingSecurityScopedResource()
    }

    func authorizes(folderID: UUID?, path: String) -> Bool {
        guard let folderID,
              let folder = folders.first(where: { $0.id == folderID }) else {
            return false
        }
        let rootPath = folder.url.standardizedFileURL.path
        let targetPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    deinit {
        for folder in folders {
            folder.url.stopAccessingSecurityScopedResource()
        }
    }
}

struct AuthorizedFolderPicker: UIViewControllerRepresentable {
    let onSelection: (Result<URL, StorageAccessIssue>) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelection: (Result<URL, StorageAccessIssue>) -> Void
        private let onCancel: () -> Void

        init(
            onSelection: @escaping (Result<URL, StorageAccessIssue>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onSelection = onSelection
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onSelection(.failure(.locationUnavailable))
                return
            }
            onSelection(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}