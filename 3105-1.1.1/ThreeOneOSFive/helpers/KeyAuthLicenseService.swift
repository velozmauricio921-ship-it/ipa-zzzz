import Foundation
import UIKit

// Small helper to parse date strings from KeyAuth responses.
// Tries ISO8601 (with and without fractional seconds), then a few common formats.
private func parseDateString(_ s: String) -> Date? {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: trimmed) { return d }

    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: trimmed) { return d }

    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)

    let formats = [
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "dd/MM/yyyy",
        "dd-MM-yyyy"
    ]
    for f in formats {
        df.dateFormat = f
        if let d = df.date(from: trimmed) { return d }
    }

    return nil
}

enum KeyAuthConfig {
    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static var baseURL: String {
        info("KeyAuthBaseURL") ?? "https://keyauth.win/api/1.2/"
    }

    static var appName: String {
        info("KeyAuthAppName") ?? "Mauricio2007veloz's Application"
    }

    static var ownerID: String {
        info("KeyAuthOwnerID") ?? "iQk2hpwc8Z"
    }

    static var appSecret: String {
        info("KeyAuthAppSecret") ?? info("KeyAuthSellerKey") ?? ""
    }

    static func hardwareID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}

struct KeyAuthInitResponse: Decodable {
    let success: Bool
    let sessionid: String?
    let message: String?
}

struct KeyAuthValidationResponse: Decodable {
    let success: Bool?
    let status: String?
    let message: String?
    let result: String?
    let error: String?
    let expiry: String?
    let level: String?
    let subscriptions: [String]?
    let hwid: String?

    var rawText: String {
        [status, result, message, error, expiry, level]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var state: KeyAuthLicenseState {
        let normalized = rawText.lowercased()

        if normalized.contains("expired") || normalized.contains("expiration") {
            return .expired
        }
        if normalized.contains("already used") || normalized.contains("already in use") || normalized.contains("in use") || normalized.contains("used") {
            return .used
        }
        if normalized.contains("success") || normalized.contains("valid") || normalized.contains("active") || normalized.contains("activated") {
            return .valid
        }
        if normalized.contains("invalid") || normalized.contains("not found") || normalized.contains("error") || normalized.contains("banned") {
            return .invalid
        }
        if let success = success {
            return success ? .valid : .invalid
        }
        return .unknown
    }

    var isValid: Bool {
        switch state {
        case .valid:
            return true
        case .invalid, .expired, .used, .unknown:
            return false
        }
    }
}

enum KeyAuthLicenseService {
    static func validate(licenseKey: String) async throws -> KeyAuthValidationResponse {
        let cleanKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw KeyAuthLicenseError.emptyLicense
        }

        let appName = KeyAuthConfig.appName
        let ownerID = KeyAuthConfig.ownerID
        let appSecret = KeyAuthConfig.appSecret

        if appName.isEmpty || ownerID.isEmpty || appSecret.isEmpty {
            throw KeyAuthLicenseError.invalidConfiguration
        }

        // PASO 1: Init session
        guard var initComponents = URLComponents(string: KeyAuthConfig.baseURL) else {
            throw KeyAuthLicenseError.invalidConfiguration
        }

        initComponents.queryItems = [
            URLQueryItem(name: "type", value: "init"),
            URLQueryItem(name: "name", value: appName),
            URLQueryItem(name: "ownerid", value: ownerID),
            URLQueryItem(name: "secret", value: appSecret),
            URLQueryItem(name: "version", value: "1.0")
        ]

        guard let initURL = initComponents.url else {
            throw KeyAuthLicenseError.invalidConfiguration
        }

        print("[KeyAuth] INIT URL: \(initURL.absoluteString)")

        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "GET"
        initRequest.setValue("KeyAuth", forHTTPHeaderField: "User-Agent")
        initRequest.timeoutInterval = 20

