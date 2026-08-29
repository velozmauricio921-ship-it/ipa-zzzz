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
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @State private var expiryWatcher = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    private func preloadBundlePatches() {
        PatchProjectLibrary.ensurePreloadedPackagesInstalled()
        NotificationCenter.default.post(name: Notification.Name("PatchLibraryDidChange"), object: nil)
    }

    // Validate saved license and toggle the license gate appropriately.
    // Validate saved license and optionally toggle the license gate UI.
    private func validateSavedLicenseAndToggleGate(updateUI: Bool = true) async {
        let saved = LicenseGateStore.savedLicense()
        guard !saved.isEmpty else {
            await MainActor.run { showLicenseGate = true }
            return
        }

        do {
            let response = try await KeyAuthLicenseService.validate(licenseKey: saved)
            await MainActor.run {
                // If server provided explicit `success`, require it. Otherwise use response.isValid.
                let serverHasExplicitSuccess = (response.success != nil)
                let serverDeclaredSuccess = (response.success == true) || (response.status?.lowercased().contains("success") == true) || (response.result?.lowercased().contains("success") == true)

                let hwidOK = (response.hwid == nil) || (response.hwid!.isEmpty) || (response.hwid == KeyAuthConfig.hardwareID())

                let ok: Bool
                if serverHasExplicitSuccess {
                    ok = (response.success == true) && hwidOK
                } else {
                    ok = (serverDeclaredSuccess || response.isValid) && hwidOK
                }

                // Only toggle the license gate UI if requested (preserve behavior for 'remember' option).
                if updateUI {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLicenseGate = !ok
                    }
                } else {
                    // still ensure NotificationCenter observers get updated state
                    NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                }
            }
        } catch {
            await MainActor.run {
                // if validation fails due to network, be conservative and show gate
                if updateUI { showLicenseGate = true }
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
                            checkForUpdate()
                        }
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(1)
                    }
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding && !showLicenseGate)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                    checkForUpdate()
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLicenseGate = !LicenseGateStore.isValid()
                        }
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: LicenseGateStore.notificationName, object: nil)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                // On resume, refresh saved license state from KeyAuth if present.
                if !LicenseGateStore.savedLicense().isEmpty {
                    Task {
                        await validateSavedLicenseAndToggleGate(updateUI: rememberLicense)
                    }
                } else if !rememberLicense {
                    // if not remembered and no saved license, force login on resume
                    showLicenseGate = true
                }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .onReceive(expiryWatcher) { _ in
                // If a saved expiry exists and is in the past, force logout and show license gate.
                if let expiry = LicenseGateStore.savedExpiryDate() {
                    if expiry.timeIntervalSinceNow <= 0 {
                        // Clear persisted license and force login
                        rememberLicense = false
                        LicenseGateStore.clear()
                        NotificationCenter.default.post(name: LicenseGateStore.notificationName, object: nil)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLicenseGate = true
                        }
                    }
                }
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
