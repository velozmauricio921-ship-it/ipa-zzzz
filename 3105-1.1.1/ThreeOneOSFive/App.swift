import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    // Start locked until we verify or user logs in
    @State private var showLicenseGate = true
    @AppStorage("keyauth.license.remember") private var rememberLicense = false
    
    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    // Update checks disabled to avoid showing update dialogs in builds

    private func preloadBundlePatches() {
        PatchProjectLibrary.ensurePreloadedPackagesInstalled()
        NotificationCenter.default.post(name: Notification.Name("PatchLibraryDidChange"), object: nil)
    }

    private func invalidateSessionImmediately() async {
        await MainActor.run {
            rememberLicense = false
            withAnimation(.easeInOut(duration: 0.25)) {
                showLicenseGate = true
            }
            LicenseGateStore.clear()
            NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
        }

        await DevicePatchService.deactivateAllActivePatches()
        NotificationCenter.default.post(name: Notification.Name("PatchLibraryDidChange"), object: nil)
    }

    // Validate saved license and toggle the license gate appropriately.
    // Validate saved license and optionally toggle the license gate UI.
    private func validateSavedLicenseAndToggleGate(updateUI: Bool = true) async {
        if !KeyAuthConfig.matchesPersistedRuntimeSignature() {
            await invalidateSessionImmediately()
            return
        }

        let saved = LicenseGateStore.savedLicense()
        guard !saved.isEmpty else {
            await MainActor.run { showLicenseGate = true }
            return
        }

        do {
            let response = try await KeyAuthLicenseService.validate(licenseKey: saved)
            await MainActor.run {
                // Explicitly close the session when the server says the license is expired or its expiry date is already past.
                let responseExpired = response.state == .expired
                    || (response.status?.lowercased().contains("expired") == true)
                    || (response.result?.lowercased().contains("expired") == true)
                    || (response.message?.lowercased().contains("expired") == true)

                let expiryDate: Date?
                if let expiryValue = response.expiry, !expiryValue.isEmpty {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    expiryDate = iso.date(from: expiryValue) ?? ISO8601DateFormatter().date(from: expiryValue)
                } else {
                    expiryDate = nil
                }

                let expiredByDate = expiryDate.map { $0.timeIntervalSinceNow <= 0 } ?? false

                let hwidOK = (response.hwid == nil) || (response.hwid!.isEmpty) || (response.hwid == KeyAuthConfig.hardwareID())
                let ok = response.isValid
                    && LicenseGateStore.isValid()
                    && hwidOK
                    && !responseExpired
                    && !expiredByDate

                if !ok {
                    Task {
                        await self.invalidateSessionImmediately()
                    }
                    return
                }

                // Only toggle the license gate UI if requested (preserve behavior for 'remember' option).
                if updateUI {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLicenseGate = false
                    }
                } else {
                    // still ensure NotificationCenter observers get updated state
                    NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                }
            }
        } catch {
            await MainActor.run {
                // Network/validation failure: do NOT immediately force the login UI when the user chose "remember"
                // If the user has a recent successful validation (e.g. within 24h), assume transient network and keep UI.
                if updateUI {
                    if rememberLicense {
                        let recent = LicenseGateStore.isValid()
                        if !recent {
                            // no recent validation — show gate
                            showLicenseGate = true
                        } else {
                            // keep current UI (do not open gate on transient errors)
                        }
                    } else {
                        // not remembered — be conservative and require re-login
                        showLicenseGate = true
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLicenseGate {
                    LicenseGateView {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLicenseGate = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                } else {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .opacity(showOnboarding ? 0 : 1)
                        .allowsHitTesting(!showOnboarding)

                    if showOnboarding {
                        OnboardingView {
                            OnboardingStore.markCompleted()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                showOnboarding = false
                            }
                            appState.detectSupport()
                            // update check intentionally disabled
                        }
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(1)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding && !showLicenseGate)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            // Update alert disabled
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                    preloadBundlePatches()
                    // If a saved license exists, refresh its state/expiry from KeyAuth.
                    // Only allow the validation to open the gate automatically when the user chose to remember the license.
                    if !LicenseGateStore.savedLicense().isEmpty {
                        Task {
                            await validateSavedLicenseAndToggleGate(updateUI: rememberLicense)
                        }
                    } else if !rememberLicense {
                        showLicenseGate = true
                    }

                    // Observe license store changes to toggle license gate
                    NotificationCenter.default.addObserver(forName: LicenseGateStore.notificationName, object: nil, queue: .main) { _ in
                        let valid = LicenseGateStore.isValid()
                        let forceLogout = LicenseGateStore.shouldForceLogout()

                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLicenseGate = !valid || forceLogout
                        }

                        // Revoke the session immediately when KeyAuth reports the license as expired, invalid, or removed.
                        // This must happen even if the user chose "remember" so the app cannot remain unlocked after server-side revocation.
                        if forceLogout {
                            rememberLicense = false
                            Task.detached(priority: .userInitiated) {
                                await DevicePatchService.deactivateAllActivePatches()
                                // notify UI lists that patches changed (receipts removed)
                                NotificationCenter.default.post(name: Notification.Name("PatchLibraryDidChange"), object: nil)
                                DispatchQueue.main.async {
                                    LicenseGateStore.clear()
                                }
                            }
                        }
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: LicenseGateStore.notificationName, object: nil)
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                guard !showOnboarding else { return }
                let saved = LicenseGateStore.savedLicense()
                guard !saved.isEmpty else { return }
                Task {
                    await validateSavedLicenseAndToggleGate(updateUI: rememberLicense || !showLicenseGate)
                }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
