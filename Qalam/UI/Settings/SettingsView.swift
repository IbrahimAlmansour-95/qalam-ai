import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, models, modes, snippets, myInfo, shortcuts, privacy

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .general:   return L.t(.tabGeneral)
        case .models:    return L.t(.tabModels)
        case .modes:     return L.t(.tabModes)
        case .snippets:  return L.t(.tabSnippets)
        case .myInfo:    return L.t(.tabMyInfo)
        case .shortcuts: return L.t(.tabShortcuts)
        case .privacy:   return L.t(.tabPrivacy)
        }
    }

    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .models:    return "cube.box"
        case .modes:     return "wand.and.stars"
        case .snippets:  return "text.bubble"
        case .myInfo:    return "person.text.rectangle"
        case .shortcuts: return "keyboard"
        case .privacy:   return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsTab = .general
    @State private var l10n = LocalizationStore.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 180, alignment: .top)
                .frame(maxHeight: .infinity)
            QDivider(orientation: .vertical)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 580)
        // One uniform background across the whole window — sidebar, content,
        // and any gaps. Cards inside stand out via backgroundElevated.
        .background(QColors.backgroundPrimary)
        .environment(\.layoutDirection, l10n.current.layoutDirection)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                QalamLogo(size: 24, tint: QColors.accent)
                Text(Constants.appName)
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
            }
            .padding(.horizontal, QSpacing.l)
            .padding(.top, 28)
            .padding(.bottom, QSpacing.l)

            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Constants.appName) \(Constants.version)").font(QFonts.caption).foregroundStyle(QColors.textTertiary)
                Text("by \(Constants.developer)").font(QFonts.caption).foregroundStyle(QColors.textTertiary)
            }
            .padding(.horizontal, QSpacing.l)
            .padding(.bottom, QSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(tab.label).font(QFonts.body)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .foregroundStyle(selection == tab ? QColors.textPrimary : QColors.textSecondary)
            .background(selection == tab
                        ? QColors.backgroundElevated
                        : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
            // Make the entire row clickable — Color.clear doesn't register
            // hits, so without this only the icon/text area would respond.
            .contentShape(RoundedRectangle(cornerRadius: QRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:   GeneralSettingsView()
        case .models:    ModelsSettingsView()
        case .modes:     ModesSettingsView()
        case .snippets:  SnippetsSettingsView()
        case .myInfo:    MyInfoSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .privacy:   PrivacySettingsView()
        }
    }
}
