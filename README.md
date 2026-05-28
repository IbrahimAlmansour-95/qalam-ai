# QalamAI

> **قلم** _(qalam)_ — Arabic for "pen". A free, local-first AI autocomplete for every macOS app.

QalamAI predicts your next words while you type in any Mac application — Mail, Notes, Safari, Chrome, Word, Notion, Obsidian, Messages, and most other text fields. It runs entirely on your Mac via a bundled Ollama engine, so your text never leaves your device.

- **Inline ghost text**, just like macOS's native predictive autocomplete
- **Tab to accept** word-by-word; ⇧Tab accepts the full suggestion
- **Context-aware autocorrect** powered by `NSSpellChecker` + optional LLM grammar pass
- **24 model choices** across Gemma 4 · Gemma 3n · Gemma 3 · Qwen 3 · Qwen 2.5 · Phi · Llama · SmolLM2
- **Snippets** (`:sig` → your signature) and **emoji shortcodes** (`:smi` → 🙂)
- **6 writing modes** (Professional · Casual · Code · Email · Reply · Custom)
- **English & Arabic** UI with full RTL layout support
- **Apple Silicon only** (M1+), macOS 14+
- **Free**, no Pro tier, no daily caps, no telemetry

## Installation

### Option 1 — DMG (recommended)

1. Download `QalamAI-1.0.0-arm64.dmg` from the [latest release](../../releases).
2. Open the DMG and drag **QalamAI** into your `Applications` folder.
3. Launch **QalamAI**. The قلم icon appears in your menu bar.
4. **Grant Accessibility access** when prompted: System Settings → Privacy & Security → Accessibility → toggle QalamAI on. The app will detect this within ~2 s and start working.
5. Open the menu-bar popover and follow the in-app onboarding to pick a model.

> macOS revokes the Accessibility grant every time the binary changes (because we ad-hoc sign). The first launch after every update needs a re-grant — the app will show a clear banner with a one-click button to the right Settings pane.

### Option 2 — Build from source

```bash
git clone <this-repo-url>
cd qalamai
bash scripts/ship.sh
open build/QalamAI-1.0.0-arm64.dmg
```

