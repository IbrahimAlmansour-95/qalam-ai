import SwiftUI

struct MenuBarPopoverView: View {
    @State private var prefs = UserPreferences.shared
    @State private var modelManager = ModelManager.shared
    @State private var axMonitor = AccessibilityPermissionMonitor.shared
    @State private var updater = UpdateChecker.shared
    @State private var l10n = LocalizationStore.shared
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
                enableRow
                QDivider().padding(.horizontal, 0)
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
        .frame(width: 320)
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

    private var statusText: String {
        if !axMonitor.isGranted { return L.t(.popoverStatusNeedsAccess) }
        switch modelManager.ollamaState {
        case .running:     return L.t(prefs.isEnabled ? .popoverStatusActive : .popoverStatusPaused)
        case .starting:    return L.t(.popoverStatusStarting)
        case .stopped:     return L.t(.popoverStatusStopped)
        case .notInstalled: return L.t(.popoverStatusInstallOllama)
        case .unknown:     return L.t(.popoverStatusChecking)
        }
    }

    private var statusStyle: QTagStyle {
        if !axMonitor.isGranted { return .destructive }
        switch modelManager.ollamaState {
        case .running:      return prefs.isEnabled ? .success : .warning
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.statsSnapshot = await UsageLogger.shared.snapshot()
            }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