        let (initData, initResponse) = try await URLSession.shared.data(for: initRequest)
        guard let httpInit = initResponse as? HTTPURLResponse else {
            throw KeyAuthLicenseError.badResponse
        }
        if !(200...299).contains(httpInit.statusCode) {
            let body = String(data: initData, encoding: .utf8)
            print("[KeyAuth] Init failed HTTP \(httpInit.statusCode): \(body ?? "(no body)")")
            LicenseGateStore.persistLastResponse(body: body ?? "")
            throw KeyAuthLicenseError.requestFailedWithBody(httpInit.statusCode, body)
        }

        let initResult: KeyAuthInitResponse
        do {
            initResult = try JSONDecoder().decode(KeyAuthInitResponse.self, from: initData)
        } catch {
            let body = String(data: initData, encoding: .utf8)
            print("[KeyAuth] Failed to decode init response: \(body ?? "(no body)")")
            throw KeyAuthLicenseError.decodingFailed(body)
        }

        guard initResult.success, let sessionID = initResult.sessionid else {
            throw KeyAuthLicenseError.initFailed(initResult.message ?? "Error iniciando sesión en KeyAuth.")
        }

        print("[KeyAuth] sessionID: \(sessionID)")

        // PASO 2: Validate license using sessionid
        guard var valComponents = URLComponents(string: KeyAuthConfig.baseURL) else {
            throw KeyAuthLicenseError.invalidConfiguration
        }

        valComponents.queryItems = [
            URLQueryItem(name: "type", value: "license"),
            URLQueryItem(name: "key", value: cleanKey),
            URLQueryItem(name: "hwid", value: KeyAuthConfig.hardwareID()),
            URLQueryItem(name: "sessionid", value: sessionID),
            URLQueryItem(name: "name", value: appName),
            URLQueryItem(name: "ownerid", value: ownerID)
        ]

        guard let valURL = valComponents.url else {
            throw KeyAuthLicenseError.invalidConfiguration
        }

        print("[KeyAuth] VALIDATE URL: \(valURL.absoluteString)")
        print("[KeyAuth] VALIDATE hwid: \(KeyAuthConfig.hardwareID())")

        var valRequest = URLRequest(url: valURL)
        valRequest.httpMethod = "GET"
        valRequest.setValue("KeyAuth", forHTTPHeaderField: "User-Agent")
        valRequest.timeoutInterval = 20

        let (valData, valResponse) = try await URLSession.shared.data(for: valRequest)
        guard let httpVal = valResponse as? HTTPURLResponse else {
            throw KeyAuthLicenseError.badResponse
        }
        if !(200...299).contains(httpVal.statusCode) {
            let body = String(data: valData, encoding: .utf8)
            print("[KeyAuth] License check failed HTTP \(httpVal.statusCode): \(body ?? "(no body)")")
            LicenseGateStore.persistLastResponse(body: body ?? "")
            throw KeyAuthLicenseError.requestFailedWithBody(httpVal.statusCode, body)
        }

        let valResult: KeyAuthValidationResponse
        do {
            valResult = try JSONDecoder().decode(KeyAuthValidationResponse.self, from: valData)
        } catch {
            let body = String(data: valData, encoding: .utf8)
            print("[KeyAuth] Failed to decode license response: \(body ?? "(no body)")")
            throw KeyAuthLicenseError.decodingFailed(body)
        }

        // If server provides explicit `success`, trust it; otherwise use heuristic `isValid`.
        let valid: Bool
        if let explicitSuccess = valResult.success {
            valid = explicitSuccess
        } else {
            valid = valResult.isValid
        }

        let summaryText = valResult.rawText.isEmpty ? valResult.state.summary : valResult.rawText

