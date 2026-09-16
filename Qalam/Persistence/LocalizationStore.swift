import Foundation
import SwiftUI
import Observation

/// QalamAI's own translation table. We don't use Bundle .strings files because
/// the user needs to change the UI language at runtime from Settings, which
/// would require re-launching the app under the system localization model.
///
/// Add a new key to `Translations.dict` to localize a new piece of UI, then
/// reference it via `L.t(.someKey)` in SwiftUI views.
@MainActor
@Observable
final class LocalizationStore {
    static let shared = LocalizationStore()

    enum Language: String, CaseIterable, Codable, Sendable {
        case english = "en"
        case arabic  = "ar"

        var displayName: String {
            switch self {
            case .english: return "English"
            case .arabic:  return "العربية"
            }
        }

        var nativeName: String { displayName }

        var layoutDirection: LayoutDirection {
            self == .arabic ? .rightToLeft : .leftToRight
        }

        var locale: Locale {
            Locale(identifier: rawValue)
        }
    }

    private let key = "qalam.uiLanguage"
    var current: Language {
        didSet {
            QalamDefaults.suite.set(current.rawValue, forKey: key)
        }
    }

    private init() {
        if let raw = QalamDefaults.suite.string(forKey: "qalam.uiLanguage"),
           let lang = Language(rawValue: raw) {
            self.current = lang
        } else {
            // Default to the system's preferred language if it's Arabic.
            let pref = Locale.preferredLanguages.first ?? "en"
            self.current = pref.hasPrefix("ar") ? .arabic : .english
        }
    }

    /// Translate a key for the currently selected language. Falls back to the
    /// English value if no Arabic translation is registered, or to the raw
    /// key string if neither is registered.
    func t(_ key: LocalizationKey) -> String {
        let row = Translations.dict[key] ?? [:]
        return row[current] ?? row[.english] ?? key.rawValue
    }
}

/// String keys for every piece of localized UI. Adding a key here without
/// adding entries in `Translations.dict` will render the raw key — useful
/// while wiring up.
enum LocalizationKey: String, CaseIterable, Sendable {
    // Onboarding
    case onbWelcomeTitle
    case onbWelcomeSubtitle
    case onbGetStarted
    case onbChooseLanguage
    case onbAccessibilityTitle
    case onbAccessibilityBody
    case onbOpenSystemSettings
    case onbSkip
    case onbContinue
    case onbEngineReadyTitle
    case onbEngineReadyBody
    case onbSettingUpTitle
    case onbSettingUpBody
    case onbRecommendedTitle
    case onbOrPickAnother
    case onbDownloadAndStart
    case onbSkipForNow
    case onbPersonalizeTitle
    case onbPersonalizeBody
    case onbPersonalizeName
    case onbPersonalizeEmail

    // Settings tabs
    case settingsTitle
    case tabGeneral
    case tabModels
    case tabModes
    case tabSnippets
    case tabShortcuts
    case tabPrivacy
    case tabMyInfo
    // My Info
    case myInfoHeading
    case myInfoSubheading
    case myInfoPrivacy
    case myInfoAddField
    case myInfoLabelPlaceholder
    case myInfoValuePlaceholder
    // General extras
    case generalSpaceAfterTab
    case generalSpaceAfterTabHelp
    case generalAutoUpdate
    case generalAutoUpdateHelp
    // Updater
    case updateAvailable
    case updateDownload
    case updateCheckNow
    case updateChecking
    case updateUpToDate
    // Uninstall
    case uninstallTitle
    case uninstallBody
    case uninstallKeepData
    case uninstallKeepDataHelp
    case uninstallEverything
    case uninstallEverythingHelp
    case uninstallReveal
    case uninstallConfirmKeep
    case uninstallConfirmAll
    case uninstallCancel

    // General tab
    case generalHeading
    case generalSubheading
    case generalLaunchAtLogin
    case generalShowInMenuBar
    case generalEnableSuggestions
    case generalContextAutocorrect
    case generalContextAutocorrectBody
    case generalSuggestSpelling
    case generalSuggestGrammar
    case generalSuggestionDelay
    case generalSuggestionDelayHelp
    case generalTriggerThreshold
    case generalTriggerThresholdHelp
    case generalLanguage
    case generalLanguageHelp
    case generalMaxWords
    case generalMaxWordsHelp
    case generalMaxWordsValue        // "{n} words"
    case generalMaxWordsModelCap     // "Model max: {n}"
    case generalExcludedApps
    // Engine + context
    case generalEngine
    case generalEngineHelp
    case engineOllama
    case engineAppleIntelligence
    case generalContextSources
    case generalContextSourcesHelp
    case ctxBroader
    case ctxBroaderHelp
    case ctxClipboard
    case ctxClipboardHelp
    case ctxScreen
    case ctxScreenHelp
    case ctxScreenGrant
    // Modes tab
    case modesHeading
    case modesBuiltIn
    case modesCustom
    case modesCustomHelp
    case modesNewMode
    case modesNoCustom
    case modesNewModeTitle
    case modesName
    case modesInstruction
    case modesTemperature
    case commonCancel
    case commonCreate
    case commonDelete
    case commonUse
    // Snippets tab
    case snippetsHeading
    case snippetsSubheading
    case snippetsHowTitle
    case snippetsNewTitle
    case snippetsExpansion
    case snippetsAdd
    case snippetsYours
    case snippetsNone
    // Shortcuts tab
    case shortcutsHeading
    case shortcutsSubheading
    case shortcutAcceptWord
    case shortcutDismiss
    case shortcutPauseResume
    case shortcutPauseHelp
    // Privacy tab
    case privacyHeading
    case privacySubheading
    case privacyLast7Days
    case privacyLocalTitle
    case privacyWordsToday
    case privacyStyleEntries
    case privacyClearStyle
    case privacyResetStats
    // Models tab
    case modelsSelectPrompt
    case modelsDownload
    case modelsUseThis
    case modelsBrowseAll
    case modelsSearch

    // Menu bar popover
    case popoverEnableSuggestions
    case popoverWritingMode
    case popoverActiveModel
    case popoverChange
    case popoverTodaysStats
    case popoverWordsCompleted
    case popoverKeystrokesSaved
    case popoverSuggestionsShown
    case popoverSettings
    case popoverQuit
    case popoverAccessibilityRequired
    case popoverAccessibilityBody
    case popoverOpenAccessibility
    case popoverStatusActive
    case popoverStatusPaused
    case popoverStatusStarting
    case popoverStatusStopped
    case popoverStatusInstallOllama
    case popoverStatusChecking
    case popoverStatusNeedsAccess
    case modelGoodForArabic
    case popoverCompatibility
    case popoverCompatibilityWorks
    case popoverCompatibilityToggle
    case popoverCompatibilityLimited
    // ━━━ Snooze ━━━
    case popoverSnooze
    case popoverSnoozeResume
    case popoverSnooze30m
    case popoverSnooze1h
    case popoverSnoozeTomorrow
    case popoverSnoozedUntil
    // ━━━ Accept key / hint (General) ━━━
    case generalAcceptKey
    case generalAcceptKeyTab
    case generalAcceptKeyArrow
    case generalShowAcceptHint
    case generalShowAcceptHintHelp
    // ━━━ Custom model import (Models) ━━━
    case modelsAddCustom
    case modelsAddCustomTitle
    case modelsAddCustomHelp
    case modelsAddCustomPlaceholder
    case modelsAddCustomButton
    case modelsCustomBadge
    // ━━━ Diagnostics (Privacy) ━━━
    case diagnosticsTitle
    case diagnosticsHelp
    case diagnosticsCopy
    case diagnosticsCopied
    // ━━━ Appearance (General) ━━━
    case generalAppearance
    case generalAppearanceSystem
    case generalAppearanceLight
    case generalAppearanceDark
    // ━━━ Ghost calibration ━━━
    case generalGhostCalibration
    case generalGhostCalibrationHelp
    case generalGhostSize
    case generalGhostVOffset
    case generalGhostReset
    // ━━━ In-app update install ━━━
    case updateInstall
    case updateDownloading
    case updateOpening
    case updateReady
    // ━━━ Tone rewrite on selection ━━━
    case rewriteTitle
    case rewriteWorking
    case rewriteFailed
    case rewriteToneFormal
    case rewriteToneCasual
    case rewriteToneConcise
    case rewriteToneExpand
    case rewriteToneGrammar
    // ━━━ v1.4 T1 stability ━━━
    case popoverSecureInputPaused
    case popoverSecureInputHelp
    case popoverStatusRestarting
    case popoverStatusEngineFailed
    case popoverEngineFailedHelp
    case popoverEngineRetry
    case rewriteTimedOut
    // ━━━ v1.4 T2 diagnostics ━━━
    case diagShowLogs
    // ━━━ v1.4 T3 apps & profiles ━━━
    case tabApps
    case appsHeading
    case appsSubheading
    case appsAddFrontmostFmt
    case appsAddFrontmost
    case appsAddRunning
    case appsAddWebsite
    case appsWebsitePlaceholder
    case appsWebsiteInvalid
    case appsAddHelp
    case appsConfigured
    case appsConfiguredEmpty
    case appsRecent
    case appsRecentEmpty
    case appsShowAllFmt
    case appsShowFewer
    case appsRecentSitesHelp
    case appsWebsite
    case appsCustomized
    case appsSelectPrompt
    case appsActivation
    case appsActivationInherit
    case appsActivationAlwaysOn
    case appsActivationForceOnly
    case appsActivationOff
    case appsActivationHelp
    case appsWritingMode
    case appsInherit
    case appsInheritValueFmt
    case appsLanguage
    case appsLanguageAuto
    case appsLanguageEnglish
    case appsLanguageArabic
    case appsLanguageHelp
    case appsAutocorrect
    case appsAutocorrectHelp
    case appsOn
    case appsOff
    case appsInstructions
    case appsInstructionsHelp
    case appsInstructionsPlaceholder
    case appsReset
    case appsRemove
    case appsOpen
    case appsManageHint
    case myInfoInstructionsTitle
    case myInfoInstructionsHelp
    case myInfoInstructionsPlaceholder
    case popoverSuggestInAppFmt
    case popoverSuggestOnSiteFmt
    case popoverAppPausedFmt
    // ━━━ v1.4 T4 shortcuts & activation ━━━
    case shortcutCardVisible
    case shortcutCardAnywhere
    case shortcutCardEsc
    case shortcutAcceptWordHelp
    case shortcutTabPassNote
    case shortcutAcceptAll
    case shortcutAcceptAllHelp
    case shortcutRealTab
    case shortcutRealTabHelp
    case shortcutDismissHelp
    case shortcutRegenerate
    case shortcutRegenerateHelp
    case shortcutForceActivate
    case shortcutForceActivateHelp
    case shortcutForceEditorsHelp
    case shortcutAppToggle
    case shortcutAppToggleHelp
    case shortcutRewrite
    case shortcutRewriteHelp
    case shortcutEditorsPassHelp
    case shortcutKeyAboveTab
    case shortcutKeyAboveTabHelp
    case shortcutEscDismiss
    case shortcutEscDismissPause
    case shortcutEscPass
    case shortcutEscHelp
    case toastPaused
    case toastResumed
    case toastPausedAppFmt
    case toastResumedAppFmt
    case toastNoField
    case toastForceBlocked
    case appsTabAccept
    case appsTabAcceptOn
    case appsTabAcceptOff
    case appsTabAcceptHelp