See [Building](#building) for details.

## First-launch onboarding

1. **Welcome** — pick interface language (English or العربية).
2. **Accessibility access** — tap "Open System Settings", toggle QalamAI on.
3. **Engine setup** — QalamAI's bundled Ollama is auto-detected; if for some reason it isn't, the app downloads it once into `~/Library/Application Support/QalamAI/`.
4. **Choose a model** — QalamAI inspects your RAM and chip and recommends the best free-tier model that comfortably fits. The default for most Macs is **Gemma 4 E2B**. Drag the "Suggestion length" slider to control how many words it predicts at once (1 → model max).

## How autocomplete works

While you type in any app, QalamAI reads the focused text via the macOS Accessibility API, debounces ~120 ms, and asks the local model for the next 1–3 words (adjustable). The ghost text renders inline next to your caret in a neutral SF Pro 14 pt and disappears the moment you keep typing.

| Key | Action |
|---|---|
| `Tab` | Accept the next word |
| `⇧Tab` | Accept the full suggestion |
| `Esc` | Dismiss the suggestion |
| `:abbrev` + `Tab` | Expand a snippet (`:sig`, `:addr`, `:thx`, …) |
| `:shortcode` + `Tab` | Insert an emoji (`:smi` → 🙂, `:fire` → 🔥, …) |

Password fields and any app added to the **Excluded apps** list in Settings are skipped automatically.

## Compatibility

| Status | Apps |
|---|---|
| ✅ Works | Mail, Notes, Safari, Chrome, Word, Notion, Obsidian, Messages, most native text fields |
| ⚙️ Needs a toggle | Google Docs (turn on Accessibility mode), Arc / Dia (enable accessibility in browser settings) |
| ⚠️ Limited | VS Code / Cursor main editor (uses canvas-rendered text that's not AX-readable) — only the sidebar AI chats work |

## Settings highlights

- **General** — language, suggestion delay, trigger threshold, suggestion length, excluded apps, autocorrect toggles
- **Models** — All / Installed filter, family chips, download progress, system-RAM compatibility warnings, delete unused models
- **Modes** — 6 built-in writing modes + custom mode editor (set your own instruction + temperature)
- **Snippets** — manage your `:abbrev` expansions
- **Shortcuts** — see all key bindings
- **Privacy** — 7-day word chart, style history, app compatibility, "Clear style history" / "Reset statistics"

## Privacy

- **100% local** — QalamAI ships its own Ollama engine (`Contents/Helpers/Ollama.app`) and talks to it only on `127.0.0.1:11434`. No telemetry, no analytics, no cloud inference path.
- **Models live at** `~/Library/Application Support/QalamAI/models`.
- **Password fields are excluded** at the AX layer (`AXSecureTextField` role check).
- **Excluded apps** are honored at the engine level — no requests are made for text in those bundles.

## System requirements

- **Apple Silicon** Mac (M1 or newer). The bundle is arm64-only; no x86_64 build.
- **macOS 14** (Sonoma) or later. Built and tested through macOS 26 (Tahoe).
- ~**4 GB RAM** free for the smallest models; 8 GB+ for the recommended Gemma 4 E2B; 24 GB+ for the largest (Gemma 4 26B / 31B, Qwen 3 30B-A3B).
- ~**4 GB** disk for the app + bundled Ollama; models download separately into Application Support.

## Building

QalamAI doesn't use `xcodebuild` (the Xcode 26.5 toolchain has a `DVTDownloads`/`IDESimulatorFoundation` symbol mismatch on macOS 26.5 that blocks `xcodebuild` startup). It builds via `swiftc` directly, plus `create-dmg` for the installer.

**Prerequisites:**
- Xcode 16+ command line tools (`xcode-select --install`)
- `brew install create-dmg`

**One-shot ship build:**
```bash
bash scripts/ship.sh
```
This does a fresh build, downloads + embeds the latest Ollama, strips its universal binaries to arm64, and packages the DMG. Output: `build/QalamAI-1.0.0-arm64.dmg`.

**Iterative (skip bundling Ollama for fast rebuilds):**
```bash
SKIP_OLLAMA=1 bash scripts/build.sh
```

**Directory layout:**
```
Qalam/
  App/                   QalamApp.swift (@main), AppDelegate, AppState, Constants
  Accessibility/         AccessibilityMonitor, TextInjector, AccessibilityPermissionMonitor
  DesignSystem/          Tokens + Q* SwiftUI components + WeeklyBarChart + QalamLogo
  Inference/             LLMBackend protocol + OllamaBackend (streaming generate)
  Input/                 KeystrokeInterceptor (CGEventTap for Tab/Esc + AX pump)
  ModelManager/          ModelRegistry, ModelManager, OllamaService, OllamaInstaller, DeviceSpecs
  Persistence/           UserPreferences, UsageLogger, StyleContextBuffer, LocalizationStore
  Resources/             AppIcon assets, menu-bar PNGs, emoji-shortcodes.json, entitlements
  Suggestion/            SuggestionEngine, PromptBuilder, GrammarChecker, WritingMode, Snippet, EmojiResolver
  UI/                    MenuBar/ · Settings/ · Onboarding/ · Overlay/
scripts/
  build.sh               swiftc + Ollama embed + lipo + ad-hoc codesign
  package-dmg.sh         create-dmg with branded background
  ship.sh                build.sh + package-dmg.sh + checksum summary
  dmg-resources/         800×500 installer background (1× + 2×)
```

## Distributing to other Macs

The shipped DMG is **ad-hoc signed** (no Apple Developer account). On the build machine it just runs; on any *other* Apple Silicon Mac, macOS quarantines it on download and Gatekeeper blocks it with *"QalamAI.app can't be opened."* Recipients clear it once with either:

- double-click `scripts/Fix-QalamAI-Open.command` (bundled in the repo), or
- `xattr -dr com.apple.quarantine /Applications/QalamAI.app` in Terminal, or
- **System Settings → Privacy & Security → Open Anyway**.

See [Troubleshooting](#troubleshooting). (Intel Macs can't run it at all — QalamAI is arm64-only.)

> If you later get a paid Apple Developer account, signing with a Developer ID + notarizing the DMG removes this step entirely. It's intentionally not wired up here since the project ships unsigned.

## Architecture notes

- **Single-file app entry** ([`QalamApp.swift`](Qalam/App/QalamApp.swift)) — `@main` `enum QalamAIMain` bootstraps `NSApplication` directly. SwiftUI `App` is deliberately avoided because its `Settings { EmptyView() }` scene auto-opens an empty Settings window on macOS Tahoe for accessory apps.
- **Bundled Ollama** ([`OllamaInstaller.swift`](Qalam/ModelManager/OllamaInstaller.swift)) — bundle path first, system install second, downloaded copy third, auto-download fourth.
- **Caret-anchored ghost text** ([`AccessibilityMonitor.caretFrame()`](Qalam/Accessibility/AccessibilityMonitor.swift)) — `kAXBoundsForRangeParameterizedAttribute` for native apps; top-left offset for Electron apps that don't expose caret bounds.
- **Per-app preferences suite** ([`QalamDefaults.swift`](Qalam/Persistence/QalamDefaults.swift)) — explicit `UserDefaults(suiteName: Constants.bundleID)` instead of `.standard`, because `.standard` isn't reliably bound to the bundle's domain when an ad-hoc signed app is launched outside LaunchServices.
- **Swift 6 strict concurrency** everywhere (`SWIFT_STRICT_CONCURRENCY=complete`).

## Troubleshooting

**"The application 'QalamAI.app' can't be opened" on someone else's Mac:**
QalamAI is **ad-hoc signed**, not notarized through a paid Apple Developer account. When the DMG is downloaded/copied to another Mac, macOS quarantines the app and Gatekeeper refuses to launch it. Two fixes (Apple Silicon only — QalamAI does not run on Intel Macs):

- **Easiest:** double-click `scripts/Fix-QalamAI-Open.command` (also shipped in the repo), which removes the quarantine flag and opens the app.
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/QalamAI.app` then open it normally.
- **GUI:** try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

This is a one-time step per download. See [Distributing to other Macs](#distributing-to-other-macs).

**"Needs access" red badge in the menu bar:** Open System Settings → Privacy & Security → Accessibility, remove any stale QalamAI entry, then re-add (the app will trigger the prompt). The app auto-detects the flip and reinstalls the keystroke tap within 2 s, no restart needed.

**Empty settings window:** Was a real bug on early builds; fixed by switching from SwiftUI `App` to a plain `@main` enum. If you hit it on a current build, reinstall from the latest DMG.

**Suggestions stuck on "Connecting…":** Most commonly a port collision — another Ollama instance is already on `127.0.0.1:11434`. The Models tab now shows the engine's actual stderr as a red banner on download failure; quit the other Ollama or change `OLLAMA_HOST` for the conflicting process.

**Ghost text in the wrong location in Cursor/VS Code:** Their editor canvas isn't AX-readable, so we fall back to a heuristic. The AI sidebar chats work; the main editor doesn't (Cotypist has the same limitation).

## License

[MIT](LICENSE) © 2026 Ibrahim Almansour