        // Determine expiration text: prefer decoded string, otherwise try to extract from raw JSON (could be numeric)
        var expirationText = valResult.expiry ?? ""
        if expirationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let jsonObj = try? JSONSerialization.jsonObject(with: valData, options: []),
               let dict = jsonObj as? [String: Any] {
                if let expNum = dict["expiry"] as? NSNumber {
                    // Numeric expiry may be: milliseconds since epoch, seconds since epoch, or seconds remaining.
                    let n = expNum.doubleValue
                    let resolvedDate: Date
                    if n > 1_000_000_000_000.0 {
                        // very large -> milliseconds since epoch
                        resolvedDate = Date(timeIntervalSince1970: n / 1000.0)
                    } else if n > 1_500_000_000.0 {
                        // reasonable epoch in seconds (post-2017)
                        resolvedDate = Date(timeIntervalSince1970: n)
                    } else {
                        // small number: treat as seconds remaining
                        resolvedDate = Date().addingTimeInterval(n)
                    }
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    expirationText = iso.string(from: resolvedDate)
                } else if let expStr = dict["expiry"] as? String {
                    expirationText = expStr
                }
            }
        }

        // If still empty, try multiple heuristics:
        // 1) derive from license key tags (MES/SEM/DIA)
        // 2) extract durations from server message text ("30 days", "72 hours")
        // 3) if server provides a creation/used date in JSON, combine it with a duration found in JSON/text
        if expirationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let upperKey = cleanKey.uppercased()
                var durationCandidate: (value: Double, unit: String)?
                if upperKey.contains("MES") || upperKey.contains("MONTH") {
                    durationCandidate = (30, "day")
                } else if upperKey.contains("SEM") || upperKey.contains("WEEK") {
                    durationCandidate = (7, "day")
                } else if upperKey.contains("DIA") || upperKey.contains("DAY") {
                    durationCandidate = (1, "day")
                }

                // Try to extract durations from server message text as a fallback (e.g., "30 days", "1 month", "72 hours")
                if durationCandidate == nil {
                    if let candidate = deriveDuration(from: valResult.rawText) {
                        durationCandidate = candidate
                    }
                }

            // Parse JSON for created/used dates and per-field durations
            if let jsonObj = try? JSONSerialization.jsonObject(with: valData, options: []),
               let dict = jsonObj as? [String: Any] {
                // Attempt to find explicit expiry keys
                let expiryKeys = ["expiry","expires","expires_at","expiration","expirationDate","expiration_date","expiresAt"]
                for k in expiryKeys {
                    if let v = dict[k] as? NSNumber {
                            // handle numeric expiry heuristically (ms / epoch seconds / seconds remaining)
                            let n = v.doubleValue
                            let resolved: Date
                            if n > 1_000_000_000_000.0 {
                                resolved = Date(timeIntervalSince1970: n / 1000.0)
                            } else if n > 1_500_000_000.0 {
                                resolved = Date(timeIntervalSince1970: n)
                            } else {
                                resolved = Date().addingTimeInterval(n)
                            }
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: resolved)
                        break
                    } else if let v = dict[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let d = parseDateString(v) {
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: d)
                            break
                        }
                    }

