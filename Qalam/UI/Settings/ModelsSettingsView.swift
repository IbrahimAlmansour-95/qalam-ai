import SwiftUI

enum ModelsScope: String, CaseIterable, Hashable {
    case all, installed

    var label: String {
        switch self {
        case .all:       return "All Models"
        case .installed: return "Installed"
        }
    }
}

struct ModelsSettingsView: View {
    @State private var prefs = UserPreferences.shared
    @State private var modelManager = ModelManager.shared
    @State private var searchText: String = ""
    @State private var familyFilter: ModelFamily? = nil
    @State private var scope: ModelsScope = .all
    @State private var selectedTag: String? = nil
    @State private var confirmDeleteTag: String? = nil

    private func isInstalled(_ entry: ModelEntry) -> Bool {
        modelManager.installedTags.contains(entry.ollamaTag) ||
        modelManager.installedTags.contains(entry.ollamaTag + ":latest")
    }

    private var installedCount: Int {
        ModelRegistry.all.reduce(0) { $0 + (isInstalled($1) ? 1 : 0) }
    }

    private var filteredModels: [ModelEntry] {
        var list = ModelRegistry.entries(family: familyFilter)
        if !searchText.isEmpty {
            list = list.filter { entry in
                entry.displayName.lowercased().contains(searchText.lowercased()) ||
                entry.familyName.lowercased().contains(searchText.lowercased()) ||
                entry.publisher.lowercased().contains(searchText.lowercased())
            }
        }
        if scope == .installed {
            list = list.filter(isInstalled)
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            QDivider(orientation: .vertical)
            detail
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            scopePicker
                .padding(.top, QSpacing.m)
            QTextField(placeholder: "Search models", text: $searchText, icon: "magnifyingglass")

            filterChips

            if filteredModels.isEmpty {
                emptySidebar
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredModels) { entry in
                            QModelCard(
                                entry: entry,
                                status: modelManager.status(for: entry, activeTag: prefs.activeModelTag),
                                isSelected: selectedTag == entry.ollamaTag
                            ) {
                                selectedTag = entry.ollamaTag
                            }
                        }
                    }
                    .padding(.bottom, QSpacing.l)
                }
            }
        }
        .padding(.horizontal, QSpacing.m)
        .frame(width: 220)
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(ModelsScope.allCases, id: \.self) { s in
                Button {
                    withAnimation(QAnimation.quick) { scope = s }
                } label: {
                    HStack(spacing: 4) {
                        Text(s.label)
                            .font(QFonts.caption)
                            .fontWeight(.medium)
                        if s == .installed, installedCount > 0 {
                            Text("\(installedCount)")
                                .font(QFonts.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(scope == s ? Color.white.opacity(0.25) : QColors.accent.opacity(0.25))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(scope == s ? .white : QColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(scope == s ? QColors.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
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

    private var emptySidebar: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 24)
            Image(systemName: scope == .installed ? "tray" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(QColors.textTertiary)
            Text(scope == .installed ? "No models installed yet"
                                     : "No models match your search")
                .font(QFonts.caption)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
            if scope == .installed {
                QButton(title: "Browse all", style: .ghost, size: .small) {
                    scope = .all
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                familyChip(nil, label: "All")
                ForEach(ModelFamily.allCases, id: \.self) { family in
                    familyChip(family, label: family.rawValue)
                }
            }
        }
    }

    private func familyChip(_ family: ModelFamily?, label: String) -> some View {
        let active = familyFilter == family
        return Button {
            familyFilter = family
        } label: {
            Text(label)
                .font(QFonts.caption)
                .fontWeight(.medium)
                .foregroundStyle(active ? .white : QColors.textSecondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 9)
                .background(active ? QColors.accent : Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let tag = selectedTag, let entry = ModelRegistry.entry(forTag: tag) {
            modelDetail(entry)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(QColors.textTertiary)
            Text("Select a model to view details")
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(QSpacing.xl)
    }

    private func modelDetail(_ entry: ModelEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                systemRow
                if let err = modelManager.lastError {
                    errorBanner(err)
                }

                QCard {
                    VStack(alignment: .leading, spacing: QSpacing.m) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayName)
                                    .font(QFonts.title)
                                    .foregroundStyle(QColors.textPrimary)
                                Text("\(entry.publisher) · \(entry.familyName)")
                                    .font(QFonts.caption)
                                    .foregroundStyle(QColors.textSecondary)
                            }
                            Spacer()
                            if case .active = modelManager.status(for: entry, activeTag: prefs.activeModelTag) {
                                QTag(text: "Active Model", style: .success, icon: "checkmark")
                            }
                        }

                        QFlowLayout(spacing: 6, lineSpacing: 6) {
                            QTag(text: String(format: "%.1f GB", entry.sizeGB), style: .neutral, icon: "arrow.down.circle")
                            QTag(text: "\(Int(entry.ramGB)) GB RAM", style: .neutral, icon: "memorychip")
                            QTag(text: entry.speed.label, style: .accent, icon: entry.speed.icon)
                            if entry.recommended {
                                QTag(text: "Recommended", style: .warning, icon: "star.fill")
                            }
                            if entry.goodAtArabic {
                                QTag(text: L.t(.modelGoodForArabic), style: .success, icon: "character.book.closed")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(entry.description)
                            .font(QFonts.body)
                            .foregroundStyle(QColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                statsRow(entry)

                if modelManager.isRAMInsufficient(for: entry) {
                    ramWarning(entry)
                }

                actionArea(entry)
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(QColors.destructive)
            VStack(alignment: .leading, spacing: 3) {
                Text("Engine error")
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Text(msg)
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(QColors.destructive.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(QColors.destructive.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
    }

    private var systemRow: some View {
        HStack {
            QTag(
                text: String(format: "Your Mac: Apple Silicon · %.0f GB", modelManager.detectedRAMGB),
                style: .neutral,
                icon: "macwindow"
            )
            Spacer()
        }
    }

    private func statsRow(_ entry: ModelEntry) -> some View {
        HStack(spacing: QSpacing.m) {
            statCard(label: "Download Size", value: String(format: "%.1f GB", entry.sizeGB), icon: "arrow.down.circle")
            statCard(label: "RAM Required",  value: "\(Int(entry.ramGB)) GB",                icon: "memorychip")
            statCard(label: "Speed",          value: entry.speed.label,                      icon: entry.speed.icon)
        }
    }

    private func statCard(label: String, value: String, icon: String) -> some View {
        QCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(QColors.textTertiary)
                    Text(label)
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
                Text(value)
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ramWarning(_ entry: ModelEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(QColors.warning)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("This model may be too large for your Mac")
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Text(String(format: "Detected %.0f GB RAM, model needs %d GB. It may run slowly or cause memory pressure.",
                            modelManager.detectedRAMGB, Int(entry.ramGB)))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(QColors.warning.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(QColors.warning.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
    }

    @ViewBuilder
    private func actionArea(_ entry: ModelEntry) -> some View {
        let status = modelManager.status(for: entry, activeTag: prefs.activeModelTag)
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                switch status {
                case .notInstalled:
                    QButton(title: "Download Model", icon: "arrow.down.circle.fill",
                            style: .primary, size: .large, fullWidth: true) {
                        modelManager.startDownload(entry)
                    }
                case .downloading(let fraction):
                    downloadProgressView(entry: entry, fraction: fraction)
                case .installed:
                    HStack(spacing: 10) {
                        QButton(title: "Use This Model", icon: "checkmark.circle.fill",
                                style: .primary, size: .medium) {
                            prefs.activeModelTag = entry.ollamaTag
                        }
                        QButton(title: "Delete", icon: "trash",
                                style: .destructive, size: .medium) {
                            confirmDeleteTag = entry.ollamaTag
                        }
                        Spacer()
                    }
                    if confirmDeleteTag == entry.ollamaTag {
                        confirmDeleteBanner(entry)
                    }
                case .active:
                    HStack(spacing: 10) {
                        QTag(text: "In Use", style: .success, icon: "checkmark.circle.fill")
                        Spacer()
                        QButton(title: "Delete", icon: "trash",
                                style: .destructive, size: .medium, disabled: true) {}
                    }
                    Text("Switch to another model before deleting.")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
            }
        }
    }

    private func downloadProgressView(entry: ModelEntry, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            QProgressBar(progress: fraction)
            HStack {
                let percent = Int((fraction * 100).rounded())
                Text("Downloading… \(percent)%")
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textPrimary)
                Spacer()
                QButton(title: "Cancel", style: .ghost, size: .small) {
                    modelManager.cancelDownload(entry)
                }
            }
        }
    }

    private func confirmDeleteBanner(_ entry: ModelEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(QColors.destructive)
            Text("Delete \(entry.displayName)? This frees \(String(format: "%.1f", entry.sizeGB)) GB.")
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
            Spacer()
            QButton(title: "Cancel", style: .ghost, size: .small) {
                confirmDeleteTag = nil
            }
            QButton(title: "Delete", style: .destructive, size: .small) {
                modelManager.deleteModel(entry)
                confirmDeleteTag = nil
            }
        }
        .padding(10)
        .background(QColors.destructive.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.small, style: .continuous)
                .strokeBorder(QColors.destructive.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
    }
}
