import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum WallpaperPickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct WallpaperLabView: View {
    @Environment(\.appLanguage) private var language
    @State private var report: WallpaperAccessReport?
    @State private var accessError: String?
    @State private var packages: [WallpaperStagedPackage] = []
    @State private var receipts: [WallpaperInstallReceipt] = []
    @State private var selectedPackageID: UUID?
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var showImporter = false
    @State private var alert: WallpaperLabAlert?
    @State private var hasLoaded = false
    @AppStorage("keyauth.license.remember") private var rememberLicense = false
    @State private var countdownText: String = "—"
    @State private var countdownTimer: Timer?

    private var selectedPackage: WallpaperStagedPackage? {
        packages.first { $0.id == selectedPackageID }
    }

    private var activeReceipts: [WallpaperInstallReceipt] {
        receipts.filter { $0.status == .installed || $0.status == .preparing }
    }

    // MARK: - Key info section
    private var injectedKey: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "KeyAuthAppSecret") as? String, !v.isEmpty { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: "KeyAuthSellerKey") as? String, !v.isEmpty { return v }
        return ""
    }

    private func masked(_ s: String) -> String {
        guard !s.isEmpty else { return "—" }
        let visiblePrefix = 6
        let visibleSuffix = 4
        if s.count <= visiblePrefix + visibleSuffix {
            return s
        }
        let prefix = s.prefix(visiblePrefix)
        let suffix = s.suffix(visibleSuffix)
        let midCount = max(0, s.count - visiblePrefix - visibleSuffix)
        return "\(prefix)" + String(repeating: "•", count: midCount) + "\(suffix)"
    }

    // MARK: - Info Key section (replaces wallpaper preview)
    private var keyInfoSection: some View {
        Section {
            infoKeyCard
        } header: {
            Text("Info Key")
        }
    }

    // Helpers for Info Key card
    private var statusText: String {
        let status = LicenseGateStore.savedStatus().lowercased()
        if status.contains("valid") || status.contains("active") || status.contains("success") {
            return "LICENCIA ACTIVA"
        }
        if status.contains("expired") || status.contains("expiration") {
            return "LICENCIA EXPIRADA"
        }
        if status.contains("invalid") || status.contains("error") || status.contains("not found") {
            return "LICENCIA INVÁLIDA"
        }
        return "LICENCIA INACTIVA"
    }

    private var expiryText: String {
        let raw = LicenseGateStore.savedExpiry().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "—" }
        return formatExpiry(raw)
    }

    private var remainingDaysText: String {
        if let days = LicenseGateStore.remainingDays() {
            if days <= 0 { return "Expirada" }
            return "Quedan \(days) días"
        }
        return "—"
    }

    private var maskedLicenseText: String { masked(LicenseGateStore.savedLicense()) }

    private func parseExpiryDate(_ raw: String) -> Date? {
        let candidates = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy",
            "dd-MM-yyyy"
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        for fmt in candidates {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    private func formatExpiry(_ raw: String) -> String {
        guard let date = parseExpiryDate(raw) else { return raw }
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }

    // Helper: format numeric epoch/relative values into human date string
    private func formatNumericDate(_ n: Double) -> String {
        let date: Date
        if n > 1_000_000_000_000.0 {
            date = Date(timeIntervalSince1970: n / 1000.0)
        } else if n > 1_500_000_000.0 {
            date = Date(timeIntervalSince1970: n)
        } else {
            // small number treated as seconds from now
            date = Date().addingTimeInterval(n)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func formattedNumericDate(from value: Any?) -> String? {
        guard let v = value else { return nil }
        if let s = v as? String, let d = Double(s) {
            return formatNumericDate(d)
        }
        if let num = v as? NSNumber {
            return formatNumericDate(num.doubleValue)
        }
        return nil
    }

    private var infoKeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(AppTheme.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                Text(statusText)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .center, spacing: 8) {
                Text(countdownText)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Vence: \(expiryText)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 6)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.accent)

                Text("Key")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                Text(maskedLicenseText)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }

            Text(LicenseGateStore.savedMessage().isEmpty ? "licencia válida" : LicenseGateStore.savedMessage())
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(white: 0.82))

            Button(action: {
                let raw = LicenseGateStore.savedLastResponse()
                var display = "(sin respuesta)"
                if !raw.isEmpty {
                    if let data = raw.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let dict = json as? [String: Any] {
                        var parts: [String] = []
                        if let succ = dict["success"] { parts.append("success: \(succ)") }
                        if let msg = dict["message"] as? String { parts.append("message: \(msg)") }
                        if let info = dict["info"] as? [String: Any] {
                            if let user = info["username"] as? String { parts.append("usuario: \(user)") }
                            if let hwid = info["hwid"] as? String { parts.append("hwid: \(hwid)") }

                            if let createdStr = formattedNumericDate(from: info["createdate"]) {
                                parts.append("creada: \(createdStr)")
                            }
                            if let lastStr = formattedNumericDate(from: info["lastlogin"]) {
                                parts.append("último login: \(lastStr)")
                            }

                            if let subs = info["subscriptions"] as? [Any], let first = subs.first as? [String: Any] {
                                if let key = first["key"] as? String { parts.append("sub.key: \(key)") }
                                // expiry may be numeric string
                                if let exp = first["expiry"] as? String {
                                    if let n = Double(exp) {
                                        parts.append("expiry: \(formatNumericDate(n))")
                                    } else {
                                        parts.append("expiry: \(exp)")
                                    }
                                } else if let expNum = first["expiry"] as? NSNumber {
                                    parts.append("expiry: \(formatNumericDate(expNum.doubleValue))")
                                }
                                if let timeleft = first["timeleft"] as? NSNumber {
                                    let secs = Int(timeleft.intValue)
                                    let d = secs / 86400
                                    let h = (secs % 86400) / 3600
                                    let m = (secs % 3600) / 60
                                    parts.append("timeleft: \(d)d \(h)h \(m)m")
                                }
                            }
                        }
                        if parts.isEmpty {
                            display = String(data: data, encoding: .utf8) ?? raw
                        } else {
                            display = parts.joined(separator: "\n")
                        }
                    } else {
                        display = raw
                    }
                }

                alert = WallpaperLabAlert(kind: .message(titleKey: "info_key.response", message: display))
            }) {
                Text("Ver respuesta")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(AppTheme.accent)
                    .background(Capsule().fill(Color(white: 0.18)))
            }
            .buttonStyle(.plain)
            
            Button(action: {
                // Force logout: clear persisted license and unset "remember"
                rememberLicense = false
                LicenseGateStore.clear()
                // Notify observers (App will observe and show login if needed)
                NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                alert = WallpaperLabAlert(kind: .message(titleKey: "info_key.cleared", message: "Cerraste sesión"))
            }) {
                Text("Cerrar sesión")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.white)
                    .background(Capsule().stroke(AppTheme.accent, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.accent, lineWidth: 1.8))
    }

    var body: some View {
        NavigationStack {
            List {
                keyInfoSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Info Key")
            .navigationBarTitleDisplayMode(.inline)
            .alert(item: $alert, content: alertContent)
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                NotificationCenter.default.addObserver(forName: LicenseGateStore.notificationName, object: nil, queue: .main) { _ in
                    // trigger view update
                    hasLoaded.toggle(); hasLoaded.toggle()
                }
                // start countdown timer
                startCountdownTimer()
            }
            .onChange(of: rememberLicense) { new in
                // If user chose to remember this device, proactively validate and refresh expiry/state
                if new, !LicenseGateStore.savedLicense().isEmpty {
                    Task {
                        do {
                            _ = try await KeyAuthLicenseService.validate(licenseKey: LicenseGateStore.savedLicense())
                            // LicenseGateStore.persist is called inside validate; notify view
                            NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                        } catch {
                            // ignore — validation failures will be reflected via persisted lastResponse
                            NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                        }
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: LicenseGateStore.notificationName, object: nil)
                stopCountdownTimer()
            }
        }
    }

    private func startCountdownTimer() {
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateCountdown()
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdown() {
        if let expiryDate = LicenseGateStore.savedExpiryDate() {
            let interval = Int(expiryDate.timeIntervalSinceNow)
            if interval <= 0 {
                countdownText = "Expirada"
                return
            }
            let days = interval / 86400
            let hours = (interval % 86400) / 3600
            let minutes = (interval % 3600) / 60
            let seconds = interval % 60
            countdownText = String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, seconds)
        } else {
            countdownText = "—"
        }
    }

    private func alertContent(_ alert: WallpaperLabAlert) -> Alert {
        switch alert.kind {
        case .message(let titleKey, let message):
            return Alert(
                title: Text(titleKey),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct WallpaperLabAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case message(titleKey: String, message: String)
    }
}
