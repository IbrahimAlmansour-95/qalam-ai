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

    // Settings tabs
    case settingsTitle
    case tabGeneral
    case tabModels
    case tabModes
    case tabSnippets
    case tabShortcuts
    case tabPrivacy

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
    case popoverCompatibility
    case popoverCompatibilityWorks
    case popoverCompatibilityToggle
    case popoverCompatibilityLimited
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
    ]
}

/// Convenience shorthand used in views: `L.t(.tabModels)`.
enum L {
    @MainActor
    static func t(_ key: LocalizationKey) -> String {
        LocalizationStore.shared.t(key)
    }
}
