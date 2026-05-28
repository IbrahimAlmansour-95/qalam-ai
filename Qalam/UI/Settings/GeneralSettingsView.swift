import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var prefs = UserPreferences.shared
    @State private var l10n = LocalizationStore.shared
    @State private var newExcluded: String = ""
    @State private var availableApps: [RunningApp] = []

    struct RunningApp: Identifiable, Hashable {
        let id: String
        let name: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                languageCard
                engineCard
                togglesCard
                correctionsCard
                contextSourcesCard
                suggestionLengthCard
                tuningCard
                excludedAppsCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { loadRunningApps() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.generalHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.generalSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var languageCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t(.generalLanguage))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Text(L.t(.generalLanguageHelp))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(LocalizationStore.Language.allCases, id: \.self) { lang in
                            languageChip(lang)
                        }
                    }
                }
            }
        }
    }

    private func languageChip(_ lang: LocalizationStore.Language) -> some View {
        let active = l10n.current == lang
        return Button {
            l10n.current = lang
        } label: {
            Text(lang.displayName)
                .font(QFonts.bodyMed)
                .foregroundStyle(active ? .white : QColors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(active ? QColors.accent : QColors.backgroundElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var engineCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t(.generalEngine))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Text(L.t(.generalEngineHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
                HStack(spacing: 6) {
                    engineChip("ollama", label: L.t(.engineOllama), enabled: true)
                    engineChip("appleIntelligence",
                               label: L.t(.engineAppleIntelligence),
                               enabled: AppleIntelligenceBackend.isAvailable)
                }
                if !AppleIntelligenceBackend.isAvailable,
                   let reason = AppleIntelligenceBackend.unavailableReason {
                    Text("Apple Intelligence: \(reason)")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
            }
        }
    }

    private func engineChip(_ id: String, label: String, enabled: Bool) -> some View {
        let active = prefs.engine == id
        return Button {
            if enabled { prefs.engine = id }
        } label: {
            Text(label)
                .font(QFonts.bodyMed)
                .foregroundStyle(active ? .white : (enabled ? QColors.textSecondary : QColors.textTertiary))
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(active ? QColors.accent : QColors.backgroundElevated)
                .clipShape(Capsule())
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var contextSourcesCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t(.generalContextSources))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Text(L.t(.generalContextSourcesHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
                QDivider()
                contextToggle(L.t(.ctxBroader), help: L.t(.ctxBroaderHelp),
                              isOn: Binding(get: { prefs.broaderContextEnabled },
                                            set: { prefs.broaderContextEnabled = $0 }))
                QDivider()
                contextToggle(L.t(.ctxClipboard), help: L.t(.ctxClipboardHelp),
                              isOn: Binding(get: { prefs.clipboardContextEnabled },
                                            set: { prefs.clipboardContextEnabled = $0 }))
                QDivider()
                contextToggle(L.t(.ctxScreen), help: L.t(.ctxScreenHelp),
                              isOn: Binding(get: { prefs.screenContextEnabled },
                                            set: { newVal in
                                                prefs.screenContextEnabled = newVal
                                                if newVal { ScreenOCRContext.shared.requestPermission() }
                                            }))
            }
        }
    }

    private func contextToggle(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            QToggle(isOn: isOn, label: title)
            Text(help)
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var togglesCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                QToggle(isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { newVal in
                        prefs.launchAtLogin = newVal
                        setLaunchAtLogin(newVal)
                    }
                ), label: L.t(.generalLaunchAtLogin))
                QDivider()
                QToggle(isOn: Binding(
                    get: { prefs.showInMenuBar },
                    set: { prefs.showInMenuBar = $0 }
                ), label: L.t(.generalShowInMenuBar))
                QDivider()
                QToggle(isOn: Binding(
                    get: { prefs.isEnabled },
                    set: { prefs.isEnabled = $0 }
                ), label: L.t(.generalEnableSuggestions))
                QDivider()
                contextToggle(L.t(.generalSpaceAfterTab), help: L.t(.generalSpaceAfterTabHelp),
                              isOn: Binding(get: { prefs.spaceAfterAccept },
                                            set: { prefs.spaceAfterAccept = $0 }))
                QDivider()
                contextToggle(L.t(.generalAutoUpdate), help: L.t(.generalAutoUpdateHelp),
                              isOn: Binding(get: { prefs.autoUpdateEnabled },
                                            set: { newVal in
                                                prefs.autoUpdateEnabled = newVal
                                                if newVal { UpdateChecker.shared.start() }
                                                else { UpdateChecker.shared.stop() }
                                            }))
            }
        }
    }

    private var correctionsCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(QColors.success)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t(.generalContextAutocorrect))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Text(L.t(.generalContextAutocorrectBody))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Spacer()
                }
                QDivider()
                QToggle(isOn: Binding(
                    get: { prefs.autoCorrectEnabled },
                    set: { prefs.autoCorrectEnabled = $0 }
                ), label: L.t(.generalSuggestSpelling))
                QDivider()
                QToggle(isOn: Binding(
                    get: { prefs.autoGrammarEnabled },
                    set: { prefs.autoGrammarEnabled = $0 }
                ), label: L.t(.generalSuggestGrammar))
            }
        }
    }

    private var suggestionLengthCard: some View {
        let activeModel = ModelRegistry.entry(forTag: prefs.activeModelTag)
        let modelMax = activeModel?.maxSuggestionWords ?? 5
        let modelName = activeModel?.displayName ?? prefs.activeModelTag
        // Clamp the stored value so a model with a smaller ceiling can't show
        // a slider knob past the end of the track.
        let clamped = max(1, min(prefs.maxSuggestionWords, modelMax))

        return QCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L.t(.generalMaxWords))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Spacer()
                        Text("\(clamped) \(L.t(.generalMaxWordsValue))")
                            .font(QFonts.mono)
                            .foregroundStyle(QColors.textPrimary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(clamped) },
                            set: { prefs.maxSuggestionWords = Int($0.rounded()) }
                        ),
                        in: 1...Double(modelMax),
                        step: 1
                    )
                    .tint(QColors.accent)
                    HStack {
                        Text("1")
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                        Spacer()
                        Text("\(modelName) · \(L.t(.generalMaxWordsModelCap)) \(modelMax)")
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Text(L.t(.generalMaxWordsHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Auto-clamp on appear in case the active model changed since last
        // time and the previous value is now above the new ceiling.
        .onAppear {
            if prefs.maxSuggestionWords > modelMax || prefs.maxSuggestionWords < 1 {
                prefs.maxSuggestionWords = min(modelMax, max(1, prefs.maxSuggestionWords))
            }
        }
    }

    private var tuningCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L.t(.generalSuggestionDelay))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Spacer()
                        Text("\(prefs.suggestionDelayMs) ms")
                            .font(QFonts.mono)
                            .foregroundStyle(QColors.textSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(prefs.suggestionDelayMs) },
                            set: { prefs.suggestionDelayMs = Int($0) }
                        ),
                        in: 50...500,
                        step: 10
                    )
                    .tint(QColors.accent)
                    Text(L.t(.generalSuggestionDelayHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }

                QDivider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L.t(.generalTriggerThreshold))
                                .font(QFonts.bodyMed)
                                .foregroundStyle(QColors.textPrimary)
                            Text("\(prefs.triggerThreshold) chars")
                                .font(QFonts.mono)
                                .foregroundStyle(QColors.textSecondary)
                        }
                        Text(L.t(.generalTriggerThresholdHelp))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Spacer()
                    Stepper("Trigger threshold",
                            value: Binding(
                                get: { prefs.triggerThreshold },
                                set: { prefs.triggerThreshold = $0 }
                            ),
                            in: 2...8)
                        .labelsHidden()
                }
            }
        }
    }

    private var excludedAppsCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L.t(.generalExcludedApps))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(availableApps) { app in
                            Button(app.name) {
                                if !prefs.excludedBundleIDs.contains(app.id) {
                                    prefs.excludedBundleIDs.append(app.id)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                            Text(L.t(.generalAddApp))
                        }
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if prefs.excludedBundleIDs.isEmpty {
                    Text(L.t(.generalExcludedAppsHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(prefs.excludedBundleIDs, id: \.self) { id in
                            excludedRow(id)
                        }
                    }
                }
            }
        }
    }

    private func excludedRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed").foregroundStyle(QColors.textTertiary)
            Text(displayName(forBundle: bundleID))
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
            Text(bundleID)
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
            Button {
                prefs.excludedBundleIDs.removeAll { $0 == bundleID }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(QColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(QColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
    }

    private func displayName(forBundle id: String) -> String {
        availableApps.first(where: { $0.id == id })?.name ?? id
    }

    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? id
                return RunningApp(id: id, name: name)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        availableApps = apps
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("QalamAI: Launch at login update failed: \(error.localizedDescription)")
        }
    }
}
