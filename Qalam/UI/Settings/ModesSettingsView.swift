import SwiftUI

struct ModesSettingsView: View {
    @State private var prefs = UserPreferences.shared
    @State private var store = WritingModeStore.shared
    @State private var showAddSheet = false
    @State private var draftName: String = ""
    @State private var draftInstruction: String = ""
    @State private var draftTemperature: Double = 0.3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                builtInGrid
                customCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.t(.modesHeading))
                    .font(QFonts.display)
                    .foregroundStyle(QColors.textPrimary)
                Spacer()
                QTag(text: "Active: \(activeMode.name)",
                     style: .accent,
                     showDot: true,
                     icon: activeMode.iconSymbol)
            }
            Text("Tell \(Constants.appName) how to sound. Modes change the prompt and sampling temperature.")
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var activeMode: WritingMode {
        store.mode(id: prefs.activeModeID)
    }

    // MARK: - Built-in grid

    private var builtInGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t(.modesBuiltIn))
                .font(QFonts.caption)
                .fontWeight(.semibold)
                .foregroundStyle(QColors.textTertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(WritingMode.builtIns) { mode in
                    modeTile(mode)
                }
            }
        }
    }

    private func modeTile(_ mode: WritingMode) -> some View {
        let isActive = prefs.activeModeID == mode.id
        return Button {
            prefs.activeModeID = mode.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mode.iconSymbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isActive ? QColors.accent : QColors.textSecondary)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(QColors.accent)
                            .font(.system(size: 14))
                    }
                }
                Text(mode.name)
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Text(mode.instruction)
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                QTag(text: String(format: "Temp %.2f", mode.temperature), style: .neutral)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(isActive ? QColors.backgroundElevated : QColors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                    .strokeBorder(isActive ? QColors.accent : QColors.borderSubtle,
                                  lineWidth: isActive ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom modes

    private var customCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t(.modesCustom))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Text(L.t(.modesCustomHelp))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Spacer()
                    QButton(title: L.t(.modesNewMode), icon: "plus", style: .secondary, size: .small) {
                        draftName = ""
                        draftInstruction = ""
                        draftTemperature = 0.3
                        showAddSheet = true
                    }
                }

                if store.customModes.isEmpty {
                    Text(L.t(.modesNoCustom))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.customModes) { mode in
                            customRow(mode)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { addSheet }
    }

    private func customRow(_ mode: WritingMode) -> some View {
        let isActive = prefs.activeModeID == mode.id
        return HStack(spacing: 10) {
            Image(systemName: mode.iconSymbol).foregroundStyle(QColors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name).font(QFonts.body).foregroundStyle(QColors.textPrimary)
                Text(mode.instruction).font(QFonts.caption).foregroundStyle(QColors.textTertiary).lineLimit(1)
            }
            Spacer()
            if isActive {
                QTag(text: "Active", style: .success, showDot: true)
            }
            QButton(title: isActive ? "Selected" : "Use", style: .ghost, size: .small, disabled: isActive) {
                prefs.activeModeID = mode.id
            }
            Button {
                store.delete(mode)
                if isActive { prefs.activeModeID = WritingMode.neutral.id }
            } label: {
                Image(systemName: "trash").foregroundStyle(QColors.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(QColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t(.modesNewModeTitle))
                .font(QFonts.title)
                .foregroundStyle(QColors.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(.modesName)).font(QFonts.caption).foregroundStyle(QColors.textTertiary)
                QTextField(placeholder: "e.g. Translate to French", text: $draftName)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(.modesInstruction)).font(QFonts.caption).foregroundStyle(QColors.textTertiary)
                TextEditor(text: $draftInstruction)
                    .font(QFonts.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 90)
                    .background(QColors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: QRadius.medium)
                            .strokeBorder(QColors.borderMedium, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.medium))
            }
            HStack {
                Text(L.t(.modesTemperature)).font(QFonts.caption).foregroundStyle(QColors.textTertiary)
                Slider(value: $draftTemperature, in: 0...1, step: 0.05)
                    .tint(QColors.accent)
                Text(String(format: "%.2f", draftTemperature))
                    .font(QFonts.mono)
                    .foregroundStyle(QColors.textPrimary)
                    .frame(width: 40, alignment: .trailing)
            }

            HStack {
                Spacer()
                QButton(title: L.t(.commonCancel), style: .ghost, size: .medium) { showAddSheet = false }
                QButton(title: L.t(.commonCreate), style: .primary, size: .medium,
                        disabled: draftName.trimmingCharacters(in: .whitespaces).isEmpty
                               || draftInstruction.trimmingCharacters(in: .whitespaces).isEmpty) {
                    store.add(name: draftName.trimmingCharacters(in: .whitespaces),
                              instruction: draftInstruction.trimmingCharacters(in: .whitespaces),
                              temperature: draftTemperature)
                    showAddSheet = false
                }
            }
        }
        .padding(QSpacing.xl)
        .frame(width: 460)
        .background(QColors.backgroundPrimary)
    }
}