                // If still empty, prefer expiry/timeleft from nested info->subscriptions
                if expirationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let info = dict["info"] as? [String: Any], let subs = info["subscriptions"] as? [Any], let first = subs.first as? [String: Any] {
                        if let expVal = first["expiry"] as? NSNumber {
                            let n = expVal.doubleValue
                            let resolved: Date
                            if n > 1_000_000_000_000.0 {
                                resolved = Date(timeIntervalSince1970: n / 1000.0)
                            } else if n > 1_500_000_000.0 {
                                resolved = Date(timeIntervalSince1970: n)
                            } else {
                                resolved = Date().addingTimeInterval(n)
                            }
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: resolved)
                        } else if let expStr = first["expiry"] as? String, let d = parseDateString(expStr) {
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: d)
                        } else if let timeleft = first["timeleft"] as? NSNumber {
                            let secs = timeleft.doubleValue
                            let resolved = Date().addingTimeInterval(secs)
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: resolved)
                        } else if let timeleftStr = first["timeleft"] as? String, let secs = Double(timeleftStr) {
                            let resolved = Date().addingTimeInterval(secs)
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expirationText = iso.string(from: resolved)
                        }
                    }
                }
                }

                if expirationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Look for creation/used date as base
                    var baseDate: Date? = nil
                    let candidateDateKeys = ["created","created_at","creation","creation_date","date","used","used_at","lastlogin","last_login"]
                    for k in candidateDateKeys {
                        if let v = dict[k] as? NSNumber {
                            baseDate = Date(timeIntervalSince1970: v.doubleValue)
                            break
                        } else if let v = dict[k] as? String, let d = parseDateString(v) {
                            baseDate = d
                            break
                        }
                    }

                    // If no explicit duration yet, scan all string fields for a duration pattern
                    if durationCandidate == nil {
                        for (_, v) in dict {
                            if let s = v as? String, let cand = deriveDuration(from: s) {
                                durationCandidate = cand
                                break
                            }
                        }
                    }

                    // If we have a base date and a duration, compute expiry
                    if let cand = durationCandidate {
                        let base = baseDate ?? Date()
                        let expiryDate = applyDuration(base: base, value: cand.value, unit: cand.unit)
                        let iso = ISO8601DateFormatter()
                        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        expirationText = iso.string(from: expiryDate)
                    }
                }
            }
        }

        if let raw = String(data: valData, encoding: .utf8) {
            LicenseGateStore.persistLastResponse(body: raw)
        }

        // Persist server response and validity
        LicenseGateStore.persist(
            license: cleanKey,
            validated: valid,
            status: valResult.state.rawValue,
            message: summaryText,
            expiry: expirationText
        )

        return valResult
    }

    // Attempt to parse a duration (number + unit) from freeform text and return (value, unit).
    // Unit returned is normalized: "day", "week", "month", "hour".
    private static func deriveDuration(from text: String) -> (Double, String)? {
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*(days?|day|d|weeks?|week|w|months?|month|m|hours?|hour|h|horas|dias|semanas|meses)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let m = matches.first, m.numberOfRanges >= 3 else { return nil }
        let numRange = m.range(at: 1)
        let unitRange = m.range(at: 2)
        guard numRange.location != NSNotFound, unitRange.location != NSNotFound else { return nil }
        let numStr = ns.substring(with: numRange)
        let unitStr = ns.substring(with: unitRange).lowercased()
        guard let value = Double(numStr) else { return nil }

        if unitStr.hasPrefix("d") || unitStr.contains("dia") || unitStr.contains("day") {
            return (value, "day")
        }
        if unitStr.hasPrefix("w") || unitStr.contains("sem") || unitStr.contains("week") {
            return (value, "week")
        }
        if unitStr.hasPrefix("m") || unitStr.contains("month") || unitStr.contains("mes") {
            return (value, "month")
        }
        if unitStr.hasPrefix("h") || unitStr.contains("hour") || unitStr.contains("hora") {
            return (value, "hour")
        }
        return nil
    }

    // Apply a parsed duration to a base date. For months, use Calendar to add months; for others, compute seconds.
    private static func applyDuration(base: Date, value: Double, unit: String) -> Date {
        switch unit {
        case "month":
            // For fractional months, convert to days approximation
            let intMonths = Int(floor(value))
            var date = base
            if intMonths > 0 {
                if let d = Calendar.current.date(byAdding: .month, value: intMonths, to: date) {
                    date = d
                }
            }
            let fractional = value - Double(intMonths)
            if fractional > 0 {
                let additionalDays = fractional * 30.0
                date = date.addingTimeInterval(additionalDays * 24 * 60 * 60)
            }
            return date
        case "week":
            return base.addingTimeInterval(value * 7 * 24 * 60 * 60)
        case "day":
            return base.addingTimeInterval(value * 24 * 60 * 60)
        case "hour":
            return base.addingTimeInterval(value * 60 * 60)
        default:
            return base
        }
    }
}
