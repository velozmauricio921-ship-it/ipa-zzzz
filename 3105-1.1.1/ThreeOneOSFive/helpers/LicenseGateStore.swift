import Foundation
import Security

private struct LicenseConfirmation: Codable {
    let license: String
    let runtimeSignature: String
    let hardwareID: String
    let validatedAt: TimeInterval
}

struct LicenseGateStore {
    private static let validatedKey = "keyauth.license.validated"
    private static let licenseKey = "keyauth.license.key"
    private static let statusKey = "keyauth.license.status"
    private static let lastMessageKey = "keyauth.license.lastMessage"
    private static let expiryKey = "keyauth.license.expiry"
    private static let lastResponseKey = "keyauth.license.lastResponse"
    private static let confirmationService = "com.3105.keyauth.confirmation"
    private static let confirmationAccount = "validated-license"

    static func isUnlocked() -> Bool {
        UserDefaults.standard.bool(forKey: validatedKey)
    }

    static func savedLicense() -> String {
        // Prefer the Keychain-stored license. If absent, migrate any existing UserDefaults value.
        if let data = loadLicenseFromKeychain(), let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        // Migration path: if the app previously stored the license in UserDefaults, move it to Keychain.
        if let legacy = UserDefaults.standard.string(forKey: licenseKey), !legacy.isEmpty {
            saveLicenseToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: licenseKey)
            return legacy
        }
        return ""
    }

    static func savedStatus() -> String {
        UserDefaults.standard.string(forKey: statusKey) ?? "unknown"
    }

    static func savedMessage() -> String {
        UserDefaults.standard.string(forKey: lastMessageKey) ?? ""
    }

    static func savedExpiry() -> String {
        UserDefaults.standard.string(forKey: expiryKey) ?? ""
    }

    static let notificationName = Notification.Name("LicenseGateStore.changed")

    private static func postChange() {
        NotificationCenter.default.post(name: notificationName, object: nil)
    }

    static func persist(license: String, validated: Bool, status: String, message: String, expiry: String = "") {
        saveLicenseToKeychain(license)
        UserDefaults.standard.set(validated, forKey: validatedKey)
        UserDefaults.standard.set(status, forKey: statusKey)
        UserDefaults.standard.set(message, forKey: lastMessageKey)
        UserDefaults.standard.set(expiry, forKey: expiryKey)
        if validated {
            saveConfirmation(for: license)
        } else {
            deleteConfirmation()
        }
        postChange()
    }

    static func persistLastResponse(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
        UserDefaults.standard.set(sanitized, forKey: lastResponseKey)
        postChange()
    }

    static func savedLastResponse() -> String {
        UserDefaults.standard.string(forKey: lastResponseKey) ?? ""
    }

    static func persist(license: String, validated: Bool) {
        let existingExpiry = savedExpiry()
        persist(
            license: license,
            validated: validated,
            status: validated ? KeyAuthLicenseState.valid.rawValue : KeyAuthLicenseState.invalid.rawValue,
            message: validated ? KeyAuthLicenseState.valid.summary : KeyAuthLicenseState.invalid.summary,
            expiry: existingExpiry
        )
    }

    static func clear() {
        deleteLicenseFromKeychain()
        UserDefaults.standard.removeObject(forKey: licenseKey)
        UserDefaults.standard.removeObject(forKey: validatedKey)
        UserDefaults.standard.removeObject(forKey: statusKey)
        UserDefaults.standard.removeObject(forKey: lastMessageKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
        UserDefaults.standard.removeObject(forKey: lastResponseKey)
        deleteConfirmation()
        postChange()
    }

    // MARK: - Keychain helpers for license
    private static let licenseService = "com.3105.keyauth.license"
    private static let licenseAccount = "license"

    private static func saveLicenseToKeychain(_ license: String) {
        guard let data = license.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: licenseService,
            kSecAttrAccount as String: licenseAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private static func loadLicenseFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: licenseService,
            kSecAttrAccount as String: licenseAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func deleteLicenseFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: licenseService,
            kSecAttrAccount as String: licenseAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Try to parse saved expiry into Date
    static func savedExpiryDate() -> Date? {
        let raw = savedExpiry().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }

        let candidates = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy",
            "dd-MM-yyyy"
        ]
        for fmt in candidates {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        // numeric values: could be epoch seconds, epoch milliseconds, or seconds remaining
        if let n = Double(raw) {
            if n > 1_000_000_000_000.0 {
                // milliseconds since epoch
                return Date(timeIntervalSince1970: n / 1000.0)
            } else if n > 1_500_000_000.0 {
                // seconds since epoch (reasonable recent date)
                return Date(timeIntervalSince1970: n)
            } else {
                // Ambiguous small numeric value: treat 1..31 as days (KeyAuth may return '1' for 1 day)
                if n > 0 && n <= 31 {
                    return Date().addingTimeInterval(n * 24 * 60 * 60)
                }
                // otherwise treat as seconds remaining
                return Date().addingTimeInterval(n)
            }
        }
        return nil
    }

    private static func deriveExpiryFromLicenseKey() -> Date? {
        let key = savedLicense().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let upper = key.uppercased()
        if upper.contains("MES") || upper.contains("MONTH") {
            return Date().addingTimeInterval(TimeInterval(30 * 24 * 60 * 60))
        }
        if upper.contains("SEM") || upper.contains("WEEK") {
            return Date().addingTimeInterval(TimeInterval(7 * 24 * 60 * 60))
        }
        if upper.contains("DIA") || upper.contains("DAY") {
            return Date().addingTimeInterval(TimeInterval(1 * 24 * 60 * 60))
        }

        // Try to extract numeric+unit patterns (e.g. "30 days", "72 hours")
        let pattern = "(\\d+)\\s*(days?|day|d|weeks?|week|w|months?|month|m|hours?|hour|h)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = upper as NSString
        let matches = re.matches(in: upper, range: NSRange(location: 0, length: ns.length))
        if let m = matches.first, m.numberOfRanges >= 3 {
            let numRange = m.range(at: 1)
            let unitRange = m.range(at: 2)
            if numRange.location != NSNotFound, unitRange.location != NSNotFound {
                let numStr = ns.substring(with: numRange)
                let unitStr = ns.substring(with: unitRange).lowercased()
                if let value = Double(numStr) {
                    if unitStr.hasPrefix("d") || unitStr.contains("day") {
                        return Date().addingTimeInterval(value * 24 * 60 * 60)
                    }
                    if unitStr.hasPrefix("w") || unitStr.contains("week") {
                        return Date().addingTimeInterval(value * 7 * 24 * 60 * 60)
                    }
                    if unitStr.hasPrefix("m") || unitStr.contains("month") {
                        return Date().addingTimeInterval(value * 30 * 24 * 60 * 60)
                    }
                    if unitStr.hasPrefix("h") || unitStr.contains("hour") {
                        return Date().addingTimeInterval(value * 60 * 60)
                    }
                }
            }
        }
        return nil
    }

    static func remainingDays() -> Int? {
        guard let date = savedExpiryDate() else { return nil }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return 0 }
        let daysDouble = interval / (24.0 * 60.0 * 60.0)
        return Int(ceil(daysDouble))
    }

    static func isValid() -> Bool {
        if !KeyAuthConfig.matchesPersistedRuntimeSignature() {
            return false
        }

        guard let confirmation = loadConfirmation(),
              confirmation.license == savedLicense(),
              confirmation.runtimeSignature == KeyAuthConfig.runtimeSignature,
              confirmation.hardwareID == KeyAuthConfig.hardwareID() else { return false }

        let now = Date().timeIntervalSince1970
        let recentSuccessfulValidation = confirmation.validatedAt > 0
            && now >= confirmation.validatedAt
            && (now - confirmation.validatedAt) <= (24 * 60 * 60)
        guard recentSuccessfulValidation else { return false }

        // If expiry is available, consider license valid only while expiry is in the future.
        if let expiryDate = savedExpiryDate() {
            return expiryDate.timeIntervalSinceNow > 0
        }

        // No expiry information: fall back to the recent validation checkpoint.
        return true
    }

    static func shouldForceLogout() -> Bool {
        if !KeyAuthConfig.matchesPersistedRuntimeSignature() {
            return true
        }

        let license = savedLicense()
        guard !license.isEmpty else { return false }

        let normalizedStatus = savedStatus().lowercased()
        let explicitInvalidStatus = normalizedStatus.contains("expired")
            || normalizedStatus.contains("expiration")
            || normalizedStatus.contains("invalid")
            || normalizedStatus.contains("revoked")
            || normalizedStatus.contains("banned")
            || normalizedStatus.contains("used")
            || normalizedStatus.contains("already in use")
            || normalizedStatus.contains("already used")
            || normalizedStatus.contains("hwid")
            || normalizedStatus.contains("hwid_mismatch")

        if explicitInvalidStatus { return true }

        if let expiryDate = savedExpiryDate() {
            return expiryDate.timeIntervalSinceNow <= 0
        }

        return false
    }

    static func clearAndForceLogout() {
        clear()
    }

    private static func saveConfirmation(for license: String) {
        let confirmation = LicenseConfirmation(
            license: license,
            runtimeSignature: KeyAuthConfig.runtimeSignature,
            hardwareID: KeyAuthConfig.hardwareID(),
            validatedAt: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(confirmation) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: confirmationService,
            kSecAttrAccount as String: confirmationAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func loadConfirmation() -> LicenseConfirmation? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: confirmationService,
            kSecAttrAccount as String: confirmationAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LicenseConfirmation.self, from: data)
    }

    private static func deleteConfirmation() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: confirmationService,
            kSecAttrAccount as String: confirmationAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
