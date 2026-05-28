import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case accessibility = 1
    case installOllama = 2
    case personalize = 3
    case chooseModel = 4

    var id: Int { rawValue }
}

/// Slowly-drifting accent blobs behind the onboarding content — gives the
/// flow a soft, "magical" depth without being distracting.
private struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            QColors.backgroundPrimary
            blob(QColors.accent.opacity(0.28), size: 360)
                .offset(x: animate ? -120 : -80, y: animate ? -140 : -180)
            blob(QColors.familyQwen.opacity(0.22), size: 300)
                .offset(x: animate ? 140 : 100, y: animate ? 120 : 80)
            blob(QColors.success.opacity(0.16), size: 260)
                .offset(x: animate ? 80 : 40, y: animate ? -60 : -20)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
    }
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var prefs = UserPreferences.shared
    @State private var modelManager = ModelManager.shared
    @State private var axPollTimer: Timer?
    @State private var ollamaPollTimer: Timer?
    @State private var selectedTag: String = "gemma3:4b"
    @State private var l10n = LocalizationStore.shared
    @State private var personalName: String = ""
    @State private var personalEmail: String = ""

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .id(step)   // re-run entrance transition per step
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity.combined(with: .offset(y: -12))
                    ))
                Spacer(minLength: 0)
                stepDots
                    .padding(.bottom, QSpacing.l)
            }
            .padding(QSpacing.xxl)
        }
        .frame(width: 640, height: 560)
        .environment(\.layoutDirection, l10n.current.layoutDirection)
        .onDisappear {
            axPollTimer?.invalidate()
            ollamaPollTimer?.invalidate()
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 6) {
            ForEach(LocalizationStore.Language.allCases, id: \.self) { lang in
                Button {
                    l10n.current = lang
                } label: {
                    Text(lang.displayName)
                        .font(QFonts.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(l10n.current == lang ? .white : QColors.textSecondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(l10n.current == lang ? QColors.accent : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .accessibility: accessibilityStep
        case .installOllama: installOllamaStep
        case .personalize: personalizeStep
        case .chooseModel: chooseModelStep
        }
    }

    // MARK: - Step 1

    private var welcomeStep: some View {
        VStack(spacing: QSpacing.l) {
            AnimatedLogoMark()
            VStack(spacing: 10) {
                Text(L.t(.onbWelcomeTitle))
                    .font(QFonts.display)
                    .foregroundStyle(QColors.textPrimary)
                Text(L.t(.onbWelcomeSubtitle))
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                Text(L.t(.onbChooseLanguage))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                languagePicker
            }
            QButton(title: L.t(.onbGetStarted), icon: "arrow.right",
                    style: .primary, size: .large) {
                withAnimation(QAnimation.spring) { step = .accessibility }
            }
            .frame(maxWidth: 200)
        }
    }

    // MARK: - Step 2

    private var accessibilityStep: some View {
        VStack(spacing: QSpacing.l) {
            ZStack {
                Circle()
                    .fill(QColors.accent.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(QColors.accent)
            }
            VStack(spacing: 10) {
                Text(L.t(.onbAccessibilityTitle))
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
                Text(L.t(.onbAccessibilityBody))
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                QButton(title: L.t(.onbOpenSystemSettings), icon: "arrow.up.right.square",
                        style: .primary, size: .large) {
                    AccessibilityMonitor.shared.openSystemSettings()
                    _ = AccessibilityMonitor.shared.checkPermission(prompt: true)
                    startAXPoll()
                }
                QButton(title: L.t(.onbSkip), style: .ghost, size: .large) {
                    withAnimation(QAnimation.spring) { step = .installOllama }
                }
            }
            if AccessibilityMonitor.shared.checkPermission() {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(QColors.success)
                    Text("Granted")
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.success)
                }
            }
        }
        .onAppear { startAXPoll() }
    }

    private func startAXPoll() {
        axPollTimer?.invalidate()
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if AccessibilityMonitor.shared.checkPermission() {
                    axPollTimer?.invalidate()
                    withAnimation(QAnimation.spring) { step = .installOllama }
                }
            }
        }
    }

    // MARK: - Step 3

    private var installOllamaStep: some View {
        VStack(spacing: QSpacing.l) {
            ZStack {
                Circle()
                    .fill(QColors.accent.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: engineReady ? "checkmark.seal.fill" : "shippingbox")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(engineReady ? QColors.success : QColors.accent)
            }
            VStack(spacing: 10) {
                Text(engineReady ? L.t(.onbEngineReadyTitle) : L.t(.onbSettingUpTitle))
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
                Text(engineReady ? L.t(.onbEngineReadyBody) : L.t(.onbSettingUpBody))
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            if modelManager.installerActive {
                VStack(spacing: 8) {
                    QProgressBar(progress: modelManager.installerProgress)
                        .frame(width: 320)
                    Text(modelManager.installerStatus)
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                }
            } else {
                QButton(title: L.t(.onbContinue), icon: "arrow.right",
                        style: .primary, size: .large,
                        disabled: !engineReady) {
                    withAnimation(QAnimation.spring) { step = .personalize }
                }
                .frame(maxWidth: 200)
            }
        }
        .onAppear {
            Task { await ModelManager.shared.ensureOllamaAvailable() }
        }
    }

    private var engineReady: Bool {
        modelManager.ollamaSource != .missing
    }

    // MARK: - Step 4 — Personalize

    private var personalizeStep: some View {
        VStack(spacing: QSpacing.l) {
            ZStack {
                Circle().fill(QColors.accent.opacity(0.15)).frame(width: 84, height: 84)
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(QColors.accent)
            }
            VStack(spacing: 8) {
                Text(L.t(.onbPersonalizeTitle))
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
                Text(L.t(.onbPersonalizeBody))
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 10) {
                QTextField(placeholder: L.t(.onbPersonalizeName), text: $personalName)
                QTextField(placeholder: L.t(.onbPersonalizeEmail), text: $personalEmail)
            }
            .frame(maxWidth: 320)

            HStack(spacing: 12) {
                QButton(title: L.t(.onbContinue), icon: "arrow.right",
                        style: .primary, size: .large) {
                    savePersonalInfo()
                    withAnimation(QAnimation.spring) { step = .chooseModel }
                }
                QButton(title: L.t(.onbSkip), style: .ghost, size: .large) {
                    withAnimation(QAnimation.spring) { step = .chooseModel }
                }
            }
        }
    }

    private func savePersonalInfo() {
        let store = PersonalInfoStore.shared
        let name = personalName.trimmingCharacters(in: .whitespaces)
        let email = personalEmail.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            if let item = store.items.first(where: { $0.label.lowercased() == "name" }) {
                store.update(.init(id: item.id, label: item.label, value: name))
            } else { store.add(label: "Name", value: name) }
        }
        if !email.isEmpty {
            if let item = store.items.first(where: { $0.label.lowercased() == "email" }) {
                store.update(.init(id: item.id, label: item.label, value: email))
            } else { store.add(label: "Email", value: email) }
        }
    }

    // MARK: - Step 5 — Smart model recommendation

    private var chooseModelStep: some View {
        let specs = DeviceSpecs.detect()
        let recommendation = ModelRecommender.recommend(for: specs)

        return VStack(spacing: QSpacing.l) {
            VStack(spacing: 6) {
                Text(L.t(.onbRecommendedTitle))
                    .font(QFonts.title)
                    .foregroundStyle(QColors.textPrimary)
                Text(specs.summary)
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
            }

            recommendedCard(recommendation.entry, reason: recommendation.reason)

            suggestionLengthOnboardingControl

            if !recommendation.alternates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t(.onbOrPickAnother))
                        .font(QFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(QColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        ForEach(recommendation.alternates) { entry in
                            alternateCard(entry)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            HStack(spacing: 12) {
                QButton(title: L.t(.onbDownloadAndStart),
                        icon: "arrow.down.circle.fill",
                        style: .primary, size: .large) {
                    let tag = selectedTag.isEmpty ? recommendation.entry.ollamaTag : selectedTag
                    if let entry = ModelRegistry.entry(forTag: tag) {
                        prefs.activeModelTag = tag
                        modelManager.startDownload(entry)
                    }
                    AppState.shared.dismissOnboarding()
                }
                QButton(title: L.t(.onbSkipForNow), style: .ghost, size: .large) {
                    AppState.shared.dismissOnboarding()
                }
            }
        }
        .onAppear {
            // Lock in the recommendation as default selection.
            if selectedTag.isEmpty {
                selectedTag = ModelRecommender.recommend(for: DeviceSpecs.detect()).entry.ollamaTag
            }
        }
    }

    /// Compact "next words" slider shown under the recommended model card.
    /// Tracks `prefs.maxSuggestionWords`, capped to the currently-selected
    /// model's `speed.maxSuggestionWords`.
    private var suggestionLengthOnboardingControl: some View {
        let activeTag = selectedTag.isEmpty
            ? ModelRecommender.recommend(for: DeviceSpecs.detect()).entry.ollamaTag
            : selectedTag
        let entry = ModelRegistry.entry(forTag: activeTag)
        let modelMax = entry?.maxSuggestionWords ?? 5
        let clamped = max(1, min(prefs.maxSuggestionWords, modelMax))

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(.generalMaxWords))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                Text("\(clamped) \(L.t(.generalMaxWordsValue))  ·  \(L.t(.generalMaxWordsModelCap)) \(modelMax)")
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
            }
            Slider(
                value: Binding(
                    get: { Double(clamped) },
                    set: { prefs.maxSuggestionWords = Int($0.rounded()) }
                ),
                in: 1...Double(modelMax),
                step: 1
            )
            .tint(QColors.accent)
        }
        .padding(12)
        .background(QColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(QColors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
    }

    private func recommendedCard(_ entry: ModelEntry, reason: String) -> some View {
        let active = selectedTag == entry.ollamaTag
        return Button {
            selectedTag = entry.ollamaTag
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(entry.family.accent)
                        .frame(width: 4, height: 22)
                    Text(entry.displayName)
                        .font(QFonts.title)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    QTag(text: "Recommended", style: .accent, icon: "sparkles")
                }
                HStack(spacing: 4) {
                    QTag(text: String(format: "%.1f GB", entry.sizeGB), style: .neutral, icon: "arrow.down.circle")
                    QTag(text: "\(Int(entry.ramGB)) GB RAM", style: .neutral, icon: "memorychip")
                    QTag(text: entry.speed.label, style: .accent, icon: entry.speed.icon)
                }
                Text(reason)
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(QSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QColors.backgroundElevated)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.large, style: .continuous)
                    .strokeBorder(active ? QColors.accent : QColors.accent.opacity(0.4),
                                  lineWidth: active ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func alternateCard(_ entry: ModelEntry) -> some View {
        let active = selectedTag == entry.ollamaTag
        return Button {
            selectedTag = entry.ollamaTag
        } label: {
            HStack(spacing: 8) {
                Rectangle().fill(entry.family.accent).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f GB", entry.sizeGB))
                        Text("·")
                        Text(entry.speed.label)
                    }
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QColors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                    .strokeBorder(active ? QColors.accent : QColors.borderSubtle,
                                  lineWidth: active ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step dots

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { s in
                Circle()
                    .fill(s.rawValue == step.rawValue ? QColors.accent : Color.white.opacity(0.12))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// The قلم mark with a scale-in entrance and a slow breathing glow — the
/// little bit of "magic" on the welcome screen.
private struct AnimatedLogoMark: View {
    @State private var appeared = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(QColors.accent.opacity(0.18))
                .frame(width: 110, height: 110)
                .blur(radius: glow ? 14 : 6)
                .scaleEffect(glow ? 1.08 : 0.96)
            Circle()
                .fill(QColors.accent.opacity(0.15))
                .frame(width: 96, height: 96)
            QalamLogo(size: 60, tint: QColors.accent)
        }
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