    // ━━━ v1.4 T5 mirror bubble, compatibility, field button ━━━
    case appsDisplay
    case appsDisplayInline
    case appsDisplayMirror
    case appsDisplayHelp
    case appsCompat
    case appsCompatElectron
    case appsCompatHelp
    case generalDisplay
    case generalCaretUnavailable
    case generalCaretUnavailableBubble
    case generalCaretUnavailableHide
    case generalCaretUnavailableHelp
    case generalFieldButton
    case generalFieldButtonHelp
    case fieldButtonDisableFmt
    case fieldButtonEnableFmt
    case fieldButtonPause10
    case fieldButtonSettings

    // ━━━ v1.4 T6 personalization ━━━
    case tabPersonalization
    case personaHeading
    case personaSubheading
    case personaRecord
    case personaRecordHelp
    case personaMode
    case personaModeAccepted
    case personaModeEverything
    case personaModeHelp
    case personaStrength
    case personaStrengthOff
    case personaStrengthLow
    case personaStrengthMedium
    case personaStrengthStrong
    case personaStrengthHelp
    case personaSamples
    case personaSamplesHelp
    case personaSamplesEmpty
    case personaSampleCountFmt
    case personaDelete
    case personaDeleteAll
    case personaDeleteAllTitle
    case personaDeleteAllConfirm
    case personaPrivacy
    case personaUnavailable
    case appsRecord
    case appsRecordHelp
    case appsRecordSamplesFmt
    case appsRecordDelete

    // ━━━ v1.4 T7 suggestion features ━━━
    case generalCompletionShort
    case generalCompletionMedium
    case generalCompletionLong
    case generalCompletionLengthHelp
    case generalCompletionLongUnavailable
    case generalMidLine
    case generalMidLineHelp
    case generalAlternativesAutoShow
    case generalAlternativesAutoShowHelp
    case generalAutocorrectStyle
    case generalAutocorrectStyleInline
    case generalAutocorrectStyleArrow
    case generalAutocorrectStyleHelp
    case shortcutAcceptAllAboveTab
    case shortcutAcceptAllAboveTabHelp
    case shortcutAlternatives
    case shortcutAlternativesHelp
    case shortcutInsertAlternative
    case shortcutInsertAlternativeHelp
    case alternativesLoading

    // ━━━ v1.4 T8 encrypted iCloud Drive sync ━━━
    case tabSync
    case syncHeading
    case syncSubheading
    case syncUnavailable
    case syncTurnOnTitle
    case syncTurnOn
    case syncPassphrase
    case syncPassphraseConfirm
    case syncPassphraseHelp
    case syncPassphraseTooShort
    case syncPassphraseMismatch
    case syncReenterTitle
    case syncReenterHelp
    case syncSavePassphrase
    case syncStatus
    case syncStatusOff
    case syncStatusIdle
    case syncStatusSyncing
    case syncStatusWaiting
    case syncErrorWrongPassphrase
    case syncErrorKeychain
    case syncErrorIO
    case syncErrorFormat
    case syncLastSync
    case syncNever
    case syncNow
    case syncTurnOff
    case syncTurnOffTitle
    case syncTurnOffMessage
    case syncTurnOffKeep
    case syncTurnOffRemove
    case syncIncludeSamples
    case syncIncludeSamplesHelp
    case syncWhatSyncs
    case syncItemSnippets
    case syncItemModes
    case syncItemApps
    case syncItemInstructions
    case syncItemMyInfo
    case syncNeverNote
    case syncEncryptionNote

    // ━━━ v1.4 T9 integration polish ━━━
    case popoverStatusSnoozed
}

