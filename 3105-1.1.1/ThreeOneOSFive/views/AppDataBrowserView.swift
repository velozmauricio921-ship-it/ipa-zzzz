import SwiftUI
import UIKit

struct AppDataBrowserView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var locations: [StorageLocation] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isShowingFolderPicker = false
    @State private var workspaceURL: URL?
    @EnvironmentObject private var authorizedFolderProvider: AuthorizedFolderProvider
    @Binding private var tabSession: FilesTabSession

    init(tabSession: Binding<FilesTabSession>) {
        _tabSession = tabSession
    }

    private var filteredLocations: [StorageLocation] {
        guard !searchText.isEmpty else { return locations }
        let q = searchText.lowercased()
        return locations.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var overlayState: AppBrowserOverlayState {
        if isLoading && locations.isEmpty { return .loading }
        if locations.isEmpty { return .empty }
        if filteredLocations.isEmpty { return .noResults }
        return .none
    }

    private var interfaceAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.20)
    }

    var body: some View {
        NavigationStack(path: activeNavigationPath) {
            appList
            .navigationTitle(language.text("browser.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    FilesTabToolbarButton(session: $tabSession)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isShowingFolderPicker = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel(language.text("browser.choose_folder"))
                }
            }
            .onAppear {
                if workspaceURL == nil {
                    workspaceURL = try? PatchWorkspaceService.patchesRootURL()
                }
                reload()
            }
            .navigationDestination(for: FileBrowserDestination.self) { destination in
                if destination.startPath == destination.containerPath {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        accessKind: destination.accessKind,
                        authorizedFolderID: destination.authorizedFolderID,
                        filesTabSession: $tabSession
                    )
                } else {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        startPath: destination.startPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        accessKind: destination.accessKind,
                        authorizedFolderID: destination.authorizedFolderID,
                        filesTabSession: $tabSession
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            AuthorizedFolderPicker(
                onSelection: { result in
                    isShowingFolderPicker = false
                    switch result {
                    case .success(let url):
                        switch authorizedFolderProvider.add(url) {
                        case .success:
                            errorMessage = nil
                            reload()
                        case .failure(let issue):
                            errorMessage = issue.localizedDescription
                        }
                    case .failure(let issue):
                        errorMessage = issue.localizedDescription
                    }
                },
                onCancel: { isShowingFolderPicker = false }
            )
            .ignoresSafeArea()
        }
    }

    private var activeNavigationPath: Binding<[FileBrowserDestination]> {
        Binding(
            get: { tabSession.activeTab?.navigationPath ?? [] },
            set: { tabSession.setActiveNavigationPath($0) }
        )
    }

    private var appList: some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                FilesTabStrip(session: $tabSession)
            }
            AppSearchField(
                text: $searchText,
                prompt: language.text("browser.search_locations"),
                clearLabel: language.text("common.clear")
            )
            Divider()
            appRows
        }
    }

    private var appRows: some View {
        List {
            if let workspaceURL {
                Section(language.text("browser.workspace")) {
                    let workspaceDestination = FileBrowserDestination(
                        containerPath: workspaceURL.path,
                        startPath: workspaceURL.path,
                        title: "3105",
                        bundleID: nil,
                        accessKind: .appOwned
                    )
                    NavigationLink(value: workspaceDestination) {
                        HStack(spacing: 10) {
                            AppRowIcon(systemName: "folder.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("3105")
                                    .font(.subheadline.weight(.semibold))
                                Text(language.text("browser.workspace_subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        openInNewTabButton(workspaceDestination)
                    }
                }
            }
            Section {
                ForEach(filteredLocations) { location in
                    let selectedFolder = authorizedFolder(for: location.authorizedFolderID)
                    let destination = FileBrowserDestination(
                        containerPath: location.rootURL.path,
                        startPath: location.rootURL.path,
                        title: language.text(location.title),
                        bundleID: nil,
                        accessKind: location.accessKind,
                        authorizedFolderID: location.authorizedFolderID
                    )
                    NavigationLink(value: destination) {
                        HStack(spacing: 10) {
                            AppRowIcon(systemName: location.accessKind == .userSelected ? "folder.badge.checkmark" : "folder.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.text(location.title))
                                    .font(.subheadline.weight(.semibold))
                                Text(language.text(location.subtitleKey))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        openInNewTabButton(destination)
                        if let selectedFolder {
                            Button(role: .destructive) {
                                authorizedFolderProvider.remove(selectedFolder)
                                reload()
                            } label: {
                                Label(language.text("browser.remove_folder"), systemImage: "folder.badge.minus")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(language.text("browser.available_locations"))
                    Spacer()
                    Text(language.text("browser.locations_count", Int64(filteredLocations.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
            Section {
                Text(errorMessage ?? language.text("browser.no_app_catalog"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 48)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            Group {
                switch overlayState {
                case .loading:
                    ProgressView(language.text("browser.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    emptyView
                case .noResults:
                    searchEmptyView
                case .none:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .animation(interfaceAnimation, value: overlayState)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            BrowserAppIcon(app: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(app.bundleID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !app.version.isEmpty {
                Text(app.version)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
    }

    private func openInNewTabButton(_ destination: FileBrowserDestination) -> some View {
        Button {
            tabSession.openTab(navigationPath: [destination])
        } label: {
            Label(language.text("browser.open_new_tab"), systemImage: "square.on.square")
        }
    }

    private func authorizedFolder(for folderID: UUID?) -> AuthorizedFolder? {
        guard let folderID else { return nil }
        let folders = authorizedFolderProvider.folders
        return folders.first { folder in
            folder.id == folderID
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(errorMessage ?? language.text("browser.no_authorized_locations"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button(language.text("browser.retry")) { reload() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var searchEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("browser.search_locations_empty"))
                .font(.subheadline.weight(.medium))
            Text(language.text("browser.search_locations_empty_message"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func reload() {
        isLoading = true
        errorMessage = nil
        WQIntegrationDiagnostics.emit()
        locations = ContainerDiscoveryService.availableLocations(
            authorizedFolders: authorizedFolderProvider.folders
        )
        if case .failure(let issue) = ContainerDiscoveryService.installedApplications() {
            log("browser: app catalog unavailable: \(issue.localizedDescription)")
        }
        isLoading = false
    }
}

private enum AppBrowserOverlayState: Equatable {
    case loading
    case empty
    case noResults
    case none
}

struct BrowserAppIcon: View {
    let app: InstalledApp
    @State private var resolvedIcon: UIImage?
    @State private var didRequestIcon = false

    init(app: InstalledApp) {
        self.app = app
        _resolvedIcon = State(initialValue: app.icon)
    }

    var body: some View {
        Group {
            if let resolvedIcon {
                Image(uiImage: resolvedIcon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app")
                    .font(.system(size: AppTheme.rowIconSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: AppTheme.appIconSize, height: AppTheme.appIconSize)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard resolvedIcon == nil, !didRequestIcon else { return }
            didRequestIcon = true
            let bundleID = app.bundleID
            DispatchQueue.global(qos: .utility).async {
                let icon = iconForBundleID(bundleID)
                DispatchQueue.main.async {
                    resolvedIcon = icon
                }
            }
        }
    }
}
