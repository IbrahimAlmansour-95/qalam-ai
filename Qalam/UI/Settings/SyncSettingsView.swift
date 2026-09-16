import SwiftUI

/// Sync between the user's Macs through an encrypted file in iCloud Drive.
/// Off until the user turns it on and chooses a passphrase; QalamAI does not
/// look inside iCloud Drive before then.
struct SyncSettingsView: View {
    @State private var prefs = UserPreferences.shared
    @State private var manager = SyncManager.shared

    @State private var cloudAvailable = true
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var validationError: LocalizationKey?
    @State private var busy = false
    @State private var showTurnOffConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                if !cloudAvailable { unavailableCard }
                if prefs.syncEnabled {
                    // Shown even when iCloud Drive has gone away, so there
                    // is always a way to turn sync back off.
                    statusCard
                    if case .error(.wrongPassphrase) = manager.status {
                        passphraseCard(reentry: true)
                    }
                    samplesCard
                } else if cloudAvailable {
                    passphraseCard(reentry: false)
                }
                whatSyncsCard
                encryptionCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Lazily — this is the first moment we are allowed to look at
        // ~/Library/Mobile Documents.
        .onAppear { cloudAvailable = SyncManager.cloudDriveAvailable() }
        .alert(L.t(.syncTurnOffTitle), isPresented: $showTurnOffConfirm) {
            Button(L.t(.commonCancel), role: .cancel) { }
            Button(L.t(.syncTurnOffKeep)) { manager.disable(removeCloudCopy: false) }
            Button(L.t(.syncTurnOffRemove), role: .destructive) {
                manager.disable(removeCloudCopy: true)
            }
        } message: {
            Text(L.t(.syncTurnOffMessage))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.syncHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.syncSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unavailableCard: some View {
        QCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(QColors.warning)
                Text(L.t(.syncUnavailable))
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Turning it on

    private func passphraseCard(reentry: Bool) -> some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t(reentry ? .syncReenterTitle : .syncTurnOnTitle))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Text(L.t(reentry ? .syncReenterHelp : .syncPassphraseHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                secureField(L.t(.syncPassphrase), text: $passphrase)
                if !reentry {
                    secureField(L.t(.syncPassphraseConfirm), text: $confirmation)
                }

                if let validationError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(QColors.warning)
                        Text(L.t(validationError))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                HStack {
                    QButton(title: L.t(reentry ? .syncSavePassphrase : .syncTurnOn),
                            icon: "icloud.and.arrow.up",
                            size: .small,
                            disabled: busy || passphrase.isEmpty) {
                        submit(reentry: reentry)
                    }
                    Spacer()
                }
            }
        }
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(QFonts.body)
            .foregroundStyle(QColors.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(QColors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                    .strokeBorder(QColors.borderMedium, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
    }

    private func submit(reentry: Bool) {
        let pass = passphrase
        guard pass.count >= SyncManager.minPassphraseLength else {
            validationError = .syncPassphraseTooShort
            return
        }
        if !reentry, pass != confirmation {
            validationError = .syncPassphraseMismatch
            return
        }
        validationError = nil
        busy = true
        Task {
            let failure = await manager.enable(passphrase: pass)
            busy = false
            if let failure {
                validationError = Self.errorKey(failure)
            } else {
                passphrase = ""
                confirmation = ""
            }
        }
    }

    // MARK: - Running

    private var statusCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t(.syncStatus))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    Text(statusText)
                        .font(QFonts.caption)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t(.syncLastSync))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                    Spacer()
                    Text(lastSyncText)
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
                QDivider()
                HStack(spacing: 8) {
                    QButton(title: L.t(.syncNow), icon: "arrow.triangle.2.circlepath",
                            style: .secondary, size: .small, disabled: busy) {
                        busy = true
                        Task {
                            await manager.syncNow()
                            busy = false
                        }
                    }
                    Spacer()
                    QButton(title: L.t(.syncTurnOff), style: .destructive, size: .small) {
                        showTurnOffConfirm = true
                    }
                }
            }
        }
    }

    private var samplesCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 10) {
                QToggle(isOn: Binding(get: { prefs.syncIncludePersonalization },
                                      set: { prefs.syncIncludePersonalization = $0 }),
                        label: L.t(.syncIncludeSamples))
                Text(L.t(.syncIncludeSamplesHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Explanations

    private var whatSyncsCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t(.syncWhatSyncs))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                ForEach([LocalizationKey.syncItemSnippets, .syncItemModes, .syncItemApps,
                         .syncItemInstructions, .syncItemMyInfo], id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(QColors.success)
                        Text(L.t(key))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                QDivider()
                Text(L.t(.syncNeverNote))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var encryptionCard: some View {
        QCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(QColors.success)
                Text(L.t(.syncEncryptionNote))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Status text

    private var statusText: String {
        switch manager.status {
        case .off:                return L.t(.syncStatusOff)
        case .unavailable:        return L.t(.syncUnavailable)
        case .idle:               return L.t(.syncStatusIdle)
        case .syncing:            return L.t(.syncStatusSyncing)
        case .waitingForDownload: return L.t(.syncStatusWaiting)
        case .error(let kind):    return L.t(Self.errorKey(kind))
        }
    }

    private var statusColor: Color {
        switch manager.status {
        case .idle:                        return QColors.success
        case .error:                       return QColors.warning
        case .off, .unavailable:           return QColors.textTertiary
        case .syncing, .waitingForDownload: return QColors.textSecondary
        }
    }

    private var lastSyncText: String {
        guard let date = manager.lastSyncAt else { return L.t(.syncNever) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func errorKey(_ kind: SyncErrorKind) -> LocalizationKey {
        switch kind {
        case .wrongPassphrase:     return .syncErrorWrongPassphrase
        case .keychainUnavailable: return .syncErrorKeychain
        case .io:                  return .syncErrorIO
        case .badFormat:           return .syncErrorFormat
        }
    }
}
