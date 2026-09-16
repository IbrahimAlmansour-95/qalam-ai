import SwiftUI

struct MyInfoSettingsView: View {
    @State private var store = PersonalInfoStore.shared
    @State private var prefs = UserPreferences.shared
    /// Edited locally and capped here: a TextEditor bound straight to a
    /// capped preference keeps showing the characters past the cap.
    @State private var instructionsDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                instructionsCard
                infoCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { instructionsDraft = prefs.customInstructions }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.myInfoHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.myInfoSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var instructionsCard: some View {
        let limit = ProfileStore.globalInstructionsLimit
        return QCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t(.myInfoInstructionsTitle))
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    Text("\(instructionsDraft.count) / \(limit)")
                        .font(QFonts.caption.monospacedDigit())
                        .foregroundStyle(instructionsDraft.count >= limit ? QColors.warning : QColors.textTertiary)
                }
                Text(L.t(.myInfoInstructionsHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                InstructionsEditor(text: $instructionsDraft,
                                   placeholder: L.t(.myInfoInstructionsPlaceholder))
                    .onChange(of: instructionsDraft) { _, newValue in
                        if newValue.count > limit {
                            instructionsDraft = String(newValue.prefix(limit))
                            return
                        }
                        if prefs.customInstructions != newValue {
                            prefs.customInstructions = newValue
                        }
                    }
            }
        }
    }

    private var infoCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(QColors.success)
                    Text(L.t(.myInfoPrivacy))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                QDivider()
                ForEach(store.items) { item in
                    fieldRow(item)
                }
                QButton(title: L.t(.myInfoAddField), icon: "plus",
                        style: .secondary, size: .small) {
                    store.add()
                }
            }
        }
    }

    private func fieldRow(_ item: PersonalInfoItem) -> some View {
        HStack(spacing: 8) {
            QTextField(placeholder: L.t(.myInfoLabelPlaceholder),
                       text: Binding(
                        get: { item.label },
                        set: { var m = item; m.label = $0; store.update(m) }))
                .frame(width: 150)
            QTextField(placeholder: L.t(.myInfoValuePlaceholder),
                       text: Binding(
                        get: { item.value },
                        set: { var m = item; m.value = $0; store.update(m) }))
            Button {
                store.delete(item)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(QColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Multi-line instruction field styled like `QTextField`, with a placeholder
/// (TextEditor has none). Shared by My Info and the Apps tab.
struct InstructionsEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textTertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(QColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(QColors.borderMedium, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
    }
}
