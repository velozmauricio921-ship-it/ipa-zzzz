import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @StateObject private var store = PatchProjectStore()
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var isWorkingAction = false
    @State private var receiptRefresh = UUID()
    @State private var actionAlert: PatchStoreAlert?
    @State private var restoreFailureCounts: [UUID: Int] = [:]
    @State private var selectedGroup: String? = nil
    @State private var selectedSubgroup: String? = nil

    private var filteredItems: [PatchLibraryItem] {
        // Start from full list and apply category/subcategory filtering first
        var items = store.items
        if let group = selectedGroup {
            items = items.filter { $0.categories.first == group }
        }
        if let subgroup = selectedSubgroup {
            items = items.filter { $0.categories.count > 1 && $0.categories[1] == subgroup }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            if item.packageURL.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard let project = item.project else { return false }
            return project.name.localizedCaseInsensitiveContains(query)
                || project.allBundleIdentifiers.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
                || project.directories.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                }
                || project.rules.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                        || $0.replacementFilename.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private var availableGroups: [String] {
        let groups = Set(store.items.compactMap { $0.categories.first })
        return Array(groups).sorted()
    }

    private func availableSubgroups(for group: String) -> [String] {
        let subs = Set(store.items.compactMap { item -> String? in
            let cats = item.categories
            guard cats.first == group, cats.count > 1 else { return nil }
            return cats[1]
        })
        return Array(subs).sorted()
    }

    private func refreshSelectionState() {
        guard let selected = selectedID,
              let item = store.items.first(where: { $0.id == selected }) else {
            selectedID = nil
            return
        }
        _ = DevicePatchService.latestReceipt(projectID: item.id)
    }

    init() {
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.10, blue: 0.18), Color(red: 0.12, green: 0.16, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    ZStack(alignment: .trailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BAIJ STORE")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.83, green: 0.96, blue: 1.00))
                                .tracking(-1.2)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(red: 0.12, green: 0.22, blue: 0.34))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(AppTheme.accent.opacity(0.9), lineWidth: 2)
                                )
                        )

                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 42, height: 42)
                            .padding(.trailing, 18)
                            .overlay(
                                Text("B")
                                    .font(.system(size: 21, weight: .heavy))
                                    .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.20))
                            )
                    }
                    .padding(.horizontal, 14)

                    if !availableGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableGroups, id: \.self) { g in
                                    Button(action: {
                                        if selectedGroup == g {
                                            selectedGroup = nil
                                            selectedSubgroup = nil
                                        } else {
                                            selectedGroup = g
                                            selectedSubgroup = nil
                                        }
                                    }) {
                                        Text(g)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .padding(.vertical, 9)
                                            .padding(.horizontal, 14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(selectedGroup == g ? AppTheme.accent : Color(white: 0.18))
                                            )
                                            .foregroundStyle(selectedGroup == g ? .black : .white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppTheme.pageInset)
                            .padding(.vertical, 8)
                        }
                        if let group = selectedGroup {
                            let subs = availableSubgroups(for: group)
                            if !subs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(subs, id: \.self) { s in
                                            Button(action: {
                                                if selectedSubgroup == s { selectedSubgroup = nil } else { selectedSubgroup = s }
                                            }) {
                                                Text(s)
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                    .padding(.vertical, 7)
                                                    .padding(.horizontal, 12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(selectedSubgroup == s ? AppTheme.accent : Color(white: 0.18))
                                                    )
                                                    .foregroundStyle(selectedSubgroup == s ? .black : .white)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, AppTheme.pageInset)
                                    .padding(.bottom, 6)
                                }
                            }
                        }
                    }

                    List {
                        if store.items.isEmpty && !store.isBusy {
                            emptyState
                                .listRowSeparator(.hidden)
                        } else if filteredItems.isEmpty && !store.isBusy {
                            searchEmptyState
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems) { item in
                                Button(action: {
                                    if selectedID == item.id {
                                        selectedID = nil
                                    } else {
                                        selectedID = item.id
                                        refreshSelectionState()
                                    }
                                }) {
                                    PatchProjectRow(item: item, language: language)
                                        .overlay(
                                            Group {
                                                if selectedID == item.id {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(AppTheme.accent, lineWidth: 2)
                                                        .shadow(color: AppTheme.accent.opacity(0.55), radius: 10, x: 0, y: 0)
                                                } else {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.clear, lineWidth: 0)
                                                }
                                            }
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                offsets.map { filteredItems[$0] }.forEach(store.delete)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            // Bottom action bar for selected feature (inside NavigationStack content)
            if let sel = selectedID, let selectedItem = store.items.first(where: { $0.id == sel }) {
                let selectedHasReceipt = DevicePatchService.latestReceipt(projectID: selectedItem.id) != nil
                VStack(spacing: 0) {
                    Divider()
                    HStack(alignment: .center, spacing: 12) {
                        let selectedTitle = selectedItem.packageURL.deletingPathExtension().lastPathComponent
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTitle.isEmpty ? (selectedItem.project?.name ?? language.text("patch.title")) : selectedTitle)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(selectedHasReceipt ? "ACTIVE" : "INACTIVE")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedHasReceipt ? AppTheme.accent : .white.opacity(0.7))
                                .textCase(.uppercase)
                        }

                        Spacer()

                        if isWorkingAction {
                            ProgressView()
                                .tint(AppTheme.accent)
                        } else if selectedItem.isLocked {
                            Button {
                                Task.detached(priority: .userInitiated) {
                                    await MainActor.run { store.requestUnlock(for: selectedItem) }
                                }
                            } label: {
                                Text(language.text("patch.unlock"))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(AppTheme.accent.opacity(0.12))
                                    )
                                    .foregroundStyle(AppTheme.accent)
                            }
                        } else {
                            Toggle("", isOn: Binding(
                                get: { selectedHasReceipt },
                                set: { newValue in
                                    guard !isWorkingAction else { return }
                                    if newValue {
                                        Task.detached(priority: .userInitiated) {
                                            await MainActor.run { isWorkingAction = true }
                                            do {
                                                let project = selectedItem.summary.schemaVersion >= 2 ? try PatchProjectLibrary.synchronizeWorkspace(item: selectedItem) : (selectedItem.project!)
                                                _ = try await DevicePatchService.apply(project: project)
                                                await MainActor.run {
                                                    store.reload()
                                                    refreshSelectionState()
                                                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                                                }
                                            } catch let error as PatchPackageError {
                                                await MainActor.run {
                                                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: error.localizationKey, messageArgument: error.localizationArgument)
                                                }
                                            } catch {
                                                await MainActor.run {
                                                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                                                }
                                            }
                                            await MainActor.run {
                                                isWorkingAction = false
                                                receiptRefresh = UUID()
                                                refreshSelectionState()
                                            }
                                        }
                                    } else {
                                        Task.detached(priority: .userInitiated) {
                                            await MainActor.run { isWorkingAction = true }
                                            do {
                                                if let receipt = DevicePatchService.latestReceipt(projectID: selectedItem.id) {
                                                    try DevicePatchService.restore(receipt: receipt)
                                                    await MainActor.run {
                                                        store.reload()
                                                        refreshSelectionState()
                                                        actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                                                    }
                                                }
                                            } catch let error as PatchPackageError {
                                                await MainActor.run {
                                                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: error.localizationKey, messageArgument: error.localizationArgument)
                                                }
                                            } catch {
                                                await MainActor.run {
                                                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                                                }
                                            }
                                            await MainActor.run {
                                                isWorkingAction = false
                                                receiptRefresh = UUID()
                                                refreshSelectionState()
                                            }
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(AppTheme.accent)
                        }
                    }
                    .padding(.horizontal, AppTheme.pageInset)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.10, green: 0.18, blue: 0.26))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1.2)
                            )
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .id(receiptRefresh)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } // NavigationStack end
        .navigationTitle(language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCreate = true
                    } label: {
                        Label(language.text("patch.new"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    if store.isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .disabled(store.isBusy)
                .accessibilityLabel(language.text("patch.add"))
            }
        }
        .sheet(isPresented: $showImporter) {
            FileDocumentPicker(
                allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showImporter = false
                    if case .success(let urls) = result, let url = urls.first {
                        store.importPackage(at: url)
                    }
                },
                onCancel: {
                    showImporter = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCreate) {
            PatchProjectEditorView(
                existingProject: nil,
                passwordIsProtected: false
            ) { project, password in
                store.create(project: project, password: password)
            }
        }
        .sheet(item: $draftCoordinator.request) { request in
            PatchProjectEditorView(
                existingProject: nil,
                passwordIsProtected: false,
                initialDraft: request.draft
            ) { project, password in
                store.create(project: project, password: password)
                draftCoordinator.clear()
            }
        }
        .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
            PatchUnlockView(store: store)
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .onAppear(perform: consumeExternalImport)
        .onChange(of: draftCoordinator.importRequest?.id) { _ in
            consumeExternalImport()
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("patch.empty_title"))
                .font(.headline)
            Text(language.text("patch.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("patch.search_empty"))
                .font(.headline)
            Text(language.text("patch.search_empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            PatchCubeIcon(isLocked: item.isLocked)

            VStack(alignment: .leading, spacing: 4) {
                let fileTitle = item.packageURL.deletingPathExtension().lastPathComponent
                Text((fileTitle.isEmpty ? (item.project?.name ?? language.text("patch.locked_project")) : fileTitle).uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock").uppercased()
                     : language.text(
                        item.summary.schemaVersion >= 2 ? "patch.workspace_items_count" : "patch.rules_count",
                        Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
                     ).uppercased())
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.8))
            }

            Spacer()

            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.10, green: 0.18, blue: 0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1.2)
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 6)
    }
}

