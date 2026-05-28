# Changelog

## 1.1.0 — 2026-05-29

- Inline ghost text now renders as a dimmed version of your own text color (not green/indigo).
- Spell-aware: valid in-progress words continue via completion; only finished misspelled words get corrected.
- Toggle: add a trailing space after accepting with Tab.
- New **My Info** vault (name/email/phone/custom) injected into the prompt for in-context completion of your details.
- Context sources: app name, text-after-cursor, nearby AX text, clipboard (opt-in), screen OCR (opt-in).
- **Apple Intelligence** Foundation Model engine option (macOS 26+), falls back to bundled Ollama.
- GitHub **auto-update** checker with a Download banner in the menu-bar popover.
- Apple-like onboarding revamp (aurora background, animated logo, personalize step).
- Completed Arabic localization across all settings tabs.
- Version is now single-sourced from `Constants.version`; bump rule documented in CONTRIBUTING.


## 1.0.0 — 2026-05-28

Initial public release. Everything below is in the box.

### Core
- Local-first inline autocomplete via bundled Ollama (`Contents/Helpers/Ollama.app`)
- arm64-only, macOS 14+, ad-hoc signed, no telemetry
- Apple Silicon Metal acceleration through Ollama's MLX runners
- AX-driven text reading + `kAXBoundsForRangeParameterizedAttribute` caret anchoring
- `CGEventTap` keystroke interception for Tab / ⇧Tab / Esc

### Models — 24 entries shipped
- Gemma 4: E2B (recommended default), E4B, 26B, 31B
- Gemma 3n: E2B, E4B
- Gemma 3: 1B, 4B, 12B
- Qwen 3: 1.7B, 4B, 8B, 30B-A3B
- Qwen 2.5: 0.5B, 1.5B, 3B, 7B
- Phi: phi4-mini, phi3:mini
- Llama: 3.2:1B, 3.2:3B, 3.1:8B
- SmolLM2: 135M, 360M

### Features
- **Smart onboarding** that recommends a model based on detected RAM + chip family
- **Suggestion length slider** (1 → model max) with model-aware ceiling (Fast=5, Balanced=10, Quality=15)
- **6 writing modes** (Neutral, Professional, Casual, Code, Email, Reply) + user-defined custom modes
- **Snippets** — `:abbrev` + Tab inserts an expansion; seeded with sensible defaults
- **Emoji shortcodes** — `:partial` + Tab inserts the matching emoji (52 shortcodes bundled)
- **Context-aware autocorrect** via `NSSpellChecker.check(types: .spelling | .grammar)` with edit-distance and length filters
- **Sentence-level grammar fix** via LLM, opt-in
- **App exclusion list** in Settings
- **7-day usage chart** in Privacy tab
- **Style context buffer** — last 50 accepted phrases used as prompt examples
- **English + Arabic UI** with RTL layout

### Installer
- DMG with branded 800×500 background, drag-to-Applications layout
- `create-dmg`-backed packaging script
- Pill backdrops behind icon labels for legibility in both Light and Dark mode

### Build pipeline
- `scripts/ship.sh` — one-shot fresh DMG (cleans previous artifacts, rebuilds, embeds Ollama, lipo-strips x86_64, codesigns, packages)
- `scripts/build.sh` — incremental build with `SKIP_OLLAMA=1` for fast rebuilds
- Swift 6 strict concurrency throughout

### Free for all
- No Pro tier, no paid plans, no usage caps, no telemetry, no analytics
