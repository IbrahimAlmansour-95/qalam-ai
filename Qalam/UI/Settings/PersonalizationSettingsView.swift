import SwiftUI
import AppKit

/// Personalization: the encrypted local store of the user's own writing and
/// how much of it is fed back into suggestions. Everything here is off until
/// the user switches it on.
struct PersonalizationSettingsView: View {
    @State private var prefs = UserPreferences.shared
    @State private var counts: [String: Int] = [:]
    @State private var isUnavailable = false
    @State private var hasStoredData = false
    @State private var showDeleteAllConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                recordCard
                strengthCard
                samplesCard
                privacyCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await refresh() }
        .alert(L.t(.personaDeleteAllTitle), isPresented: $showDeleteAllConfirm) {
            Button(L.t(.commonCancel), role: .cancel) { }
            Button(L.t(.personaDeleteAll), role: .destructive) {
                Task {
                    await PersonalizationStore.shared.deleteAll()
                    await refresh()
                }
            }
        } message: {
            Text(L.t(.personaDeleteAllConfirm))
        }
    }

    private func refresh() async {
        counts = await PersonalizationStore.shared.counts()
        // Deliberately does NOT open the store: reading the key here would
        // create one just because the tab was opened.
        hasStoredData = await PersonalizationStore.shared.hasStoredData()
        isUnavailable = PersonalizationSnapshot.shared.isUnavailable
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.personaHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.personaSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recording

    private var recordCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                QToggle(isOn: Binding(get: { prefs.recordWritingEnabled },
                                      set: { newValue in
                                          prefs.recordWritingEnabled = newValue
                                          Task { await refresh() }
                                      }),
                        label: L.t(.personaRecord))
                Text(L.t(.personaRecordHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if prefs.recordWritingEnabled {
                    QDivider()
                    Text(L.t(.personaMode))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    VStack(spacing: 0) {
                        modeSegment(L.t(.personaModeAccepted), value: .acceptedOnly)
                        modeSegment(L.t(.personaModeEverything), value: .everything)
                    }
                    .padding(2)
                    .background(QColors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous)
                            .strokeBorder(QColors.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous))
                    Text(L.t(.personaModeHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Stacked (not side by side): both labels are long sentences.
    private func modeSegment(_ title: String, value: RecordWritingMode) -> some View {
        let active = prefs.recordWritingMode == value
        return Button {
            withAnimation(QAnimation.quick) { prefs.recordWritingMode = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(QFonts.caption)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? .white : QColors.textSecondary)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? QColors.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Strength

    private var strengthCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t(.personaStrength))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                HStack(spacing: 0) {
                    strengthSegment(L.t(.personaStrengthOff), value: .off)
                    strengthSegment(L.t(.personaStrengthLow), value: .low)
                    strengthSegment(L.t(.personaStrengthMedium), value: .medium)
                    strengthSegment(L.t(.personaStrengthStrong), value: .strong)
                }
                .padding(2)
                .background(QColors.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous)
                        .strokeBorder(QColors.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: QRadius.small + 1, style: .continuous))
                Text(L.t(.personaStrengthHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func strengthSegment(_ title: String, value: PersonalizationStrength) -> some View {
        let active = prefs.personalizationStrength == value
        return Button {
            withAnimation(QAnimation.quick) { prefs.personalizationStrength = value }
        } label: {
            Text(title)
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

    // MARK: - Saved samples

    private var sortedCounts: [(bundleID: String, count: Int)] {
        counts.map { (bundleID: $0.key, count: $0.value) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.bundleID < b.bundleID
            }
    }

    private var samplesCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t(.personaSamples))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    Text(String(format: L.t(.personaSampleCountFmt),
                                counts.values.reduce(0, +)))
                        .font(QFonts.caption.monospacedDigit())
                        .foregroundStyle(QColors.textTertiary)
                }
                Text(L.t(.personaSamplesHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if isUnavailable {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(QColors.warning)
                        Text(L.t(.personaUnavailable))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }

                QDivider()
                if sortedCounts.isEmpty {
                    Text(L.t(.personaSamplesEmpty))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                } else {
                    ForEach(sortedCounts, id: \.bundleID) { entry in
                        sampleRow(bundleID: entry.bundleID, count: entry.count)
                    }
                }

                QDivider()
                HStack {
                    QButton(title: L.t(.personaDeleteAll), icon: "trash",
                            style: .destructive, size: .small,
                            disabled: !hasStoredData) {
                        showDeleteAllConfirm = true
                    }
                    Spacer()
                }
            }
        }
    }

    private func sampleRow(bundleID: String, count: Int) -> some View {
        HStack(spacing: 10) {
            if let icon = AppIconCache.shared.icon(bundleID: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(QColors.textTertiary)
                    .frame(width: 18, height: 18)
            }
            Text(ProfileStore.appDisplayName(bundleID: bundleID) ?? bundleID)
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(String(format: L.t(.personaSampleCountFmt), count))
                .font(QFonts.caption.monospacedDigit())
                .foregroundStyle(QColors.textTertiary)
            QButton(title: L.t(.personaDelete), style: .ghost, size: .small) {
                Task {
                    await PersonalizationStore.shared.delete(bundleID: bundleID)
                    await refresh()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var privacyCard: some View {
        QCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(QColors.success)
                Text(L.t(.personaPrivacy))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }
}
