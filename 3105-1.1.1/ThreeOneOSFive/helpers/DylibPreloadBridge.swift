import Foundation
import Darwin

enum DylibPreloadError: Error {
    case notFound
    case loadFailed(String)
}

final class DylibPreloadBridge {
    static let shared = DylibPreloadBridge()

    private init() {}

    func installPreloadedPackages(into preloadedRoot: URL) throws {
        guard let dylibPath = Bundle.main.path(forResource: "preload", ofType: "dylib") else {
            // No dylib bundled — nothing to do
            return
        }

        guard let handle = dlopen(dylibPath, RTLD_NOW) else {
            let err = String(cString: dlerror())
            throw DylibPreloadError.loadFailed(err)
        }
        defer { dlclose(handle) }

        typealias CountFn = @convention(c) () -> Int32
        typealias NameFn = @convention(c) (Int32) -> UnsafePointer<CChar>?
        typealias GetFn = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int32>?) -> Int32
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

        guard let symCount = dlsym(handle, "preload_count") else { return }
        guard let symName = dlsym(handle, "preload_name") else { return }
        guard let symGet = dlsym(handle, "preload_get") else { return }
        guard let symFree = dlsym(handle, "preload_free") else { return }

        let count = unsafeBitCast(symCount, to: CountFn.self)()
        let nameFn = unsafeBitCast(symName, to: NameFn.self)
        let getFn = unsafeBitCast(symGet, to: GetFn.self)
        let freeFn = unsafeBitCast(symFree, to: FreeFn.self)

        let fm = FileManager.default

        for i in 0..<Int(count) {
            guard let cname = nameFn(Int32(i)) else { continue }
            let filename = String(cString: cname)
            var outPtr: UnsafeMutablePointer<UInt8>? = nil
            var outLen: Int32 = 0
            let ok = getFn(Int32(i), &outPtr, &outLen)
            if ok == 0, let ptr = outPtr, outLen > 0 {
                let data = Data(bytes: ptr, count: Int(outLen))
                // create destination path preserving any subfolders in the name
                let destination = preloadedRoot.appendingPathComponent(filename)
                try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try data.write(to: destination, options: [.atomic, .completeFileProtection])
                } catch {
                    // ignore individual file write errors but continue
                }
            }
            freeFn(outPtr)
        }
    }
}
