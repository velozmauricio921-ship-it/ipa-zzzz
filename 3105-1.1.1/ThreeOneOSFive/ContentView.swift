import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var tabNavigation: AppTabNavigationState
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = false
    @AppStorage(FeatureVisibility.wallpapersStorageKey) private var wallpapersEnabled = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-files-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-patch-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-cleaner-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 4
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
        .onChange(of: cleanerEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onChange(of: wallpapersEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("3105")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView(
                cleanerEnabled: $cleanerEnabled,
                wallpapersEnabled: $wallpapersEnabled,
                wallpapersSupported: wallpapersSupported
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession
            )
        case .patches:
            PatchProjectsView()
        case .cleaner:
            CleanerView()
        case .wallpapers:
            WallpaperLabView()
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(
            cleanerEnabled: cleanerEnabled,
            wallpapersEnabled: wallpapersEnabled,
            wallpapersSupported: wallpapersSupported
        )
    }

    private var wallpapersSupported: Bool {
        WallpaperFeatureSupportPolicy.isSupported(major: AppInfo.versionTuple.major)
    }

    private var selectedVisibleSection: AppSection {
        guard let section = AppSection(rawValue: tabNavigation.selectedTab),
              featureVisibility.isVisible(section) else {
            return .home
        }
        return section
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .files: return "tab.files"
        case .patches: return "tab.patches"
        case .cleaner: return "tab.cleaner"
        case .wallpapers: return "Info Key"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .files: return "folder.fill"
        case .patches: return "shippingbox.fill"
        case .cleaner: return "sparkles"
        case .wallpapers: return "key.fill"
        }
    }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showLogs = false
    @Binding var cleanerEnabled: Bool
    @Binding var wallpapersEnabled: Bool
    let wallpapersSupported: Bool

    private let bgDark = Color(red: 0.02, green: 0.09, blue: 0.17)
    private let bgMid = Color(red: 0.04, green: 0.18, blue: 0.30)
    private let panel = Color(red: 0.10, green: 0.26, blue: 0.37)
    private let panelAlt = Color(red: 0.08, green: 0.20, blue: 0.31)
    private let accent = Color(red: 0.45, green: 0.92, blue: 1.00)
    private let accentSoft = Color(red: 0.83, green: 0.96, blue: 1.00)
    private let stroke = Color(red: 0.42, green: 0.88, blue: 1.00).opacity(0.9)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [bgDark, bgMid],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerPanel
                        developerPanel
                        contactPanel
                        deviceStatusPanel
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
        }
    }

    private var headerPanel: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BAIJ STORE")
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .foregroundStyle(accentSoft)
                    .tracking(-1.2)
                    .textCase(.uppercase)

                Text("PATCH CONTROL CENTER")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .tracking(1.8)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.28, blue: 0.41))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(stroke, lineWidth: 2)
                    )
            )

            Circle()
                .fill(accent)
                .frame(width: 42, height: 42)
                .padding(.trailing, 18)
                .overlay(
                    Text("B")
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.20))
                )
        }
    }

    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(white: 0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                Text("DEVELOPER INFO")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accentSoft)
                    .tracking(0.9)
                    .textCase(.uppercase)
            }

            Text("VELOZxIOS")
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.leading, 48)

            Divider().background(Color.white.opacity(0.14))

            HStack {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)

                Text("DEVELOPER INFO • DESIGN 1")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack {
                Text("BUILD")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accentSoft)
                    .tracking(1.6)
                    .textCase(.uppercase)
                Spacer()
                Text("1.2")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(stroke, lineWidth: 1.8)
                )
        )
    }

    private var contactPanel: some View {
        VStack(spacing: 12) {
            contactButton(title: "Discord", subtitle: "Join my Discord", icon: "bubble.left.fill", tint: accent, url: "https://discord.gg/aBQyPTbpgc")
            contactButton(title: "WhatsApp", subtitle: "Contact me", icon: "message.fill", tint: accent, url: "https://wa.me/584124788825")
            contactButton(title: "VELOZxIOS", subtitle: "Developer", icon: "person.fill", tint: accent, url: "https://t.me/VELOZxIOS")
        }
    }

    private func contactButton(title: String, subtitle: String, icon: String, tint: Color, url: String) -> some View {
        Group {
            if let destination = URL(string: url) {
                Link(destination: destination) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(white: 0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(tint)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(panelAlt)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(stroke, lineWidth: 1.1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var deviceStatusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DEVICE STATUS")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accentSoft)
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                statusRow(label: "iOS", value: AppInfo.osVersion)
                statusRow(label: "Device", value: AppInfo.displayMachineName)
                statusRow(
                    label: "Support",
                    value: appState.isSupported ? "SUPPORTED" : "UNSUPPORTED",
                    valueColor: appState.isSupported ? .green : .orange
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(panelAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(stroke, lineWidth: 1.5)
                )
        )
    }

    private func statusRow(label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .textCase(.uppercase)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay(
            Divider().background(Color.white.opacity(0.12)),
            alignment: .bottom
        )
    }
}
