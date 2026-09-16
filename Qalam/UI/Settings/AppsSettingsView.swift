import SwiftUI
import AppKit

/// Per-app and per-website settings: what QalamAI does in each app / site,
/// with "Inherit" falling back to the site → app → global value.
struct AppsSettingsView: View {
    @State private var store = ProfileStore.shared
    @State private var appState = AppState.shared
    @State private var prefs = UserPreferences.shared
    @State private var modes = WritingModeStore.shared
    @State private var selectedID: String?
    @State private var runningApps: [RunningAppsProvider.RunningApp] = []
    @State private var websiteDraft = ""
    @State private var websiteInvalid = false
    @State private var showAllRecent = false
    /// Edited locally and capped here (see `MyInfoSettingsView`).
    @State private var instructionsDraft = ""
    /// Writing samples per bundle id (personalization), loaded on appear.
    @State private var sampleCounts: [String: Int] = [:]

    private static let editorAnchor = "apps-editor"
    private static let recentPreviewCount = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.xl) {
                    header
                    addCard(proxy)
                    listCard(proxy)
                    editorSection
                        .id(Self.editorAnchor)
                }
                .padding(QSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                runningApps = RunningAppsProvider.regularApps()
                applyRequestedProfile(proxy)
            }
            .task { sampleCounts = await PersonalizationStore.shared.counts() }
            .onChange(of: appState.requestedProfileID) { _, _ in applyRequestedProfile(proxy) }
            .onChange(of: store.lastExternalApp) { _, _ in runningApps = RunningAppsProvider.regularApps() }
            .onChange(of: selectedID) { _, _ in
                instructionsDraft = selectedProfile?.customInstructions ?? ""
            }
            .onChange(of: instructionsDraft) { _, newValue in commitInstructions(newValue) }
            .onChange(of: websiteDraft) { _, _ in websiteInvalid = false }
        }
    }

    // MARK: - Data

    private var selectedProfile: AppProfile? {
        selectedID.flatMap { store.profile(id: $0) }
    }

    /// Configured profiles: apps first, then sites, by name.
    private var configured: [AppProfile] {
        store.profiles.filter(\.isConfigured).sorted { a, b in
            if a.kind != b.kind { return a.kind == .app }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Seen but not configured, most recent first.
    private var recent: [AppProfile] {
        store.profiles.filter { !$0.isConfigured }.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func select(_ id: String, _ proxy: ScrollViewProxy) {
        selectedID = id
        // After the editor re-lays out for the new selection.
        DispatchQueue.main.async {
            withAnimation(QAnimation.standard) {
                proxy.scrollTo(Self.editorAnchor, anchor: .top)
            }
        }
    }

    private func addApp(bundleID: String, name: String, _ proxy: ScrollViewProxy) {
        guard bundleID != Constants.bundleID else { return }
        let profile = store.ensureApp(bundleID: bundleID, name: name)
        select(profile.id, proxy)
    }

    private func addWebsite(_ proxy: ScrollViewProxy) {
        guard let host = ProfileStore.normalizeHost(websiteDraft) else {
            websiteInvalid = true
            return
        }
        let profile = store.ensureDomain(host: host)
        websiteDraft = ""
        select(profile.id, proxy)
    }

    /// Opens the profile requested via `AppState.showSettings(tab:profileID:)`.
    private func applyRequestedProfile(_ proxy: ScrollViewProxy) {
        guard let id = appState.requestedProfileID else { return }
        appState.requestedProfileID = nil
        if store.profile(id: id) == nil {
            if id.hasPrefix("app:") {
                let bundleID = String(id.dropFirst("app:".count))
                guard !bundleID.isEmpty, bundleID != Constants.bundleID else { return }
                store.ensureApp(bundleID: bundleID,
                                name: ProfileStore.appDisplayName(bundleID: bundleID) ?? bundleID)
            } else if id.hasPrefix("domain:") {
                guard let host = ProfileStore.normalizeHost(String(id.dropFirst("domain:".count))) else { return }
                store.ensureDomain(host: host)
            }
        }
        guard store.profile(id: id) != nil else { return }
        select(id, proxy)
    }

    private func commitInstructions(_ newValue: String) {
        guard let id = selectedID else { return }
        let limit = ProfileStore.profileInstructionsLimit
        if newValue.count > limit {
            instructionsDraft = String(newValue.prefix(limit))
            return
        }
        guard (store.profile(id: id)?.customInstructions ?? "") != newValue else { return }
        store.update(id: id) { $0.customInstructions = newValue }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.appsHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.appsSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Add

    private func addCard(_ proxy: ScrollViewProxy) -> some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    frontmostButton(proxy)
                    runningAppsMenu(proxy)
                    Spacer()
                }
                QDivider()
                HStack(spacing: 8) {
                    QTextField(placeholder: L.t(.appsWebsitePlaceholder), text: $websiteDraft,
                               icon: "globe", onSubmit: { addWebsite(proxy) })
                    QButton(title: L.t(.appsAddWebsite), icon: "plus", style: .secondary, size: .small,
                            disabled: websiteDraft.trimmingCharacters(in: .whitespaces).isEmpty) {
                        addWebsite(proxy)
                    }
                }
                if websiteInvalid {
                    Text(L.t(.appsWebsiteInvalid))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.destructive)
                }
                Text(L.t(.appsAddHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func frontmostButton(_ proxy: ScrollViewProxy) -> some View {
        if let app = store.lastExternalApp {
            QButton(title: String(format: L.t(.appsAddFrontmostFmt), app.name),
                    icon: "plus.app", style: .secondary, size: .small) {
                addApp(bundleID: app.bundleID, name: app.name, proxy)
            }
        } else {
            QButton(title: L.t(.appsAddFrontmost), icon: "plus.app",
                    style: .secondary, size: .small, disabled: true) {}
        }
    }

    private func runningAppsMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(runningApps) { app in
                Button(app.name) {
                    addApp(bundleID: app.id, name: app.name, proxy)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                Text(L.t(.appsAddRunning))
            }
            .font(QFonts.caption)
            .foregroundStyle(QColors.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - List

    private func listCard(_ proxy: ScrollViewProxy) -> some View {
        let configured = self.configured
        let recent = self.recent
        let visibleRecent = showAllRecent ? recent : Array(recent.prefix(Self.recentPreviewCount))
        return QCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L.t(.appsConfigured))
                if configured.isEmpty {
                    emptyCaption(L.t(.appsConfiguredEmpty))
                } else {
                    VStack(spacing: 4) {
                        ForEach(configured) { profileRow($0, proxy) }
                    }
                }
                QDivider()
                sectionTitle(L.t(.appsRecent))
                if recent.isEmpty {
                    emptyCaption(L.t(.appsRecentEmpty))
                } else {
                    VStack(spacing: 4) {
                        ForEach(visibleRecent) { profileRow($0, proxy) }
                    }
                    if recent.count > Self.recentPreviewCount {
                        Button {
                            withAnimation(QAnimation.quick) { showAllRecent.toggle() }
                        } label: {
                            Text(showAllRecent ? L.t(.appsShowFewer)
                                               : String(format: L.t(.appsShowAllFmt), recent.count))
                                .font(QFonts.caption)
                                .foregroundStyle(QColors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(L.t(.appsRecentSitesHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(QFonts.caption)
            .fontWeight(.semibold)
            .foregroundStyle(QColors.textTertiary)
    }

    private func emptyCaption(_ text: String) -> some View {
        Text(text)
            .font(QFonts.caption)
            .foregroundStyle(QColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    private func profileRow(_ profile: AppProfile, _ proxy: ScrollViewProxy) -> some View {
        let isSelected = selectedID == profile.id
        return Button {
            select(profile.id, proxy)
        } label: {
            HStack(spacing: 10) {
                profileIcon(profile, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textPrimary)
                        .lineLimit(1)
                    Text(profile.kind == .app ? profile.key : L.t(.appsWebsite))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let tag = summaryTag(profile) {
                    QTag(text: tag.text, style: tag.style)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? QColors.accent.opacity(0.12) : QColors.backgroundElevated)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.small, style: .continuous)
                    .strokeBorder(isSelected ? QColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileIcon(_ profile: AppProfile, size: CGFloat) -> some View {
        if profile.kind == .app, let image = AppIconCache.shared.icon(bundleID: profile.key) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: profile.kind == .domain ? "globe" : "app.dashed")
                .font(.system(size: size * 0.7))
                .foregroundStyle(QColors.textSecondary)
                .frame(width: size, height: size)
        }
    }

    private func summaryTag(_ profile: AppProfile) -> (text: String, style: QTagStyle)? {
        switch profile.activation {
        case .off?:       return (L.t(.appsActivationOff), .destructive)
        case .forceOnly?: return (L.t(.appsActivationForceOnly), .warning)
        case .alwaysOn?:  return (L.t(.appsActivationAlwaysOn), .success)
        case nil:         return profile.isConfigured ? (L.t(.appsCustomized), .accent) : nil
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorSection: some View {
        if let profile = selectedProfile {
            editorCard(profile)
        } else {
            QCard {
                HStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .foregroundStyle(QColors.textTertiary)
                    Text(L.t(.appsSelectPrompt))
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
    }

    private func editorCard(_ profile: AppProfile) -> some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                editorHeader(profile)
                QDivider()
                activationControl(profile)
                QDivider()
                writingModeControl(profile)
                QDivider()
                languageControl(profile)
                QDivider()
                autocorrectControl(profile)
                QDivider()
                instructionsControl(profile)
                // MARK: T4 tab-accept control
                if prefs.acceptWordKey == "tab" {
                    QDivider()
                    tabAcceptControl(profile)
                }
                // MARK: T5 display & compatibility controls
                QDivider()
                displayControl(profile)
                if profile.kind == .app {
                    QDivider()
                    compatibilityControl(profile)
                }
                // MARK: T6 recording control
                QDivider()
                recordingControl(profile)
                QDivider()
                editorActions(profile)
            }
        }
    }

    private func editorHeader(_ profile: AppProfile) -> some View {
        HStack(spacing: 12) {
            profileIcon(profile, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
                    .lineLimit(1)
                Text(profile.kind == .app ? profile.key : L.t(.appsWebsite))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let tag = summaryTag(profile) {
                QTag(text: tag.text, style: tag.style, showDot: true)
            }
        }
    }

    private func activationControl(_ profile: AppProfile) -> some View {
        controlBlock(title: L.t(.appsActivation), help: L.t(.appsActivationHelp)) {
            segmented([(L.t(.appsActivationInherit), nil),
                       (L.t(.appsActivationAlwaysOn), .alwaysOn),
                       (L.t(.appsActivationForceOnly), .forceOnly),
                       (L.t(.appsActivationOff), .off)] as [(String, ProfileActivation?)],
                      selection: profile.activation) { value in
                store.update(id: profile.id) { $0.activation = value }
            }
        }
    }

    private func writingModeControl(_ profile: AppProfile) -> some View {
        let known = modes.allModes
        let inheritTitle = profile.kind == .app
            ? String(format: L.t(.appsInheritValueFmt), modes.mode(id: prefs.activeModeID).name)
            : L.t(.appsInherit)
        let selection = Binding<String?>(
            get: { profile.writingModeId.flatMap { id in known.contains { $0.id == id } ? id : nil } },
            set: { value in store.update(id: profile.id) { $0.writingModeId = value } }
        )
        return HStack(alignment: .center, spacing: 12) {
            Text(L.t(.appsWritingMode))
                .font(QFonts.bodyMed)
                .foregroundStyle(QColors.textPrimary)
            Spacer()
            Picker(L.t(.appsWritingMode), selection: selection) {
                Text(inheritTitle).tag(String?.none)
                ForEach(known) { mode in
                    Text(mode.name).tag(Optional(mode.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func languageControl(_ profile: AppProfile) -> some View {
        controlBlock(title: L.t(.appsLanguage), help: L.t(.appsLanguageHelp)) {
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsLanguageAuto), .auto),
                       (L.t(.appsLanguageEnglish), .english),
                       (L.t(.appsLanguageArabic), .arabic)] as [(String, LanguagePreference?)],
                      selection: profile.languagePreference) { value in
                store.update(id: profile.id) { $0.languagePreference = value }
            }
        }
    }

    private func autocorrectControl(_ profile: AppProfile) -> some View {
        controlBlock(title: L.t(.appsAutocorrect), help: L.t(.appsAutocorrectHelp)) {
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsOn), true),
                       (L.t(.appsOff), false)] as [(String, Bool?)],
                      selection: profile.autocorrectEnabled) { value in
                store.update(id: profile.id) { $0.autocorrectEnabled = value }
            }
        }
    }

    /// Some apps use Tab themselves (indenting, moving between fields). Only
    /// shown while Tab is the accept key.
    private func tabAcceptControl(_ profile: AppProfile) -> some View {
        controlBlock(title: L.t(.appsTabAccept), help: L.t(.appsTabAcceptHelp)) {
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsTabAcceptOn), true),
                       (L.t(.appsTabAcceptOff), false)] as [(String, Bool?)],
                      selection: profile.tabAcceptEnabled) { value in
                store.update(id: profile.id) { $0.tabAcceptEnabled = value }
            }
        }
    }

    /// Where the suggestion is drawn: inline at the cursor, or in a bubble
    /// anchored to the field (for apps where inline lands in the wrong place).
    private func displayControl(_ profile: AppProfile) -> some View {
        controlBlock(title: L.t(.appsDisplay), help: L.t(.appsDisplayHelp)) {
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsDisplayInline), .inline),
                       (L.t(.appsDisplayMirror), .mirror)] as [(String, DisplayMode?)],
                      selection: profile.displayMode) { value in
                store.update(id: profile.id) { $0.displayMode = value }
                OverlayCoordinator.shared.invalidate()
            }
        }
    }

    /// Electron apps keep their accessibility tree switched off until an
    /// assistive client asks for it. Apps only.
    private func compatibilityControl(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.t(.appsCompat))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                if ElectronCompatibility.shared.isElectron(bundleID: profile.key) {
                    QTag(text: L.t(.appsCompatElectron), style: .accent)
                }
                Spacer()
            }
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsOn), true),
                       (L.t(.appsOff), false)] as [(String, Bool?)],
                      selection: profile.improveCompatibility) { value in
                store.update(id: profile.id) { $0.improveCompatibility = value }
                if value == true {
                    ElectronCompatibility.shared.applyNow(bundleID: profile.key)
                }
            }
            Text(L.t(.appsCompatHelp))
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Whether writing in this app / site may be kept for personalization.
    /// The saved count and the delete button are per app: a website's samples
    /// are counted under the browser they were typed in.
    private func recordingControl(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(.appsRecord))
                .font(QFonts.bodyMed)
                .foregroundStyle(QColors.textPrimary)
            segmented([(L.t(.appsInherit), nil),
                       (L.t(.appsOn), true),
                       (L.t(.appsOff), false)] as [(String, Bool?)],
                      selection: profile.recordWriting) { value in
                store.update(id: profile.id) { $0.recordWriting = value }
                WritingRecorder.shared.settingsChanged()
            }
            Text(L.t(.appsRecordHelp))
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if profile.kind == .app {
                HStack(spacing: 10) {
                    Text(String(format: L.t(.appsRecordSamplesFmt), sampleCounts[profile.key] ?? 0))
                        .font(QFonts.caption.monospacedDigit())
                        .foregroundStyle(QColors.textTertiary)
                    Spacer()
                    QButton(title: L.t(.appsRecordDelete), icon: "trash",
                            style: .ghost, size: .small,
                            disabled: (sampleCounts[profile.key] ?? 0) == 0) {
                        let bundleID = profile.key
                        Task {
                            await PersonalizationStore.shared.delete(bundleID: bundleID)
                            sampleCounts = await PersonalizationStore.shared.counts()
                        }
                    }
                }
            }
        }
    }

    private func instructionsControl(_ profile: AppProfile) -> some View {
        let limit = ProfileStore.profileInstructionsLimit
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t(.appsInstructions))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Spacer()
                Text("\(instructionsDraft.count) / \(limit)")
                    .font(QFonts.caption.monospacedDigit())
                    .foregroundStyle(instructionsDraft.count >= limit ? QColors.warning : QColors.textTertiary)
            }
            Text(L.t(.appsInstructionsHelp))
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            InstructionsEditor(text: $instructionsDraft,
                               placeholder: L.t(.appsInstructionsPlaceholder),
                               minHeight: 64)
        }
    }

    private func editorActions(_ profile: AppProfile) -> some View {
        HStack(spacing: 10) {
            QButton(title: L.t(.appsReset), icon: "arrow.uturn.backward",
                    style: .secondary, size: .small, disabled: !profile.isConfigured) {
                store.update(id: profile.id) { $0.resetToInherit() }
                instructionsDraft = ""
            }
            Spacer()
            QButton(title: L.t(.appsRemove), icon: "trash", style: .destructive, size: .small) {
                selectedID = nil
                store.delete(id: profile.id)
            }
        }
    }

    // MARK: - Controls

    private func controlBlock<Content: View>(title: String, help: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(QFonts.bodyMed)
                .foregroundStyle(QColors.textPrimary)
            content()
            Text(help)
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Segmented chips styled like the General tab's accept-key control.
    private func segmented<Value: Equatable>(_ options: [(String, Value)],
                                             selection: Value,
                                             onSelect: @escaping (Value) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let active = option.1 == selection
                Button {
                    withAnimation(QAnimation.quick) { onSelect(option.1) }
                } label: {
                    Text(option.0)
                        .font(QFonts.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(active ? .white : QColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(active ? QColors.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(QColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous)
                .strokeBorder(QColors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous))
    }
}

/// Regular (Dock) apps currently running, for "Add running app".
@MainActor
enum RunningAppsProvider {
    struct RunningApp: Identifiable, Hashable {
        let id: String      // bundle id
        let name: String
    }

    static func regularApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != Constants.bundleID else { return nil }
                return RunningApp(id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// App icons by bundle id, looked up once through LaunchServices.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []

    private init() {}

    func icon(bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard !missing.contains(bundleID) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        icons[bundleID] = image
        return image
    }
}