private struct PatchCubeIcon: View {
    let isLocked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.12, green: 0.22, blue: 0.34), Color(red: 0.07, green: 0.16, blue: 0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.78, green: 0.95, blue: 1.0), Color(red: 0.44, green: 0.77, blue: 0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 24, height: 24)

                Circle()
                    .stroke(Color(red: 0.12, green: 0.24, blue: 0.36), lineWidth: 2)
                    .frame(width: 18, height: 18)

                Rectangle()
                    .fill(Color(red: 0.12, green: 0.24, blue: 0.36))
                    .frame(width: 2, height: 22)

                Rectangle()
                    .fill(Color(red: 0.12, green: 0.24, blue: 0.36))
                    .frame(width: 22, height: 2)

                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 28, height: 28)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color(red: 0.08, green: 0.15, blue: 0.24))
                    )
                    .offset(x: 10, y: 10)
            }
        }
        .frame(width: 34, height: 34)
        .cornerRadius(10)
    }
}

private struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(language.text("patch.password_once_message"))
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

private struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?
    

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    var body: some View {
        List {
            if let item, let project = item.project {
                if isWorkspaceProject {
                    Section {
                        ForEach(project.allBundleIdentifiers, id: \.self) { bundleID in
                            Label {
                                Text(bundleID)
                                    .font(.subheadline.monospaced())
                            } icon: {
                                Image(systemName: "app.dashed")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        LabeledContent(language.text("patch.files")) {
                            Text("\(project.rules.count)")
                        }
                        LabeledContent(language.text("patch.folders")) {
                            Text("\(project.directories.count)")
                        }
                        if let workspaceURL = item.workspaceURL {
                            NavigationLink {
                                FileBrowserView(
                                    containerPath: workspaceURL.path,
                                    title: project.name,
                                    bundleID: nil
                                )
                            } label: {
                                Label(
                                    language.text("patch.open_workspace"),
                                    systemImage: "folder"
                                )
                            }
                        }
                    } header: {
                        Text(language.text("patch.workspace"))
                    } footer: {
                        Text(language.text("patch.workspace_detail_footer"))
                    }
                } else {
                    Section {
                        ForEach(project.rules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                HStack(spacing: 10) {
                                    ruleSummary(rule)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(language.text("patch.edit_rule_hint"))
                        }
                    } header: {
                        Text(language.text("patch.rules"))
                    } footer: {
                        Text(language.text("patch.legacy_footer"))
                    }
                }

                Section(language.text("patch.password")) {
                    HStack(spacing: 12) {
                        Image(systemName: item.summary.isPasswordProtected ? "lock.fill" : "lock.open")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)
                        Text(language.text(item.summary.isPasswordProtected
                            ? "patch.password_locked"
                            : "patch.no_password"))
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        showApplyConfirmation = true
                    } label: {
                        actionLabel("patch.apply", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(isWorking)

                    if receipt != nil {
                        Button(role: .destructive) {
                            showRestoreConfirmation = true
                        } label: {
                            actionLabel("patch.restore", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(isWorking)
                    }

                    // Export disabled to avoid leaking .3105 files
                } footer: {
                    Text(language.text("patch.apply_footer"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item?.project?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                } else if !isWorkspaceProject {
                    Button(language.text("patch.edit")) { showEditor = true }
                        .disabled(item?.project == nil)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let item, let project = item.project {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) { apply() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_confirm_title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore"), role: .destructive) { restore() }
            Button(language.text("common.cancel"), role: .cancel) {}
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(language.text(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let item, let baseProject = item.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try await DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    // Export functionality removed to avoid accidental leaking of .3105 packages.

    private func restore() {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }
}

private struct PatchShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PatchActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
