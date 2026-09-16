import Foundation

enum PreloadDecryptor {
    // The same key as used in CI script (hex string). Keep length 32 bytes (AES-256).
    private static let hexKey = "d4b2f3a9c6e7f8a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a"

    static func decryptPrefixedAES(fileURL: URL) throws -> Data {
        let raw = try Data(contentsOf: fileURL)
        // First 16 bytes are IV
        guard raw.count > 16 else { throw NSError(domain: "preload", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid file"]) }
        let iv = raw.subdata(in: 0..<16)
        let cipher = raw.subdata(in: 16..<raw.count)
        guard let keyData = Data(hexString: hexKey) else { throw NSError(domain: "preload", code: 2, userInfo: [NSLocalizedDescriptionKey: "invalid key"]) }
        return try aesCBCDecrypt(data: cipher, key: keyData, iv: iv)
    }

    private static func aesCBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        let status = out.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBytes.baseAddress, out.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw NSError(domain: "preload", code: Int(status), userInfo: nil) }
        out.removeSubrange(numBytesDecrypted..<out.count)
        return out
    }
}

private extension Data {
    init?(hexString: String) {
        var data = Data()
        var s = hexString
        while s.count >= 2 {
            let prefix = String(s.prefix(2))
            s = String(s.dropFirst(2))
            if let b = UInt8(prefix, radix: 16) {
                data.append(b)
            } else {
                return nil
            }
        }
        self = data
    }
}
