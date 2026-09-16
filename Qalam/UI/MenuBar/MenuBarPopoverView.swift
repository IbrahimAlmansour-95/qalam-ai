import SwiftUI

struct MenuBarPopoverView: View {
    @State private var prefs = UserPreferences.shared
    @State private var modelManager = ModelManager.shared
    @State private var axMonitor = AccessibilityPermissionMonitor.shared
    @State private var updater = UpdateChecker.shared
    @State private var l10n = LocalizationStore.shared
    @State private var secureInput = SecureInputMonitor.shared
    @State private var profiles = ProfileStore.shared
    @State private var pauses = TemporaryPauseStore.shared
    /// Ticks with the refresh timer so "N min left" counts down.
    @State private var now = Date()
    @State private var statsSnapshot = UsageLogger.Snapshot(
        wordsCompletedToday: 0, keystrokesSaved: 0, suggestionsShown: 0
    )
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            QVisualEffect(material: .popover)
            VStack(alignment: .leading, spacing: 0) {
                header
                QDivider().padding(.horizontal, 0)
                if let release = updater.available {
                    updateBanner(release)
                    QDivider().padding(.horizontal, 0)
                }
                if !axMonitor.isGranted {
                    accessibilityWarning
                    QDivider().padding(.horizontal, 0)
                }
                if secureInput.isActive {
                    secureInputBanner
                    QDivider().padding(.horizontal, 0)
                }
                if engineFailed {
                    engineFailedRow
                    QDivider().padding(.horizontal, 0)
                }
                enableRow
                QDivider().padding(.horizontal, 0)
                if let app = profiles.lastExternalApp {
                    appQuickSection(app)
                    QDivider().padding(.horizontal, 0)
                }
                snoozeSection
                QDivider().padding(.horizontal, 0)
                modeSwitcherSection
                QDivider().padding(.horizontal, 0)
                activeModelSection
                QDivider().padding(.horizontal, 0)
                statsSection
                Spacer(minLength: 0)
                QDivider().padding(.horizontal, 0)
                footer
            }
        }
        // Width is fixed; the height follows the content (the popover uses
        // `.preferredContentSize`), with a floor so the layout never collapses
        // if a section reports no ideal height.
        .frame(width: 320)
        .frame(minHeight: 420, alignment: .top)
        .background(QColors.backgroundPrimary)
        .environment(\.layoutDirection, l10n.current.layoutDirection)
        .onAppear { startRefresh() }
        .onDisappear { stopRefresh() }
    }

    private func updateBanner(_ release: UpdateChecker.Release) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(QColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(L.t(.updateAvailable))
                    .font(QFonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(QColors.textPrimary)
                Text("v\(release.version)")
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
            }
            Spacer()
            switch updater.installState {
            case .downloading(let frac):
                Text("\(Int(frac * 100))%")
                    .font(QFonts.caption).foregroundStyle(QColors.textSecondary)
            case .mounting:
                ProgressView().scaleEffect(0.5)
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(QColors.success)
            case .idle, .failed:
                QButton(title: L.t(.updateInstall), style: .primary, size: .small) {
                    Task { await UpdateChecker.shared.downloadAndInstall() }
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, 8)
        .background(QColors.accent.opacity(0.08))
    }

    private var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(QColors.warning)
                Text(L.t(.popoverAccessibilityRequired))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
            }
            Text(L.t(.popoverAccessibilityBody))
                .font(QFonts.caption)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QButton(title: L.t(.popoverOpenAccessibility), icon: "arrow.up.right.square",
                    style: .primary, size: .small, fullWidth: true) {
                AccessibilityPermissionMonitor.shared.openSystemSettings()
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
        .background(QColors.warning.opacity(0.06))
    }

    /// While Secure Input is on the keystroke tap sees no keys, so nothing can
    /// be suggested — say so instead of looking broken. Kept compact: the
    /// popover has a fixed height.
    private var secureInputBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(QColors.warning)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(.popoverSecureInputPaused))
                    .font(QFonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(QColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.t(.popoverSecureInputHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.s)
        .background(QColors.warning.opacity(0.06))
    }

    /// The bundled engine crashed repeatedly and auto-restart gave up. Only
    /// shown while it really is down.
    private var engineFailed: Bool {
        modelManager.engineSupervisor == .failed && modelManager.ollamaState != .running
    }

    private var engineRestarting: Bool {
        if case .restarting = modelManager.engineSupervisor {
            return modelManager.ollamaState != .running
        }
        return false
    }

    private var engineFailedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(QColors.destructive)
            Text(L.t(.popoverEngineFailedHelp))
                .font(QFonts.caption)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            QButton(title: L.t(.popoverEngineRetry), icon: "arrow.clockwise",
                    style: .primary, size: .small) {
                Task { await OllamaService.shared.retryAfterFailure() }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.s)
        .background(QColors.destructive.opacity(0.06))
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            QalamLogo(size: 18, tint: QColors.accent)
            Text(Constants.appName)
                .font(QFonts.bodyMed)
                .foregroundStyle(QColors.textPrimary)
            Spacer()
            QTag(text: statusText, style: statusStyle, showDot: true)
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    /// The frontmost app is paused for a while (⌘⇧Space on an app, or the
    /// field button's "Pause 10 min").
    private var frontmostAppPaused: Bool {
        guard let app = profiles.lastExternalApp else { return false }
        if let until = pauses.until(bundleID: app.bundleID) { return until > now }
        return false
    }

    /// The frontmost app (or the site open in it) is switched off in its
    /// profile.
    private var frontmostAppOff: Bool {
        guard let app = profiles.lastExternalApp else { return false }
        let host = KnownApps.isBrowser(app.bundleID) ? profiles.lastExternalHost : nil
        return profiles.resolve(bundleID: app.bundleID, host: host).activation == .off
    }

    /// One tag for the whole app state, in the order the user would fix them.
    /// Kept to a couple of words so a long app name can never clip the header:
    /// which app is paused or off is spelled out in `appQuickSection` below.
    private var statusText: String {
        if !axMonitor.isGranted { return L.t(.popoverStatusNeedsAccess) }
        if secureInput.isActive { return L.t(.popoverStatusPaused) }
        if engineFailed { return L.t(.popoverStatusEngineFailed) }
        if engineRestarting { return L.t(.popoverStatusRestarting) }
        if !prefs.isEnabled { return L.t(.popoverStatusPaused) }
        if prefs.isSnoozed { return L.t(.popoverStatusSnoozed) }
        if frontmostAppPaused { return L.t(.popoverStatusPaused) }
        if frontmostAppOff { return L.t(.appsOff) }
        switch modelManager.ollamaState {
        case .running:     return L.t(.popoverStatusActive)
        case .starting:    return L.t(.popoverStatusStarting)
        case .stopped:     return L.t(.popoverStatusStopped)
        case .notInstalled: return L.t(.popoverStatusInstallOllama)
        case .unknown:     return L.t(.popoverStatusChecking)
        }
    }

    private var statusStyle: QTagStyle {
        if !axMonitor.isGranted { return .destructive }
        if secureInput.isActive { return .warning }
        if engineFailed { return .destructive }
        if engineRestarting { return .warning }
        if !prefs.isEnabled || prefs.isSnoozed { return .warning }
        if frontmostAppPaused || frontmostAppOff { return .warning }
        switch modelManager.ollamaState {
        case .running:      return .success
        case .starting:     return .warning
        case .stopped, .notInstalled: return .destructive
        case .unknown:      return .neutral
        }
    }

    private var enableRow: some View {
        HStack {
            QToggle(isOn: Binding(
                get: { prefs.isEnabled },
                set: { prefs.isEnabled = $0 }
            ), label: L.t(.popoverEnableSuggestions))
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    /// Quick per-app (and per-site, in a browser) switch for the app the
    /// user was just in. Off ↔ inherit on that app's / site's profile; the
    /// rest of the settings live in the Apps tab.
    private func appQuickSection(_ app: ExternalAppRef) -> some View {
        let appProfile = profiles.appProfile(bundleID: app.bundleID)
        let appOff = appProfile?.activation == .off
        let host = KnownApps.isBrowser(app.bundleID) ? profiles.lastExternalHost : nil
        let pausedUntil = pauses.until(bundleID: app.bundleID)
        return VStack(alignment: .leading, spacing: 8) {
            QToggle(isOn: Binding(
                get: { !appOff },
                set: { on in
                    let id = ProfileStore.shared.ensureApp(bundleID: app.bundleID, name: app.name).id
                    ProfileStore.shared.update(id: id) { p in
                        if on {
                            if p.activation == .off { p.activation = nil }
                        } else {
                            p.activation = .off
                        }
                    }
                }
            ), label: String(format: L.t(.popoverSuggestInAppFmt), app.name))
            // A site switch only makes sense while the browser itself is on.
            if let host, !appOff {
                let siteOff = profiles.resolve(bundleID: app.bundleID, host: host).activation == .off
                QToggle(isOn: Binding(
                    get: { !siteOff },
                    set: { on in
                        let store = ProfileStore.shared
                        let id = store.ensureDomain(host: host).id
                        if on {
                            store.update(id: id) { p in
                                if p.activation == .off { p.activation = nil }
                            }
                            // Still off because a parent domain is: turn it on
                            // for this host only, leaving the parent's other
                            // subdomains alone.
                            if store.resolve(bundleID: app.bundleID, host: host).activation == .off {
                                store.update(id: id) { $0.activation = .alwaysOn }
                            }
                        } else {
                            store.update(id: id) { $0.activation = .off }
                        }
                    }
                ), label: String(format: L.t(.popoverSuggestOnSiteFmt), host))
            }
            if let until = pausedUntil, until > now {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(QColors.warning)
                    Text(String(format: L.t(.popoverAppPausedFmt), app.name,
                                max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        TemporaryPauseStore.shared.resume(bundleID: app.bundleID)
                    } label: {
                        Text(L.t(.popoverSnoozeResume))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.s)
    }

    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: prefs.isSnoozed ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 11))
                    .foregroundStyle(prefs.isSnoozed ? QColors.warning : QColors.textTertiary)
                Text(L.t(.popoverSnooze))
                    .font(QFonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(QColors.textTertiary)
                Spacer()
                if prefs.isSnoozed {
                    Button {
                        prefs.snoozeUntil = nil
                    } label: {
                        Text(L.t(.popoverSnoozeResume))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if prefs.isSnoozed, let until = prefs.snoozeUntil {
                Text(snoozeRemainingText(until: until))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
            } else {
                HStack(spacing: 6) {
                    snoozeChip(L.t(.popoverSnooze30m), minutes: 30)
                    snoozeChip(L.t(.popoverSnooze1h), minutes: 60)
                    snoozeChip(L.t(.popoverSnoozeTomorrow), minutes: nil)
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    private func snoozeChip(_ title: String, minutes: Int?) -> some View {
        Button {
            if let m = minutes {
                prefs.snoozeUntil = Date().addingTimeInterval(TimeInterval(m * 60))
            } else {
                // Until 8am tomorrow.
                var cal = Calendar.current
                cal.timeZone = .current
                let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                prefs.snoozeUntil = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
            }
        } label: {
            Text(title)
                .font(QFonts.caption)
                .fontWeight(.medium)
                .foregroundStyle(QColors.textSecondary)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(QColors.fillSubtle)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func snoozeRemainingText(until: Date) -> String {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return L.t(.popoverSnoozedUntil) + " " + df.string(from: until)
    }

    private var modeSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(.popoverWritingMode))
                .font(QFonts.caption)
                .fontWeight(.semibold)
                .foregroundStyle(QColors.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WritingMode.builtIns) { mode in
                        modeChip(mode)
                    }
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    private func modeChip(_ mode: WritingMode) -> some View {
        let isActive = prefs.activeModeID == mode.id
        return Button {
            prefs.activeModeID = mode.id
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.iconSymbol).font(.system(size: 10, weight: .semibold))
                Text(mode.name).font(QFonts.caption).fontWeight(.medium)
            }
            .foregroundStyle(isActive ? .white : QColors.textSecondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(isActive ? QColors.accent : QColors.fillSubtle)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var activeModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(.popoverActiveModel))
                .font(QFonts.caption)
                .fontWeight(.semibold)
                .foregroundStyle(QColors.textTertiary)

            let entry = ModelRegistry.entry(forTag: prefs.activeModelTag)
            let displayName = entry?.displayName ?? prefs.activeModelTag

            QCard(padding: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(modelManager.ollamaState == .running
                                      ? QColors.success : QColors.warning)
                                .frame(width: 6, height: 6)
                            Text(runStatusLine(entry: entry))
                                .font(QFonts.caption)
                                .foregroundStyle(QColors.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        AppState.shared.showSettings()
                    } label: {
                        HStack(spacing: 3) {
                            Text(L.t(.popoverChange))
                                .font(QFonts.caption)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(QColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    private func runStatusLine(entry: ModelEntry?) -> String {
        let state = modelManager.ollamaState
        let sizeText = entry.map { String(format: "%.1f GB", $0.sizeGB) } ?? ""
        switch state {
        case .running: return sizeText.isEmpty ? "Running" : "Running · \(sizeText)"
        case .starting: return "Starting…"
        case .stopped: return "Ollama not running"
        case .notInstalled: return "Ollama not installed"
        case .unknown: return "Checking…"
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(.popoverTodaysStats))
                .font(QFonts.caption)
                .fontWeight(.semibold)
                .foregroundStyle(QColors.textTertiary)
            statRow(label: L.t(.popoverWordsCompleted),   value: "\(statsSnapshot.wordsCompletedToday)")
            statRow(label: L.t(.popoverKeystrokesSaved),  value: "\(statsSnapshot.keystrokesSaved)")
            statRow(label: L.t(.popoverSuggestionsShown), value: "\(statsSnapshot.suggestionsShown)")
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.m)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(QFonts.body).foregroundStyle(QColors.textSecondary)
            Spacer()
            Text(value).font(QFonts.bodyMed).foregroundStyle(QColors.textPrimary)
        }
    }

    private var footer: some View {
        HStack(spacing: QSpacing.s) {
            QButton(title: L.t(.popoverSettings), icon: "gearshape", style: .ghost, size: .medium) {
                AppState.shared.showSettings()
            }
            Spacer()
            QButton(title: L.t(.popoverQuit), style: .ghost, size: .medium) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, QSpacing.m)
        .padding(.vertical, QSpacing.m)
    }

    // MARK: - Refresh

    private func startRefresh() {
        Task {
            self.statsSnapshot = await UsageLogger.shared.snapshot()
        }
        now = Date()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.statsSnapshot = await UsageLogger.shared.snapshot()
                self.now = Date()
            }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
