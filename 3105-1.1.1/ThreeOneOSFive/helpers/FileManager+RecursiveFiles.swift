import Foundation

extension FileManager {
    /// Recursively enumerates files under `directory`, returning URLs whose path extension matches `ext` (case-insensitive).
    func recursiveFiles(in directory: URL, matchingExtension ext: String) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var results: [URL] = []

        let enumerator = self.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                return true
            }
        )

        guard let enumerator else {
            return results
        }

        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: Set(keys))
            if resourceValues.isRegularFile == true,
               url.pathExtension.lowercased() == ext.lowercased() {
                results.append(url)
            }
        }

        return results
    }
}
