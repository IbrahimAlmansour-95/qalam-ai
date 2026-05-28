import SwiftUI

struct MyInfoSettingsView: View {
    @State private var store = PersonalInfoStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                infoCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