enum Translations {
    static let dict: [LocalizationKey: [LocalizationStore.Language: String]] = [
        // ━━━ Onboarding ━━━
        .onbWelcomeTitle: [
            .english: "Meet QalamAI",
            .arabic:  "تعرّف على QalamAI"
        ],
        .onbWelcomeSubtitle: [
            .english: "AI autocomplete that learns your voice.\nTab to accept. Never leaves your Mac.",
            .arabic:  "إكمال تلقائي ذكي يتعلّم أسلوبك.\nاضغط Tab لقبول الاقتراح. لا يغادر جهازك أبداً."
        ],
        .onbGetStarted: [
            .english: "Get Started",
            .arabic:  "ابدأ الآن"
        ],
        .onbChooseLanguage: [
            .english: "Language",
            .arabic:  "اللغة"
        ],
        .onbAccessibilityTitle: [
            .english: "Grant Accessibility Access",
            .arabic:  "منح صلاحية إمكانية الوصول"
        ],
        .onbAccessibilityBody: [
            .english: "QalamAI needs Accessibility access to read and suggest text in any app. This stays on your Mac.",
            .arabic:  "يحتاج QalamAI إلى صلاحية إمكانية الوصول لقراءة النصوص واقتراحها في أي تطبيق. يبقى كل شيء على جهازك."
        ],
        .onbOpenSystemSettings: [
            .english: "Open System Settings",
            .arabic:  "فتح إعدادات النظام"
        ],
        .onbSkip: [
            .english: "Skip",
            .arabic:  "تخطّي"
        ],
        .onbContinue: [
            .english: "Continue",
            .arabic:  "متابعة"
        ],
        .onbEngineReadyTitle: [
            .english: "Engine ready",
            .arabic:  "المحرك جاهز"
        ],
        .onbEngineReadyBody: [
            .english: "QalamAI bundles its own local AI engine. Nothing to install.",
            .arabic:  "يأتي QalamAI ومعه محرّك ذكاء اصطناعي محلي. لا حاجة لتثبيت أي شيء."
        ],
        .onbSettingUpTitle: [
            .english: "Setting up the engine",
            .arabic:  "جارٍ تجهيز المحرك"
        ],
        .onbSettingUpBody: [
            .english: "QalamAI is preparing its local AI engine. This happens once.",
            .arabic:  "يقوم QalamAI بتجهيز محرك الذكاء الاصطناعي المحلي. يحدث هذا مرة واحدة فقط."
        ],
        .onbRecommendedTitle: [
            .english: "Recommended for your Mac",
            .arabic:  "النموذج المُوصى به لجهازك"
        ],
        .onbOrPickAnother: [
            .english: "OR PICK ANOTHER",
            .arabic:  "أو اختر نموذجاً آخر"
        ],
        .onbDownloadAndStart: [
            .english: "Download & Start",
            .arabic:  "تنزيل وبدء الاستخدام"
        ],
        .onbSkipForNow: [
            .english: "Skip for now",
            .arabic:  "تخطّي الآن"
        ],
        .onbPersonalizeTitle: [
            .english: "Make it yours",
            .arabic:  "اجعله خاصاً بك"
        ],
        .onbPersonalizeBody: [
            .english: "Add your details so QalamAI can complete them in context — like your email after \"reach me at\". Stays on your Mac.",
            .arabic:  "أضف بياناتك ليُكملها QalamAI حسب السياق — مثل بريدك بعد «تواصل معي على». تبقى على جهازك."
        ],
        .onbPersonalizeName:  [.english: "Your name", .arabic: "اسمك"],
        .onbPersonalizeEmail: [.english: "Your email", .arabic: "بريدك الإلكتروني"],

        // ━━━ Settings tabs ━━━
        .settingsTitle: [
            .english: "QalamAI Settings",
            .arabic:  "إعدادات QalamAI"
        ],
        .tabGeneral:   [.english: "General",   .arabic: "عام"],
        .tabModels:    [.english: "Models",    .arabic: "النماذج"],
        .tabModes:     [.english: "Modes",     .arabic: "الأنماط"],
        .tabSnippets:  [.english: "Snippets",  .arabic: "المختصرات"],
        .tabShortcuts: [.english: "Shortcuts", .arabic: "اختصارات لوحة المفاتيح"],
        .tabPrivacy:   [.english: "Privacy",   .arabic: "الخصوصية"],
        .tabMyInfo:    [.english: "My Info",   .arabic: "معلوماتي"],

        // ━━━ My Info ━━━
        .myInfoHeading:    [.english: "My Information", .arabic: "معلوماتي"],
        .myInfoSubheading: [
            .english: "Your details, so QalamAI can complete them when you type — e.g. \"reach me at\" → your email.",
            .arabic:  "بياناتك، ليتمكّن QalamAI من إكمالها عند الكتابة — مثل «تواصل معي على» → بريدك."
        ],
        .myInfoPrivacy: [
            .english: "Stored only on your Mac and fed straight to the on-device model. Never uploaded.",
            .arabic:  "تُحفظ على جهازك فقط وتُمرّر مباشرة إلى النموذج المحلي. لا تُرفع أبداً."
        ],
        .myInfoAddField:        [.english: "Add field", .arabic: "إضافة حقل"],
        .myInfoLabelPlaceholder:[.english: "Label (e.g. Email)", .arabic: "التسمية (مثل البريد)"],
        .myInfoValuePlaceholder:[.english: "Value", .arabic: "القيمة"],

        // ━━━ General extras ━━━
        .generalSpaceAfterTab: [
            .english: "Add a space after accepting",
            .arabic:  "إضافة مسافة بعد القبول"
        ],
        .generalSpaceAfterTabHelp: [
            .english: "Insert a space after the last word you accept with the accept key (Tab or →). Words inside a longer suggestion always keep their spaces.",
            .arabic:  "أضف مسافة بعد آخر كلمة تقبلها بمفتاح القبول (Tab أو →). أما الكلمات داخل اقتراح أطول فتحتفظ بمسافاتها دائماً."
        ],
        .generalAutoUpdate: [
            .english: "Automatic updates",
            .arabic:  "التحديثات التلقائية"
        ],
        .generalAutoUpdateHelp: [
            .english: "Check GitHub for new versions and notify you when one is available.",
            .arabic:  "التحقق من GitHub بحثاً عن إصدارات جديدة وإعلامك عند توفّرها."
        ],

        // ━━━ Updater ━━━
        .updateAvailable: [
            .english: "Update available",
            .arabic:  "يتوفّر تحديث"
        ],
        .updateDownload: [
            .english: "Download",
            .arabic:  "تنزيل"
        ],
        .updateCheckNow:  [.english: "Check for updates", .arabic: "التحقق من التحديثات"],
        .updateChecking:  [.english: "Checking…", .arabic: "جارٍ التحقق…"],
        .updateUpToDate:  [.english: "You're up to date", .arabic: "أنت على أحدث إصدار"],

        // ━━━ Uninstall ━━━
        .uninstallTitle: [
            .english: "Uninstall QalamAI",
            .arabic:  "إلغاء تثبيت QalamAI"
        ],
        .uninstallBody: [
            .english: "Remove the app cleanly. You can keep your downloaded models and settings so reinstalling is instant — no re-download, no re-setup.",
            .arabic:  "أزل التطبيق بنظافة. يمكنك الاحتفاظ بالنماذج المُنزّلة والإعدادات ليكون إعادة التثبيت فورياً — دون إعادة تنزيل أو إعداد."
        ],
        .uninstallKeepData: [
            .english: "Remove app, keep models & settings",
            .arabic:  "إزالة التطبيق مع الاحتفاظ بالنماذج والإعدادات"
        ],
        .uninstallKeepDataHelp: [
            .english: "Moves QalamAI to the Trash but leaves your models and preferences in place.",
            .arabic:  "ينقل QalamAI إلى سلة المهملات مع إبقاء النماذج والتفضيلات."
        ],
        .uninstallEverything: [
            .english: "Remove everything",
            .arabic:  "إزالة كل شيء"
        ],
        .uninstallEverythingHelp: [
            .english: "Also trashes downloaded models and settings. This frees the most space. Also moves QalamAI’s encrypted iCloud Drive sync copy to the Trash.",
            .arabic:  "يحذف أيضاً النماذج المُنزّلة والإعدادات إلى سلة المهملات. يوفّر أكبر مساحة. وينقل أيضاً نسخة مزامنة QalamAI المشفّرة في iCloud Drive إلى سلة المهملات."
        ],
        .uninstallReveal: [
            .english: "Show my data in Finder",
            .arabic:  "إظهار بياناتي في Finder"
        ],
        .uninstallConfirmKeep: [
            .english: "Quit and move QalamAI to the Trash? Your models and settings will be kept.",
            .arabic:  "الخروج ونقل QalamAI إلى سلة المهملات؟ سيتم الاحتفاظ بالنماذج والإعدادات."
        ],
        .uninstallConfirmAll: [
            .english: "Quit and remove QalamAI, its models, and settings? Everything goes to the Trash (recoverable).",
            .arabic:  "الخروج وإزالة QalamAI ونماذجه وإعداداته؟ يذهب كل شيء إلى سلة المهملات (قابل للاسترجاع)."
        ],
        .uninstallCancel: [
            .english: "Cancel",
            .arabic:  "إلغاء"
        ],

        // ━━━ General tab ━━━
        .generalHeading: [
            .english: "General",
            .arabic:  "عام"
        ],
        .generalSubheading: [
            .english: "App-wide preferences for QalamAI.",
            .arabic:  "تفضيلات عامة لتطبيق QalamAI."
        ],
        .generalLaunchAtLogin: [
            .english: "Launch at login",
            .arabic:  "تشغيل تلقائي عند الدخول"
        ],
        .generalShowInMenuBar: [
            .english: "Show in menu bar",
            .arabic:  "إظهار في شريط القوائم"
        ],
        .generalEnableSuggestions: [
            .english: "Enable suggestions",
            .arabic:  "تفعيل الاقتراحات"
        ],
        .generalContextAutocorrect: [
            .english: "Context-aware autocorrect",
            .arabic:  "تصحيح تلقائي ذكي يراعي السياق"
        ],
        .generalContextAutocorrectBody: [
            .english: "Catches typos and grammar issues based on surrounding text — not random replacements.",
            .arabic:  "يلتقط الأخطاء الإملائية والقواعدية بناءً على النص المحيط — وليس تصحيحات عشوائية."
        ],
        .generalSuggestSpelling: [
            .english: "Suggest spelling fixes (local, instant)",
            .arabic:  "اقتراح تصحيحات إملائية (محلية وفورية)"
        ],
        .generalSuggestGrammar: [
            .english: "Suggest grammar fixes after each sentence (uses the local model)",
            .arabic:  "اقتراح تصحيحات قواعدية بعد كل جملة (باستخدام النموذج المحلي)"
        ],
        .generalSuggestionDelay: [
            .english: "Suggestion delay",
            .arabic:  "تأخير الاقتراح"
        ],
        .generalSuggestionDelayHelp: [
            .english: "Wait this long after the last keystroke before asking the model.",
            .arabic:  "الانتظار هذه المدة بعد آخر ضغطة قبل سؤال النموذج."
        ],
        .generalTriggerThreshold: [
            .english: "Trigger threshold",
            .arabic:  "الحد الأدنى للتفعيل"
        ],
        .generalTriggerThresholdHelp: [
            .english: "Number of characters before suggestions activate.",
            .arabic:  "عدد الحروف اللازمة قبل تفعيل الاقتراحات."
        ],
        .generalLanguage: [
            .english: "Interface language",
            .arabic:  "لغة الواجهة"
        ],
        .generalLanguageHelp: [
            .english: "Switch the QalamAI UI between English and Arabic.",
            .arabic:  "بدّل واجهة QalamAI بين العربية والإنجليزية."
        ],
        .generalMaxWords: [
            .english: "Suggestion length",
            .arabic:  "طول الاقتراح"
        ],
        .generalMaxWordsHelp: [
            .english: "How many words the model is allowed to predict at once. Smaller = more native predictive-text feel.",
            .arabic:  "عدد الكلمات التي يُسمَح للنموذج باقتراحها مرة واحدة. كلما قلّ العدد بدا الاقتراح أقرب لطريقة الكتابة التلقائية الأصلية."
        ],
        .generalMaxWordsValue: [
            .english: "words",
            .arabic:  "كلمات"
        ],
        .generalMaxWordsModelCap: [
            .english: "Max",
            .arabic:  "الحد الأقصى"
        ],
        .generalExcludedApps: [
            .english: "Excluded apps",
            .arabic:  "التطبيقات المستبعدة"
        ],

        // ━━━ Menu bar popover ━━━
        .popoverEnableSuggestions: [
            .english: "Enable suggestions",
            .arabic:  "تفعيل الاقتراحات"
        ],
        .popoverWritingMode: [
            .english: "WRITING MODE",
            .arabic:  "نمط الكتابة"
        ],
        .popoverActiveModel: [
            .english: "ACTIVE MODEL",
            .arabic:  "النموذج النشط"
        ],
        .popoverChange: [
            .english: "Change",
            .arabic:  "تغيير"
        ],
        .popoverTodaysStats: [
            .english: "TODAY'S STATS",
            .arabic:  "إحصائيات اليوم"
        ],
        .popoverWordsCompleted: [
            .english: "Words completed",
            .arabic:  "الكلمات المُكمَلة"
        ],
        .popoverKeystrokesSaved: [
            .english: "Keystrokes saved",
            .arabic:  "ضغطات لوحة المفاتيح الموفّرة"
        ],
        .popoverSuggestionsShown: [
            .english: "Suggestions shown",
            .arabic:  "الاقتراحات المعروضة"
        ],
        .popoverSettings: [
            .english: "Settings",
            .arabic:  "الإعدادات"
        ],
        .popoverQuit: [
            .english: "Quit QalamAI",
            .arabic:  "إنهاء QalamAI"
        ],
        .popoverAccessibilityRequired: [
            .english: "Accessibility access required",
            .arabic:  "صلاحية إمكانية الوصول مطلوبة"
        ],
        .popoverAccessibilityBody: [
            .english: "Autocomplete and Tab-to-accept won't work until you grant access. macOS resets this for every new build.",
            .arabic:  "لن يعمل الإكمال التلقائي وقبول الاقتراح بزر Tab حتى تمنح الصلاحية. يعيد macOS تعيين ذلك مع كل إصدار جديد."
        ],
        .popoverOpenAccessibility: [
            .english: "Open Accessibility Settings",
            .arabic:  "فتح إعدادات إمكانية الوصول"
        ],
        .popoverStatusActive:        [.english: "Active",         .arabic: "نشط"],
        .popoverStatusPaused:        [.english: "Paused",         .arabic: "متوقف مؤقتاً"],
        .popoverStatusStarting:      [.english: "Starting…",      .arabic: "جارٍ التشغيل…"],
        .popoverStatusStopped:       [.english: "Stopped",        .arabic: "متوقف"],
        .popoverStatusInstallOllama: [.english: "Install Ollama", .arabic: "تثبيت Ollama"],
        .popoverStatusChecking:      [.english: "Checking…",      .arabic: "جارٍ التحقق…"],
        .popoverStatusNeedsAccess:   [.english: "Needs access",   .arabic: "بحاجة لصلاحية"],

        .modelGoodForArabic: [
            .english: "Good for Arabic",
            .arabic:  "مناسب للعربية"
        ],

        // ━━━ Engine ━━━
        .generalEngine: [
            .english: "Inference engine",
            .arabic:  "محرّك الاستدلال"
        ],
        .generalEngineHelp: [
            .english: "Choose which on-device model generates suggestions.",
            .arabic:  "اختر النموذج المحلي الذي يولّد الاقتراحات."
        ],
        .engineOllama: [
            .english: "Local models",
            .arabic:  "النماذج المحلية"
        ],
        .engineAppleIntelligence: [
            .english: "Apple Intelligence",
            .arabic:  "Apple Intelligence"
        ],

        // ━━━ Context sources ━━━
        .generalContextSources: [
            .english: "Context sources",
            .arabic:  "مصادر السياق"
        ],
        .generalContextSourcesHelp: [
            .english: "Extra context makes completions more relevant. Everything stays on your Mac.",
            .arabic:  "السياق الإضافي يجعل الاقتراحات أكثر ملاءمة. يبقى كل شيء على جهازك."
        ],
        .ctxBroader: [
            .english: "Read nearby on-screen text",
            .arabic:  "قراءة النص المجاور على الشاشة"
        ],
        .ctxBroaderHelp: [
            .english: "Uses Accessibility to read surrounding text (e.g. the thread above a reply box). No extra permission.",
            .arabic:  "يستخدم إمكانية الوصول لقراءة النص المحيط (مثل المحادثة فوق صندوق الرد). لا يحتاج صلاحية إضافية."
        ],
        .ctxClipboard: [
            .english: "Use clipboard as context",
            .arabic:  "استخدام الحافظة كسياق"
        ],
        .ctxClipboardHelp: [
            .english: "Feeds recent clipboard text to the model. Off by default for privacy.",
            .arabic:  "يُمرّر نص الحافظة الأخير إلى النموذج. مُعطّل افتراضياً للخصوصية."
        ],
        .ctxScreen: [
            .english: "Read screen near cursor (OCR)",
            .arabic:  "قراءة الشاشة قرب المؤشر (OCR)"
        ],
        .ctxScreenHelp: [
            .english: "Captures and reads text around your cursor for apps that don't expose it. Requires Screen Recording permission.",
            .arabic:  "يلتقط ويقرأ النص حول المؤشر للتطبيقات التي لا تُتيحه. يتطلب صلاحية تسجيل الشاشة."
        ],
        .ctxScreenGrant: [
            .english: "Grant Screen Recording",
            .arabic:  "منح صلاحية تسجيل الشاشة"
        ],

        // ━━━ Modes tab ━━━
        .modesHeading:    [.english: "Writing Modes", .arabic: "أنماط الكتابة"],
        .modesBuiltIn:    [.english: "BUILT-IN", .arabic: "جاهزة"],
        .modesCustom:     [.english: "Custom modes", .arabic: "أنماط مخصّصة"],
        .modesCustomHelp: [
            .english: "Define your own voice — for example, \"Translate to French\" or \"Make it shorter\".",
            .arabic:  "عرّف أسلوبك الخاص — مثل «ترجم إلى الفرنسية» أو «اجعله أقصر»."
        ],
        .modesNewMode:      [.english: "New mode", .arabic: "نمط جديد"],
        .modesNoCustom:     [.english: "No custom modes yet.", .arabic: "لا توجد أنماط مخصّصة بعد."],
        .modesNewModeTitle: [.english: "New writing mode", .arabic: "نمط كتابة جديد"],
        .modesName:         [.english: "Name", .arabic: "الاسم"],
        .modesInstruction:  [.english: "Instruction", .arabic: "التعليمات"],
        .modesTemperature:  [.english: "Temperature", .arabic: "درجة الإبداع"],
        .commonCancel:      [.english: "Cancel", .arabic: "إلغاء"],
        .commonCreate:      [.english: "Create", .arabic: "إنشاء"],
        .commonDelete:      [.english: "Delete", .arabic: "حذف"],
        .commonUse:         [.english: "Use", .arabic: "استخدام"],

        // ━━━ Snippets tab ━━━
        .snippetsHeading: [.english: "Snippets", .arabic: "المختصرات"],
        .snippetsSubheading: [
            .english: "Short triggers that expand into longer text. Type ':trigger' anywhere and press Tab.",
            .arabic:  "اختصارات قصيرة تتوسّع إلى نص أطول. اكتب «:trigger» في أي مكان واضغط Tab."
        ],
        .snippetsHowTitle:  [.english: "How it works", .arabic: "كيف يعمل"],
        .snippetsNewTitle:  [.english: "New snippet", .arabic: "مختصر جديد"],
        .snippetsExpansion: [.english: "Expansion", .arabic: "النص الموسّع"],
        .snippetsAdd:       [.english: "Add Snippet", .arabic: "إضافة مختصر"],
        .snippetsYours:     [.english: "Your snippets", .arabic: "مختصراتك"],
        .snippetsNone:      [.english: "No snippets yet.", .arabic: "لا توجد مختصرات بعد."],

        // ━━━ Shortcuts tab ━━━
        .shortcutsHeading: [.english: "Shortcuts", .arabic: "الاختصارات"],
        .shortcutsSubheading: [
            .english: "Keys that interact with suggestions and QalamAI itself.",
            .arabic:  "المفاتيح التي تتفاعل مع الاقتراحات ومع QalamAI نفسه."
        ],
        .shortcutAcceptWord: [.english: "Accept next word", .arabic: "قبول الكلمة التالية"],
        .shortcutDismiss:    [.english: "Dismiss suggestion", .arabic: "تجاهل الاقتراح"],
        .shortcutPauseResume:[.english: "Pause / Resume", .arabic: "إيقاف مؤقت / استئناف"],
        .shortcutPauseHelp:  [
            .english: "Toggle QalamAI without leaving your keyboard.",
            .arabic:  "تبديل تشغيل QalamAI دون مغادرة لوحة المفاتيح."
        ],

        // ━━━ Privacy tab ━━━
        .privacyHeading: [.english: "Privacy", .arabic: "الخصوصية"],
        .privacySubheading: [
            .english: "All processing is local. Your text never leaves your Mac.",
            .arabic:  "كل المعالجة محلية. لا يغادر نصّك جهازك أبداً."
        ],
        .privacyLast7Days:   [.english: "Last 7 days", .arabic: "آخر ٧ أيام"],
        .privacyLocalTitle:  [.english: "Local-first by design", .arabic: "محلي أولاً بالتصميم"],
        .privacyWordsToday:  [.english: "Words completed today", .arabic: "الكلمات المُكمَلة اليوم"],
        .privacyStyleEntries:[.english: "Style context entries", .arabic: "مدخلات سياق الأسلوب"],
        .privacyClearStyle:  [.english: "Clear Style History", .arabic: "مسح سجل الأسلوب"],
        .privacyResetStats:  [.english: "Reset Statistics", .arabic: "إعادة تعيين الإحصائيات"],

        // ━━━ Models tab ━━━
        .modelsSelectPrompt: [
            .english: "Select a model to view details",
            .arabic:  "اختر نموذجاً لعرض التفاصيل"
        ],
        .modelsDownload:  [.english: "Download Model", .arabic: "تنزيل النموذج"],
        .modelsUseThis:   [.english: "Use This Model", .arabic: "استخدام هذا النموذج"],
        .modelsBrowseAll: [.english: "Browse all", .arabic: "تصفّح الكل"],
        .modelsSearch:    [.english: "Search models", .arabic: "بحث في النماذج"],
        .popoverCompatibility: [
            .english: "COMPATIBILITY",
            .arabic:  "التوافق مع التطبيقات"
        ],
        .popoverCompatibilityWorks: [
            .english: "Works in: Mail, Notes, Safari, Chrome, Word, Notion, Obsidian, Messages, most text fields.",
            .arabic:  "يعمل في: البريد، الملاحظات، Safari، Chrome، Word، Notion، Obsidian، الرسائل، ومعظم حقول النص."
        ],
        .popoverCompatibilityToggle: [
            .english: "Needs a toggle: Google Docs (turn on Accessibility mode), Arc/Dia (enable a setting).",
            .arabic:  "يحتاج إلى تفعيل يدوي: Google Docs (وضع إمكانية الوصول)، Arc/Dia (إعداد خاص بالمتصفح)."
        ],
        .popoverCompatibilityLimited: [
            .english: "Limited: VS Code/Cursor main editor uses canvas text — only sidebar chats work.",
            .arabic:  "محدود: محرر VS Code/Cursor الرئيسي يستخدم رسماً مخصصاً — يعمل فقط في الشريط الجانبي."
        ],
        // ━━━ Snooze ━━━
        .popoverSnooze: [ .english: "Snooze", .arabic: "إيقاف مؤقت" ],
        .popoverSnoozeResume: [ .english: "Resume", .arabic: "استئناف" ],
        .popoverSnooze30m: [ .english: "30 min", .arabic: "٣٠ دقيقة" ],
        .popoverSnooze1h: [ .english: "1 hour", .arabic: "ساعة" ],
        .popoverSnoozeTomorrow: [ .english: "Tomorrow", .arabic: "حتى الغد" ],
        .popoverSnoozedUntil: [ .english: "Paused until", .arabic: "متوقف حتى" ],
        // ━━━ Accept key / hint ━━━
        .generalAcceptKey: [ .english: "Accept key", .arabic: "مفتاح القبول" ],
        .generalAcceptKeyTab: [ .english: "Tab ⇥", .arabic: "Tab ⇥" ],
        .generalAcceptKeyArrow: [ .english: "Right Arrow →", .arabic: "السهم الأيمن →" ],
        .generalShowAcceptHint: [ .english: "Show accept hint", .arabic: "إظهار تلميح القبول" ],
        .generalShowAcceptHintHelp: [
            .english: "Display a faint key badge after the suggestion so you remember which key accepts it.",
            .arabic:  "إظهار شارة خافتة للمفتاح بعد الاقتراح لتذكّر المفتاح الذي يقبله."
        ],
        // ━━━ Custom model import ━━━
        .modelsAddCustom: [ .english: "Add a custom model", .arabic: "إضافة نموذج مخصص" ],
        .modelsAddCustomTitle: [ .english: "Custom Ollama model", .arabic: "نموذج Ollama مخصص" ],
        .modelsAddCustomHelp: [
            .english: "Enter any Ollama tag (e.g. \"llama3.2:3b\"). It will appear in your model list to install and use.",
            .arabic:  "أدخل أي وسم Ollama (مثل \"llama3.2:3b\"). سيظهر في قائمة النماذج لتثبيته واستخدامه."
        ],
        .modelsAddCustomPlaceholder: [ .english: "model:tag", .arabic: "model:tag" ],
        .modelsAddCustomButton: [ .english: "Add", .arabic: "إضافة" ],
        .modelsCustomBadge: [ .english: "Custom", .arabic: "مخصص" ],
        // ━━━ Diagnostics ━━━
        .diagnosticsTitle: [ .english: "Diagnostics", .arabic: "التشخيص" ],
        .diagnosticsHelp: [
            .english: "A snapshot of app state to help troubleshoot. No text you've typed is included.",
            .arabic:  "لقطة لحالة التطبيق للمساعدة في حل المشكلات. لا تتضمن أي نص كتبته."
        ],
        .diagnosticsCopy: [ .english: "Copy diagnostics", .arabic: "نسخ التشخيص" ],
        .diagnosticsCopied: [ .english: "Copied", .arabic: "تم النسخ" ],
        // ━━━ Appearance ━━━
        .generalAppearance: [ .english: "Appearance", .arabic: "المظهر" ],
        .generalAppearanceSystem: [ .english: "System", .arabic: "النظام" ],
        .generalAppearanceLight: [ .english: "Light", .arabic: "فاتح" ],
        .generalAppearanceDark: [ .english: "Dark", .arabic: "داكن" ],
        // ━━━ Ghost calibration ━━━
        .generalGhostCalibration: [
            .english: "Inline suggestion calibration",
            .arabic:  "ضبط الاقتراح ضمن السطر"
        ],
        .generalGhostCalibrationHelp: [
            .english: "Fine-tune the ghost text's size and vertical position. Most apps need no change; use this for apps like Notes that report an inaccurate cursor size, so the suggestion lands on the line.",
            .arabic:  "اضبط حجم النص الشبحي وموضعه العمودي. معظم التطبيقات لا تحتاج لتغيير؛ استخدم هذا مع تطبيقات مثل الملاحظات التي تُبلّغ عن حجم مؤشر غير دقيق، ليظهر الاقتراح على السطر."
        ],
        .generalGhostSize: [ .english: "Size", .arabic: "الحجم" ],
        .generalGhostVOffset: [ .english: "Vertical", .arabic: "عمودي" ],
        .generalGhostReset: [ .english: "Reset", .arabic: "إعادة تعيين" ],
        // ━━━ In-app update install ━━━
        .updateInstall: [ .english: "Download & Install", .arabic: "تنزيل وتثبيت" ],
        .updateDownloading: [ .english: "Downloading…", .arabic: "جارٍ التنزيل…" ],
        .updateOpening: [ .english: "Opening installer…", .arabic: "فتح المثبّت…" ],
        .updateReady: [ .english: "Ready — drag to Applications", .arabic: "جاهز — اسحب إلى التطبيقات" ],
        // ━━━ Tone rewrite ━━━
        .rewriteTitle: [ .english: "Rewrite selection", .arabic: "إعادة صياغة المحدّد" ],
        .rewriteWorking: [ .english: "Rewriting", .arabic: "جارٍ إعادة الصياغة" ],
        .rewriteFailed: [ .english: "Rewrite failed", .arabic: "تعذّرت إعادة الصياغة" ],
        .rewriteToneFormal: [ .english: "Formal", .arabic: "رسمي" ],
        .rewriteToneCasual: [ .english: "Casual", .arabic: "ودّي" ],
        .rewriteToneConcise: [ .english: "Concise", .arabic: "موجز" ],
        .rewriteToneExpand: [ .english: "Expand", .arabic: "توسيع" ],
        .rewriteToneGrammar: [ .english: "Fix grammar", .arabic: "تصحيح القواعد" ],
        // ━━━ v1.4 T1 stability ━━━
        .popoverSecureInputPaused: [
            .english: "Paused while Secure Input is on",
            .arabic:  "متوقف مؤقتاً أثناء تفعيل الإدخال الآمن"
        ],
        .popoverSecureInputHelp: [
            .english: "A password field or another app has turned on Secure Input. Suggestions resume automatically.",
            .arabic:  "فعّل حقل كلمة مرور أو تطبيق آخر الإدخال الآمن. ستُستأنف الاقتراحات تلقائياً."
        ],
        .popoverStatusRestarting: [ .english: "Restarting engine…", .arabic: "جارٍ إعادة تشغيل المحرك…" ],
        .popoverStatusEngineFailed: [ .english: "Engine stopped", .arabic: "توقف المحرك" ],
        .popoverEngineFailedHelp: [
            .english: "The local engine kept stopping, so automatic restarts are paused.",
            .arabic:  "توقف المحرك المحلي مراراً، لذا أُوقفت إعادة التشغيل التلقائية مؤقتاً."
        ],
        .popoverEngineRetry: [ .english: "Retry", .arabic: "إعادة المحاولة" ],
        .rewriteTimedOut: [
            .english: "The model didn't respond in time. Try again.",
            .arabic:  "لم يستجب النموذج في الوقت المحدد. حاول مجدداً."
        ],
        // ━━━ v1.4 T2 diagnostics ━━━
        .diagShowLogs: [ .english: "Show log files", .arabic: "عرض ملفات السجل" ],
        // ━━━ v1.4 T3 apps & profiles ━━━
        .tabApps: [ .english: "Apps", .arabic: "التطبيقات" ],
        .appsHeading: [ .english: "Apps & Websites", .arabic: "التطبيقات والمواقع" ],
        .appsSubheading: [
            .english: "Choose how QalamAI works in each app or website. Anything set to Inherit follows your global settings.",
            .arabic:  "اختر طريقة عمل QalamAI في كل تطبيق أو موقع. كل ما يُترك على «افتراضي» يتبع إعداداتك العامة."
        ],
        .appsAddFrontmostFmt: [ .english: "Add %@", .arabic: "إضافة %@" ],
        .appsAddFrontmost: [ .english: "Add frontmost app", .arabic: "إضافة التطبيق النشط" ],
        .appsAddRunning: [ .english: "Add running app", .arabic: "إضافة تطبيق مفتوح" ],
        .appsAddWebsite: [ .english: "Add website", .arabic: "إضافة موقع" ],
        .appsWebsitePlaceholder: [ .english: "example.com", .arabic: "example.com" ],
        .appsWebsiteInvalid: [
            .english: "Enter a website address like example.com.",
            .arabic:  "أدخل عنوان موقع مثل example.com."
        ],
        .appsAddHelp: [
            .english: "Apps show up here once you type in them. Websites are recognised in Safari, Chrome, Edge, Brave, Arc and other browsers; a website's settings also apply to its subdomains.",
            .arabic:  "تظهر التطبيقات هنا بمجرد الكتابة فيها. تُكتشف المواقع في Safari وChrome وEdge وBrave وArc وغيرها من المتصفحات، وتنطبق إعدادات الموقع على نطاقاته الفرعية أيضاً."
        ],
        .appsConfigured: [ .english: "With custom settings", .arabic: "بإعدادات مخصّصة" ],
        .appsConfiguredEmpty: [
            .english: "Nothing customized yet — every app and website uses your global settings.",
            .arabic:  "لا توجد تخصيصات بعد — كل التطبيقات والمواقع تستخدم إعداداتك العامة."
        ],
        .appsRecent: [ .english: "Recently seen", .arabic: "شوهدت مؤخراً" ],
        .appsRecentEmpty: [
            .english: "Apps and websites you type in will appear here.",
            .arabic:  "ستظهر هنا التطبيقات والمواقع التي تكتب فيها."
        ],
        .appsShowAllFmt: [ .english: "Show all (%d)", .arabic: "عرض الكل (%d)" ],
        .appsShowFewer: [ .english: "Show fewer", .arabic: "عرض أقل" ],
        .appsRecentSitesHelp: [
            .english: "Recently seen websites are kept in memory only and forgotten when QalamAI quits. A website is saved only after you change one of its settings.",
            .arabic:  "تُحفظ المواقع التي شوهدت مؤخراً في الذاكرة فقط وتُنسى عند إغلاق QalamAI. لا يُحفظ الموقع إلا بعد تغيير أحد إعداداته."
        ],
        .appsWebsite: [ .english: "Website", .arabic: "موقع ويب" ],
        .appsCustomized: [ .english: "Custom", .arabic: "مخصّص" ],
        .appsSelectPrompt: [
            .english: "Select an app or website above to change its settings.",
            .arabic:  "اختر تطبيقاً أو موقعاً أعلاه لتغيير إعداداته."
        ],
        .appsActivation: [ .english: "Suggestions", .arabic: "الاقتراحات" ],
        .appsActivationInherit: [ .english: "Inherit", .arabic: "افتراضي" ],
        .appsActivationAlwaysOn: [ .english: "Always on", .arabic: "مفعّلة دائماً" ],
        .appsActivationForceOnly: [ .english: "Force only", .arabic: "عند الطلب فقط" ],
        .appsActivationOff: [ .english: "Off", .arabic: "متوقفة" ],
        .appsActivationHelp: [
            .english: "Always on skips the automatic idle rules (search boxes, narrow fields). Force only waits for ⌃ + the key above Tab. A website inherits its browser's setting.",
            .arabic:  "«مفعّلة دائماً» تتجاوز قواعد الإيقاف التلقائي (مربعات البحث والحقول الضيقة). «عند الطلب فقط» تنتظر ⌃ + المفتاح فوق Tab. يرث الموقع إعداد متصفحه."
        ],
        .appsWritingMode: [ .english: "Writing mode", .arabic: "نمط الكتابة" ],
        .appsInherit: [ .english: "Inherit", .arabic: "افتراضي" ],
        .appsInheritValueFmt: [ .english: "Inherit (%@)", .arabic: "افتراضي (%@)" ],
        .appsLanguage: [ .english: "Language", .arabic: "اللغة" ],
        .appsLanguageAuto: [ .english: "Automatic", .arabic: "تلقائي" ],
        .appsLanguageEnglish: [ .english: "English only", .arabic: "الإنجليزية فقط" ],
        .appsLanguageArabic: [ .english: "Arabic only", .arabic: "العربية فقط" ],
        .appsLanguageHelp: [
            .english: "Only suggest when you're typing in this language.",
            .arabic:  "لا تقترح إلا عند الكتابة بهذه اللغة."
        ],
        .appsAutocorrect: [ .english: "Corrections", .arabic: "التصحيحات" ],
        .appsAutocorrectHelp: [
            .english: "Spelling and grammar fixes offered as suggestions. Inherit follows the General tab.",
            .arabic:  "إصلاحات الإملاء والقواعد المعروضة كاقتراحات. «افتراضي» يتبع تبويب «عام»."
        ],
        .appsOn: [ .english: "On", .arabic: "تشغيل" ],
        .appsOff: [ .english: "Off", .arabic: "إيقاف" ],
        .appsInstructions: [ .english: "Custom instructions", .arabic: "تعليمات مخصّصة" ],
        .appsInstructionsHelp: [
            .english: "Added after your global instructions (My Info) for this app or website.",
            .arabic:  "تُضاف بعد تعليماتك العامة (معلوماتي) لهذا التطبيق أو الموقع."
        ],
        .appsInstructionsPlaceholder: [
            .english: "e.g. Reply briefly and casually.",
            .arabic:  "مثال: ردّ باختصار وبأسلوب ودّي."
        ],
        .appsReset: [ .english: "Reset to inherit", .arabic: "إعادة إلى الافتراضي" ],
        .appsRemove: [ .english: "Remove", .arabic: "إزالة" ],
        .appsOpen: [ .english: "Open Apps", .arabic: "فتح التطبيقات" ],
        .appsManageHint: [
            .english: "Exclusions and per-app settings now live in the Apps tab.",
            .arabic:  "الاستبعادات وإعدادات كل تطبيق أصبحت في تبويب «التطبيقات»."
        ],
        .myInfoInstructionsTitle: [
            .english: "Custom AI instructions",
            .arabic:  "تعليمات مخصّصة للذكاء الاصطناعي"
        ],
        .myInfoInstructionsHelp: [
            .english: "Tell QalamAI about yourself or how you write. Added to every suggestion request; stays on this Mac.",
            .arabic:  "أخبر QalamAI عن نفسك أو عن أسلوب كتابتك. تُضاف إلى كل طلب اقتراح وتبقى على هذا الجهاز."
        ],
        .myInfoInstructionsPlaceholder: [
            .english: "e.g. I'm a product manager. Keep suggestions clear and friendly.",
            .arabic:  "مثال: أنا مدير منتجات. اجعل الاقتراحات واضحة وودية."
        ],
        .popoverSuggestInAppFmt: [ .english: "Suggest in %@", .arabic: "الاقتراح في %@" ],
        .popoverSuggestOnSiteFmt: [ .english: "Suggest on %@", .arabic: "الاقتراح على %@" ],
        .popoverAppPausedFmt: [ .english: "Paused in %@ · %d min left", .arabic: "متوقف مؤقتاً في %@ · بقي %d د" ],
        // ━━━ v1.4 T4 shortcuts & activation ━━━
        .shortcutCardVisible: [
            .english: "While a suggestion is visible",
            .arabic:  "أثناء ظهور اقتراح"
        ],
        .shortcutCardAnywhere: [ .english: "Anywhere", .arabic: "في أي مكان" ],
        .shortcutCardEsc: [ .english: "The Esc key", .arabic: "مفتاح Esc" ],
        .shortcutAcceptWordHelp: [
            .english: "Inserts the next word of the suggestion.",
            .arabic:  "يُدرج الكلمة التالية من الاقتراح."
        ],
        .shortcutTabPassNote: [
            .english: "In apps set to “Tab passes through” in the Apps tab, → accepts instead.",
            .arabic:  "في التطبيقات المضبوطة على «تمرير Tab» في تبويب «التطبيقات»، يقبل مفتاح → بدلاً منه."
        ],
        .shortcutAcceptAll: [ .english: "Accept the whole suggestion", .arabic: "قبول الاقتراح كاملاً" ],
        .shortcutAcceptAllHelp: [
            .english: "Inserts everything that is showing.",
            .arabic:  "يُدرج كل ما هو معروض."
        ],
        .shortcutRealTab: [ .english: "Insert a real Tab", .arabic: "إدراج Tab فعلي" ],
        .shortcutRealTabHelp: [
            .english: "Sends a normal Tab to the app instead of accepting the suggestion.",
            .arabic:  "يرسل Tab عادياً إلى التطبيق بدل قبول الاقتراح."
        ],
        .shortcutDismissHelp: [
            .english: "Hides the suggestion. Esc reaches the app only with the last option below.",
            .arabic:  "يُخفي الاقتراح. لا يصل Esc إلى التطبيق إلا مع الخيار الأخير أدناه."
        ],
        .shortcutRegenerate: [ .english: "Show a different suggestion", .arabic: "عرض اقتراح مختلف" ],
        .shortcutRegenerateHelp: [
            .english: "Asks the model for another completion for the same text.",
            .arabic:  "يطلب من النموذج إكمالاً آخر للنص نفسه."
        ],
        .shortcutForceActivate: [ .english: "Suggest now", .arabic: "اقترح الآن" ],
        .shortcutForceActivateHelp: [
            .english: "Asks for a suggestion in the current field right away — including search boxes, narrow fields and apps set to Force only. Never in password fields or apps set to Off.",
            .arabic:  "يطلب اقتراحاً في الحقل الحالي فوراً — بما في ذلك مربعات البحث والحقول الضيقة والتطبيقات المضبوطة على «عند الطلب فقط». لا يعمل أبداً في حقول كلمات المرور أو التطبيقات المتوقفة."
        ],
        .shortcutForceEditorsHelp: [
            .english: "In VS Code, Cursor, Windsurf and Zed this key keeps toggling the editor's terminal, unless you set that editor to Force only in the Apps tab.",
            .arabic:  "في VS Code وCursor وWindsurf وZed يظل هذا المفتاح يفتح طرفية المحرّر، إلا إذا ضبطت المحرّر على «عند الطلب فقط» في تبويب «التطبيقات»."
        ],
        .shortcutAppToggle: [
            .english: "Pause in this app for 10 minutes",
            .arabic:  "إيقاف مؤقت في هذا التطبيق ١٠ دقائق"
        ],
        .shortcutAppToggleHelp: [
            .english: "Press it again to resume. The menu bar shows how long is left.",
            .arabic:  "اضغطه مجدداً للاستئناف. تعرض شريط القوائم الوقت المتبقي."
        ],
        .shortcutRewrite: [ .english: "Rewrite the selected text", .arabic: "إعادة صياغة النص المحدد" ],
        .shortcutRewriteHelp: [
            .english: "Select some text, then pick a tone: formal, casual, concise…",
            .arabic:  "حدّد نصاً ثم اختر النبرة: رسمي أو ودّي أو موجز…"
        ],
        .shortcutEditorsPassHelp: [
            .english: "In VS Code, Cursor, Windsurf and Zed these keys keep their editor meaning.",
            .arabic:  "في VS Code وCursor وWindsurf وZed تحتفظ هذه المفاتيح بوظيفتها في المحرّر."
        ],
        .shortcutKeyAboveTab: [ .english: "key above Tab", .arabic: "المفتاح فوق Tab" ],
        .shortcutKeyAboveTabHelp: [
            .english: "On the Arabic layout this key types ذ — QalamAI only ever uses it together with ⌃, so typing ذ is never affected. On keyboards with a § key, the key next to left Shift works too.",
            .arabic:  "على التخطيط العربي يكتب هذا المفتاح حرف ذ — ولا يستخدمه QalamAI إلا مع ⌃، فلا تتأثر كتابة ذ أبداً. على لوحات المفاتيح التي فيها مفتاح §، يعمل أيضاً المفتاح المجاور لـ Shift الأيسر."
        ],
        .shortcutEscDismiss: [ .english: "Dismiss only", .arabic: "إخفاء الاقتراح فقط" ],
        .shortcutEscDismissPause: [
            .english: "Dismiss and pause this field for 15 seconds",
            .arabic:  "إخفاء الاقتراح وإيقاف هذا الحقل ١٥ ثانية"
        ],
        .shortcutEscPass: [ .english: "Pass Esc to the app", .arabic: "تمرير Esc إلى التطبيق" ],
        .shortcutEscHelp: [
            .english: "Esc is only intercepted while a suggestion is visible. “Pass Esc to the app” hides the suggestion and lets the app see Esc as well.",
            .arabic:  "لا يُعترض Esc إلا أثناء ظهور اقتراح. خيار «تمرير Esc إلى التطبيق» يُخفي الاقتراح ويترك التطبيق يستقبل Esc أيضاً."
        ],
        .toastPaused: [ .english: "QalamAI paused", .arabic: "تم إيقاف QalamAI مؤقتاً" ],
        .toastResumed: [ .english: "QalamAI resumed", .arabic: "تم استئناف QalamAI" ],
        .toastPausedAppFmt: [
            .english: "Paused in %@ for 10 minutes",
            .arabic:  "متوقف مؤقتاً في %@ لمدة ١٠ دقائق"
        ],
        .toastResumedAppFmt: [ .english: "Resumed in %@", .arabic: "تم الاستئناف في %@" ],
        .toastNoField: [
            .english: "No text field to suggest in",
            .arabic:  "لا يوجد حقل نص للاقتراح فيه"
        ],
        .toastForceBlocked: [
            .english: "Suggestions are off here",
            .arabic:  "الاقتراحات متوقفة هنا"
        ],
        .appsTabAccept: [ .english: "Tab key", .arabic: "مفتاح Tab" ],
        .appsTabAcceptOn: [ .english: "Tab accepts", .arabic: "Tab يقبل" ],
        .appsTabAcceptOff: [ .english: "Tab passes through", .arabic: "تمرير Tab" ],
        .appsTabAcceptHelp: [
            .english: "When Tab passes through, → accepts the next word and ⇧→ accepts the whole suggestion. The hint on the suggestion may still show ⇥.",
            .arabic:  "عند تمرير Tab، يقبل مفتاح → الكلمة التالية ويقبل ⇧→ الاقتراح كاملاً. قد يظل التلميح على الاقتراح يعرض ⇥."
        ],

        // ━━━ v1.4 T5 mirror bubble, compatibility, field button ━━━
        .appsDisplay: [ .english: "Where suggestions appear", .arabic: "مكان ظهور الاقتراحات" ],
        .appsDisplayInline: [ .english: "At the cursor", .arabic: "عند المؤشر" ],
        .appsDisplayMirror: [ .english: "Bubble", .arabic: "فقاعة" ],
        .appsDisplayHelp: [
            .english: "“Bubble” shows the suggestion in a small box above the text field — use it for apps where the text at the cursor lands in the wrong place.",
            .arabic:  "يعرض خيار «فقاعة» الاقتراح في مربع صغير فوق حقل النص — استخدمه في التطبيقات التي يظهر فيها النص عند المؤشر في مكان خاطئ."
        ],
        .appsCompat: [ .english: "Improve compatibility", .arabic: "تحسين التوافق" ],
        .appsCompatElectron: [ .english: "Electron", .arabic: "Electron" ],
        .appsCompatHelp: [
            .english: "For apps built with Electron (Slack, Discord, Notion…). Turns on the app's accessibility support so QalamAI can read what you type. Takes effect immediately; turning it off takes effect after the app restarts. In code editors this can switch them into screen-reader mode, so it is never turned on there by itself.",
            .arabic:  "للتطبيقات المبنية بـ Electron (مثل Slack وDiscord وNotion). يُفعّل دعم إمكانية الوصول في التطبيق ليتمكن QalamAI من قراءة ما تكتبه. يسري فوراً، أما إيقافه فيسري بعد إعادة تشغيل التطبيق. في محررات الأكواد قد يُحوّلها إلى وضع قارئ الشاشة، لذا لا يُفعَّل فيها تلقائياً."
        ],
        .generalDisplay: [ .english: "Display", .arabic: "العرض" ],
        .generalCaretUnavailable: [
            .english: "When the cursor position is unavailable",
            .arabic:  "عندما يتعذر تحديد موضع المؤشر"
        ],
        .generalCaretUnavailableBubble: [ .english: "Show bubble", .arabic: "عرض فقاعة" ],
        .generalCaretUnavailableHide: [ .english: "Hide suggestion", .arabic: "إخفاء الاقتراح" ],
        .generalCaretUnavailableHelp: [
            .english: "Some apps don't report where the cursor is. QalamAI can then show the suggestion in a small bubble above the text field instead — the same keys accept or dismiss it.",
            .arabic:  "بعض التطبيقات لا تُبلغ عن موضع المؤشر. عندها يمكن لـ QalamAI عرض الاقتراح في فقاعة صغيرة فوق حقل النص — وتقبله أو تُخفيه المفاتيح نفسها."
        ],
        .generalFieldButton: [
            .english: "Show a QalamAI button next to text fields",
            .arabic:  "إظهار زر QalamAI بجانب حقول النص"
        ],
        .generalFieldButtonHelp: [
            .english: "A small badge at the corner of the field you are typing in. Click it to turn QalamAI off in that app, pause it, or open its settings. It hides while you type and while a suggestion is showing.",
            .arabic:  "شارة صغيرة عند زاوية الحقل الذي تكتب فيه. انقرها لإيقاف QalamAI في ذلك التطبيق أو تعليقه أو فتح إعداداته. تختفي أثناء الكتابة وأثناء ظهور اقتراح."
        ],
        .fieldButtonDisableFmt: [ .english: "Turn off in %@", .arabic: "إيقاف في %@" ],
        .fieldButtonEnableFmt: [ .english: "Turn on in %@", .arabic: "تشغيل في %@" ],
        .fieldButtonPause10: [ .english: "Pause for 10 minutes", .arabic: "تعليق لمدة ١٠ دقائق" ],
        .fieldButtonSettings: [ .english: "Settings for this app…", .arabic: "إعدادات هذا التطبيق…" ],

        // ━━━ v1.4 T6 personalization ━━━
        .tabPersonalization: [ .english: "Personalization", .arabic: "التخصيص" ],
        .personaHeading: [ .english: "Learn how you write", .arabic: "تعلَّم أسلوب كتابتك" ],
        .personaSubheading: [
            .english: "QalamAI can keep a private, encrypted copy of your own writing on this Mac and use it to make suggestions sound like you.",
            .arabic:  "يمكن لـ QalamAI حفظ نسخة خاصة ومشفَّرة من كتابتك على هذا الماك واستخدامها لجعل الاقتراحات تشبه أسلوبك."
        ],
        .personaRecord: [ .english: "Learn from my writing", .arabic: "التعلّم من كتابتي" ],
        .personaRecordHelp: [
            .english: "Off by default. What you write is encrypted and stored only on this Mac — it is never sent anywhere. Password fields, anything typed while secure input is on, apps and sites you turned QalamAI off in, and short pieces of text are never saved. Terminals are off unless you turn them on.",
            .arabic:  "مُعطَّل افتراضياً. ما تكتبه يُشفَّر ويُحفظ على هذا الماك فقط ولا يُرسل إلى أي مكان. لا تُحفظ حقول كلمات المرور، ولا ما يُكتب أثناء تفعيل الإدخال الآمن، ولا التطبيقات والمواقع التي أوقفت QalamAI فيها، ولا النصوص القصيرة. الطرفية مُعطَّلة ما لم تُفعّلها بنفسك."
        ],
        .personaMode: [ .english: "What to keep", .arabic: "ما الذي يُحفظ" ],
        .personaModeAccepted: [
            .english: "Only text where I accepted a suggestion",
            .arabic:  "النص الذي قبِلتُ فيه اقتراحاً فقط"
        ],
        .personaModeEverything: [
            .english: "Everything I type in monitored fields",
            .arabic:  "كل ما أكتبه في الحقول المشمولة"
        ],
        .personaModeHelp: [
            .english: "The first option keeps far less, and only from places you already use QalamAI in.",
            .arabic:  "الخيار الأول يحفظ أقل بكثير، ومن الأماكن التي تستخدم فيها QalamAI فعلاً فقط."
        ],
        .personaStrength: [ .english: "How much to use", .arabic: "مقدار الاستخدام" ],
        .personaStrengthOff: [ .english: "Off", .arabic: "إيقاف" ],
        .personaStrengthLow: [ .english: "Low", .arabic: "منخفض" ],
        .personaStrengthMedium: [ .english: "Medium", .arabic: "متوسط" ],
        .personaStrengthStrong: [ .english: "Strong", .arabic: "قوي" ],
        .personaStrengthHelp: [
            .english: "How many short excerpts of your writing are added to each request. Stronger means more of your style, and a slightly slower suggestion.",
            .arabic:  "عدد المقتطفات القصيرة من كتابتك التي تُضاف إلى كل طلب. كلما زاد المقدار ظهر أسلوبك أكثر وصار الاقتراح أبطأ قليلاً."
        ],
        .personaSamples: [ .english: "Saved writing", .arabic: "الكتابة المحفوظة" ],
        .personaSamplesHelp: [
            .english: "Counted per app. Older pieces are removed automatically once the store is full.",
            .arabic:  "العدد لكل تطبيق. تُحذف القطع الأقدم تلقائياً عند امتلاء المخزن."
        ],
        .personaSamplesEmpty: [ .english: "Nothing saved yet.", .arabic: "لا يوجد شيء محفوظ بعد." ],
        .personaSampleCountFmt: [ .english: "%d pieces", .arabic: "%d قطعة" ],
        .personaDelete: [ .english: "Delete", .arabic: "حذف" ],
        .personaDeleteAll: [ .english: "Delete all saved writing…", .arabic: "حذف كل الكتابة المحفوظة…" ],
        .personaDeleteAllTitle: [ .english: "Delete all saved writing?", .arabic: "حذف كل الكتابة المحفوظة؟" ],
        .personaDeleteAllConfirm: [
            .english: "Everything QalamAI learned from your writing is removed from this Mac. This can't be undone.",
            .arabic:  "سيُحذف كل ما تعلّمه QalamAI من كتابتك من هذا الماك. لا يمكن التراجع عن ذلك."
        ],
        .personaPrivacy: [
            .english: "Stored encrypted (AES-GCM) in your Application Support folder, with the key in your login keychain. Nothing is uploaded, and none of it appears in logs or diagnostics.",
            .arabic:  "يُحفظ مشفَّراً (AES-GCM) في مجلد Application Support، ويُحفظ المفتاح في سلسلة مفاتيح تسجيل الدخول. لا يُرفع أي شيء ولا يظهر منه شيء في السجلات أو التشخيص."
        ],
        .personaUnavailable: [
            .english: "The encryption key couldn't be read from your keychain, so saved writing is unavailable in this session. Nothing was deleted; unlock your login keychain and reopen QalamAI.",
            .arabic:  "تعذّرت قراءة مفتاح التشفير من سلسلة المفاتيح، لذا الكتابة المحفوظة غير متاحة في هذه الجلسة. لم يُحذف شيء؛ افتح قفل سلسلة مفاتيح تسجيل الدخول ثم أعد فتح QalamAI."
        ],
        .appsRecord: [ .english: "Learn from my writing", .arabic: "التعلّم من كتابتي" ],
        .appsRecordHelp: [
            .english: "Whether writing in this app may be saved for personalization. Terminals are off unless you turn them on. Nothing is saved while the main switch in Personalization is off.",
            .arabic:  "ما إذا كان يُسمح بحفظ الكتابة في هذا التطبيق للتخصيص. الطرفية مُعطَّلة ما لم تُفعّلها. لا يُحفظ شيء ما دام المفتاح الرئيسي في «التخصيص» مُعطَّلاً."
        ],
        .appsRecordSamplesFmt: [ .english: "%d pieces saved", .arabic: "%d قطعة محفوظة" ],
        .appsRecordDelete: [ .english: "Delete saved writing", .arabic: "حذف الكتابة المحفوظة" ],

        // ━━━ v1.4 T7 suggestion features ━━━
        .generalCompletionShort: [ .english: "Short", .arabic: "قصير" ],
        .generalCompletionMedium: [ .english: "Medium", .arabic: "متوسط" ],
        .generalCompletionLong: [ .english: "Long", .arabic: "طويل" ],
        .generalCompletionLengthHelp: [
            .english: "Short stops at the end of the first clause. Medium is the usual few words. Long lets the model use everything it is allowed. The slider below fine-tunes the same setting.",
            .arabic:  "«قصير» يتوقف عند نهاية أول جملة فرعية. «متوسط» هو بضع كلمات كالمعتاد. «طويل» يتيح للنموذج استخدام كل ما هو مسموح به. يضبط الشريط أدناه الإعداد نفسه بدقة."
        ],
        .generalCompletionLongUnavailable: [
            .english: "The current model is limited to 5 words, so Long isn't available. Pick a larger model in Models.",
            .arabic:  "النموذج الحالي محدود بخمس كلمات، لذا «طويل» غير متاح. اختر نموذجاً أكبر من «النماذج»."
        ],
        .generalMidLine: [
            .english: "Suggest in the middle of a line",
            .arabic:  "الاقتراح في منتصف السطر"
        ],
        .generalMidLineHelp: [
            .english: "On by default. QalamAI writes what fits between the cursor and the text that already follows it on the same line, and never repeats that text. Turn this off to get suggestions only at the end of a line.",
            .arabic:  "مُفعَّل افتراضياً. يكتب QalamAI ما يناسب المسافة بين المؤشر والنص الموجود بعده في السطر نفسه، ولا يكرر ذلك النص أبداً. أوقفه لتحصل على الاقتراحات في نهاية السطر فقط."
        ],
        .generalAlternativesAutoShow: [
            .english: "Show alternatives automatically after a pause",
            .arabic:  "إظهار البدائل تلقائياً بعد توقف قصير"
        ],
        .generalAlternativesAutoShowHelp: [
            .english: "Off by default. When a suggestion is on screen and you stop typing for about a second and a half, the numbered list of other words opens by itself.",
            .arabic:  "مُعطَّل افتراضياً. عندما يكون هناك اقتراح ظاهر وتتوقف عن الكتابة نحو ثانية ونصف، تُفتح قائمة الكلمات الأخرى المرقّمة من تلقاء نفسها."
        ],
        .generalAutocorrectStyle: [
            .english: "How a fix is shown",
            .arabic:  "طريقة عرض التصحيح"
        ],
        .generalAutocorrectStyleInline: [
            .english: "Show the fix as a suggestion",
            .arabic:  "عرض التصحيح كاقتراح"
        ],
        .generalAutocorrectStyleArrow: [
            .english: "Show typo → fix",
            .arabic:  "عرض الخطأ ← التصحيح"
        ],
        .generalAutocorrectStyleHelp: [
            .english: "Press the accept key to apply. QalamAI never changes your text on its own.",
            .arabic:  "اضغط مفتاح القبول لتطبيق التصحيح. لا يغيّر QalamAI نصك من تلقاء نفسه أبداً."
        ],
        .shortcutAcceptAllAboveTab: [
            .english: "Accept the whole suggestion with the key above Tab",
            .arabic:  "قبول الاقتراح كاملاً بالمفتاح الذي فوق Tab"
        ],
        .shortcutAcceptAllAboveTabHelp: [
            .english: "Off by default. While a suggestion is visible, the key above Tab accepts all of it. On the Arabic layout that key types ذ — you won't be able to type ذ while a suggestion is showing.",
            .arabic:  "مُعطَّل افتراضياً. أثناء ظهور اقتراح، يقبل المفتاح الذي فوق Tab الاقتراح كاملاً. في تخطيط لوحة المفاتيح العربية يكتب هذا المفتاح حرف ذ — لن تتمكن من كتابة ذ أثناء ظهور اقتراح."
        ],
        .shortcutAlternatives: [
            .english: "Show other words",
            .arabic:  "إظهار كلمات أخرى"
        ],
        .shortcutAlternativesHelp: [
            .english: "Lists up to five other words or short phrases that could come next, under the cursor. Only while a suggestion is visible.",
            .arabic:  "يعرض حتى خمس كلمات أو عبارات قصيرة أخرى يمكن أن تأتي بعد ذلك، أسفل المؤشر. أثناء ظهور اقتراح فقط."
        ],
        .shortcutInsertAlternative: [
            .english: "Insert one of the alternatives",
            .arabic:  "إدراج أحد البدائل"
        ],
        .shortcutInsertAlternativeHelp: [
            .english: "While the list is open, the number keys insert that option and Esc closes it. The digits reach the app as usual at every other time.",
            .arabic:  "أثناء فتح القائمة، تُدرج مفاتيح الأرقام الخيار المقابل ويغلقها Esc. في غير ذلك تصل الأرقام إلى التطبيق كالمعتاد."
        ],
        .alternativesLoading: [
            .english: "Looking for alternatives…",
            .arabic:  "جارٍ البحث عن بدائل…"
        ],

        // ━━━ v1.4 T8 encrypted iCloud Drive sync ━━━
        .tabSync: [
            .english: "Sync",
            .arabic:  "المزامنة"
        ],
        .syncHeading: [
            .english: "Sync between your Macs",
            .arabic:  "المزامنة بين أجهزة Mac الخاصة بك"
        ],
        .syncSubheading: [
            .english: "Keep your snippets, writing modes, app and website settings, custom instructions and My Info the same on every Mac. Everything is encrypted on this Mac before it is written to iCloud Drive.",
            .arabic:  "احتفظ بالمختصرات وأنماط الكتابة وإعدادات التطبيقات والمواقع والتعليمات المخصصة ومعلوماتي متطابقة على كل جهاز Mac. يُشفّر كل شيء على هذا الجهاز قبل كتابته في iCloud Drive."
        ],
        .syncUnavailable: [
            .english: "iCloud Drive isn’t switched on for this Mac. Turn it on in System Settings › Apple Account › iCloud, then come back here.",
            .arabic:  "iCloud Drive غير مفعّل على هذا الجهاز. فعّله من إعدادات النظام › حساب Apple › iCloud ثم عد إلى هنا."
        ],
        .syncTurnOnTitle: [
            .english: "Turn on sync",
            .arabic:  "تشغيل المزامنة"
        ],
        .syncTurnOn: [
            .english: "Turn on sync",
            .arabic:  "تشغيل المزامنة"
        ],
        .syncPassphrase: [
            .english: "Passphrase",
            .arabic:  "عبارة المرور"
        ],
        .syncPassphraseConfirm: [
            .english: "Passphrase again",
            .arabic:  "عبارة المرور مرة أخرى"
        ],
        .syncPassphraseHelp: [
            .english: "The passphrase encrypts your data before it reaches iCloud Drive. Use the same passphrase on each Mac. If you forget it, the synced copy can’t be recovered. If the same item exists on this Mac and in iCloud, the iCloud copy is kept.",
            .arabic:  "تُشفّر عبارة المرور بياناتك قبل وصولها إلى iCloud Drive. استخدم العبارة نفسها على كل جهاز Mac. إذا نسيتها فلن يمكن استرداد النسخة المتزامنة. وإذا وُجد العنصر نفسه على هذا الجهاز وفي iCloud فيُبقى على نسخة iCloud."
        ],
        .syncPassphraseTooShort: [
            .english: "Use at least 8 characters.",
            .arabic:  "استخدم 8 أحرف على الأقل."
        ],
        .syncPassphraseMismatch: [
            .english: "The two passphrases don’t match.",
            .arabic:  "عبارتا المرور غير متطابقتين."
        ],
        .syncReenterTitle: [
            .english: "Enter the passphrase again",
            .arabic:  "أدخل عبارة المرور مرة أخرى"
        ],
        .syncReenterHelp: [
            .english: "The copy in iCloud Drive couldn’t be opened with the stored passphrase. Nothing was changed there. Enter the passphrase you used on your other Mac to carry on.",
            .arabic:  "تعذّر فتح النسخة الموجودة في iCloud Drive بعبارة المرور المحفوظة، ولم يتغير شيء فيها. أدخل عبارة المرور التي استخدمتها على جهاز Mac الآخر للمتابعة."
        ],
        .syncSavePassphrase: [
            .english: "Save passphrase",
            .arabic:  "حفظ عبارة المرور"
        ],
        .syncStatus: [
            .english: "Status",
            .arabic:  "الحالة"
        ],
        .syncStatusOff: [
            .english: "Off",
            .arabic:  "معطّلة"
        ],
        .syncStatusIdle: [
            .english: "Up to date",
            .arabic:  "محدّثة"
        ],
        .syncStatusSyncing: [
            .english: "Syncing…",
            .arabic:  "جارٍ المزامنة…"
        ],
        .syncStatusWaiting: [
            .english: "Waiting for iCloud Drive to download the copy",
            .arabic:  "بانتظار تنزيل النسخة من iCloud Drive"
        ],
        .syncErrorWrongPassphrase: [
            .english: "Wrong passphrase — the copy in iCloud Drive was left untouched.",
            .arabic:  "عبارة المرور غير صحيحة — لم يُمسس بالنسخة الموجودة في iCloud Drive."
        ],
        .syncErrorKeychain: [
            .english: "The passphrase couldn’t be saved to the keychain.",
            .arabic:  "تعذّر حفظ عبارة المرور في سلسلة المفاتيح."
        ],
        .syncErrorIO: [
            .english: "Couldn’t read or write the copy in iCloud Drive. QalamAI will try again.",
            .arabic:  "تعذّرت قراءة أو كتابة النسخة في iCloud Drive. سيحاول QalamAI مرة أخرى."
        ],
        .syncErrorFormat: [
            .english: "The file in iCloud Drive isn’t a QalamAI sync file.",
            .arabic:  "الملف الموجود في iCloud Drive ليس ملف مزامنة خاصاً بـ QalamAI."
        ],
        .syncLastSync: [
            .english: "Last sync",
            .arabic:  "آخر مزامنة"
        ],
        .syncNever: [
            .english: "Never",
            .arabic:  "لم تحدث بعد"
        ],
        .syncNow: [
            .english: "Sync now",
            .arabic:  "مزامنة الآن"
        ],
        .syncTurnOff: [
            .english: "Turn off sync",
            .arabic:  "إيقاف المزامنة"
        ],
        .syncTurnOffTitle: [
            .english: "Turn off sync?",
            .arabic:  "إيقاف المزامنة؟"
        ],
        .syncTurnOffMessage: [
            .english: "This Mac stops sending and receiving changes. Your settings here stay exactly as they are. You can keep the encrypted copy in iCloud Drive for your other Macs, or move it to the Trash.",
            .arabic:  "سيتوقف هذا الجهاز عن إرسال التغييرات واستقبالها، وتبقى إعداداتك هنا كما هي. يمكنك الإبقاء على النسخة المشفّرة في iCloud Drive لأجهزتك الأخرى، أو نقلها إلى سلة المهملات."
        ],
        .syncTurnOffKeep: [
            .english: "Keep cloud copy",
            .arabic:  "الإبقاء على النسخة السحابية"
        ],
        .syncTurnOffRemove: [
            .english: "Move cloud copy to Trash",
            .arabic:  "نقل النسخة السحابية إلى سلة المهملات"
        ],
        .syncIncludeSamples: [
            .english: "Include saved writing samples",
            .arabic:  "تضمين عينات الكتابة المحفوظة"
        ],
        .syncIncludeSamplesHelp: [
            .english: "Off by default. Writing samples are the most personal thing QalamAI keeps, so they travel only if you ask. They are encrypted with the same passphrase, in a separate file, and are sent every 15 minutes rather than right away.",
            .arabic:  "مُعطّل افتراضياً. عينات الكتابة هي أكثر ما يحتفظ به QalamAI خصوصية، لذا لا تُنقل إلا بطلبك. تُشفّر بعبارة المرور نفسها في ملف منفصل، وتُرسل كل 15 دقيقة بدلاً من إرسالها فوراً."
        ],
        .syncWhatSyncs: [
            .english: "What syncs",
            .arabic:  "ما الذي تتم مزامنته"
        ],
        .syncItemSnippets: [
            .english: "Snippets",
            .arabic:  "المختصرات"
        ],
        .syncItemModes: [
            .english: "Your own writing modes",
            .arabic:  "أنماط الكتابة الخاصة بك"
        ],
        .syncItemApps: [
            .english: "App and website settings",
            .arabic:  "إعدادات التطبيقات والمواقع"
        ],
        .syncItemInstructions: [
            .english: "Custom instructions",
            .arabic:  "التعليمات المخصصة"
        ],
        .syncItemMyInfo: [
            .english: "My Info",
            .arabic:  "معلوماتي"
        ],
        .syncNeverNote: [
            .english: "Never synced: screenshots, text read from the screen, the clipboard, logs, usage stats and downloaded models.",
            .arabic:  "لا تتم مزامنة: لقطات الشاشة، والنص المقروء من الشاشة، والحافظة، والسجلات، وإحصاءات الاستخدام، والنماذج المُنزّلة."
        ],
        .syncEncryptionNote: [
            .english: "Encrypted on this Mac with AES-GCM and a key derived from your passphrase (PBKDF2-SHA256, 310,000 rounds). iCloud Drive only ever holds the encrypted file, and the passphrase stays in this Mac’s login keychain.",
            .arabic:  "يُشفّر على هذا الجهاز بـ AES-GCM بمفتاح مشتقّ من عبارة المرور (PBKDF2-SHA256، 310,000 دورة). لا يحتفظ iCloud Drive إلا بالملف المشفّر، وتبقى عبارة المرور في سلسلة مفاتيح الدخول على هذا الجهاز."
        ],
        // ━━━ v1.4 T9 integration polish ━━━
        .popoverStatusSnoozed: [
            .english: "Snoozed",
            .arabic:  "مؤجَّل"
        ],
    ]
}

/// Convenience shorthand used in views: `L.t(.tabModels)`.
enum L {
    @MainActor
    static func t(_ key: LocalizationKey) -> String {
        LocalizationStore.shared.t(key)
    }
}
