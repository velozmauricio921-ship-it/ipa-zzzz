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
    @State private var postLicenseBootstrapRan = false
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

    private func completePostLicenseBootstrap() {
        guard !postLicenseBootstrapRan else { return }
        postLicenseBootstrapRan = true

        // Safe build: never invoke exploit/sandbox checks after the license gate.
        // Keep the app in a fail-closed mode to avoid crashes caused by native exploit code.
        checkForUpdate()
        preloadBundlePatches()

        if !LicenseGateStore.savedLicense().isEmpty {
            Task {
                await validateSavedLicenseAndToggleGate(updateUI: rememberLicense)
            }
        } else if !rememberLicense {
            showLicenseGate = true
        }

        NotificationCenter.default.addObserver(forName: LicenseGateStore.notificationName, object: nil, queue: .main) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showLicenseGate = !LicenseGateStore.isValid()
            }
        }
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
                        DispatchQueue.main.async {
                            completePostLicenseBootstrap()
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
                            // Avoid automatically invoking the kernel exploit on launch.
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
                if !showOnboarding, !showLicenseGate {
                    completePostLicenseBootstrap()
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

        // Safe mode: never deal with exploit/sandbox detection in this build.
        exploitStatus = .notStarted
        unsupportedMessage = nil
    }

    private func maybeAutoRunKernelExploit() {
        // Exploit must never run automatically. This function is intentionally inert.
        log("app: explicit exploit launch is required; automatic startup execution has been disabled")
    }

    private func refreshKernelExploitStatus() {
        // Safe mode: exploit state is intentionally ignored.
        kernelExploitRunning = false
        exploitStatus = .notStarted
    }

    func runKernelExploitIfNeeded() {
        // Hard safety gate: exploit execution is disabled in this build.
        kernelExploitRunning = false
        exploitStatus = .notStarted
        log("app: kernel exploit execution disabled in this build; no automatic launch allowed")
    }
}
