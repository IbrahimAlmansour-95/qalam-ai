import SwiftUI

struct SnippetsSettingsView: View {
    @State private var store = SnippetStore.shared
    @State private var draftTrigger: String = ""
    @State private var draftExpansion: String = ""
    @State private var editingID: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                howCard
                addCard
                listCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snippets")
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text("Short triggers that expand into longer text. Type ':trigger' anywhere and press Tab.")
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var howCard: some View {
        QCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(QColors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("How it works")
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Text("Type ':sig' in any text field — \(Constants.appName) shows the expansion as a ghost suggestion. Press Tab to accept.")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var addCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("New snippet")
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                HStack {
                    Text(":")
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.textTertiary)
                    QTextField(placeholder: "trigger (e.g. addr)", text: $draftTrigger)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expansion")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                    TextEditor(text: $draftExpansion)
                        .font(QFonts.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 80)
                        .background(QColors.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: QRadius.medium)
                                .strokeBorder(QColors.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium))
                }
                HStack {
                    Spacer()
                    QButton(title: "Add Snippet", icon: "plus.circle.fill",
                            style: .primary, size: .medium,
                            disabled: draftTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                                   || draftExpansion.trimmingCharacters(in: .whitespaces).isEmpty) {
                        store.add(trigger: draftTrigger, expansion: draftExpansion)
                        draftTrigger = ""
                        draftExpansion = ""
                    }
                }
            }
        }
    }

    private var listCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your snippets")
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                if store.snippets.isEmpty {
                    Text("No snippets yet.")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.snippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                }
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(":")
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.textTertiary)
                    Text(snippet.trigger)
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.accent)
                }
                Text(snippet.expansion)
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                store.delete(snippet)
            } label: {
                Image(systemName: "trash").foregroundStyle(QColors.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(QColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
    }
}
