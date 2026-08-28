import Foundation

struct LicenseGateStore {
    private static let validatedKey = "keyauth.license.validated"
    private static let licenseKey = "keyauth.license.key"
    private static let statusKey = "keyauth.license.status"
    private static let lastMessageKey = "keyauth.license.lastMessage"
    private static let expiryKey = "keyauth.license.expiry"
    private static let lastResponseKey = "keyauth.license.lastResponse"

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
        postChange()
    }

    static func persistLastResponse(body: String) {
        UserDefaults.standard.set(body, forKey: lastResponseKey)
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
                // treat as seconds remaining
                return Date().addingTimeInterval(n)
            }
        }
        // If still nil, attempt to derive expiry from the license string itself (e.g., keys containing MES/SEM/DIA or durations)
        if let derived = deriveExpiryFromLicenseKey() {
            return derived
        }

        // Fallback: if the license is marked validated but no expiry found, assume a default 30-day expiry
        // and persist it so the UI shows a countdown. This helps when users create simple keys without tags.
        if isUnlocked(), !savedLicense().isEmpty {
            let defaultExpiry = Date().addingTimeInterval(TimeInterval(30 * 24 * 60 * 60))
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let s = iso.string(from: defaultExpiry)
            UserDefaults.standard.set(s, forKey: expiryKey)
            postChange()
            return defaultExpiry
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
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
        return days
    }

    static func isValid() -> Bool {
        let validated = isUnlocked()
        let license = savedLicense()
        guard validated && !license.isEmpty else { return false }
        if let days = remainingDays() {
            return days > 0
        }
        return true
    }
}
