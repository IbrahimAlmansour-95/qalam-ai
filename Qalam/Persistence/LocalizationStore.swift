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
    case generalExcludedAppsHelp
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
    case generalAddApp
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
    case shortcutAcceptLine
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
            .english: "When you press Tab, insert a trailing space after the accepted word.",
            .arabic:  "عند الضغط على Tab، أضف مسافة بعد الكلمة المقبولة."
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
            .english: "Also trashes downloaded models and settings. This frees the most space.",
            .arabic:  "يحذف أيضاً النماذج المُنزّلة والإعدادات إلى سلة المهملات. يوفّر أكبر مساحة."
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
        .generalExcludedAppsHelp: [
            .english: "No apps excluded. QalamAI will suggest in every app where it can read text.",
            .arabic:  "لا توجد تطبيقات مستبعدة. سيقترح QalamAI في كل تطبيق يستطيع قراءة النص فيه."
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
        .generalAddApp: [.english: "Add app", .arabic: "إضافة تطبيق"],

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
        .shortcutAcceptLine: [.english: "Accept full line", .arabic: "قبول السطر كاملاً"],
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
    ]
}

/// Convenience shorthand used in views: `L.t(.tabModels)`.
enum L {
    @MainActor
    static func t(_ key: LocalizationKey) -> String {
        LocalizationStore.shared.t(key)
    }
}
