# Changelog

## 1.2.0 — 2026-05-29

- **Configurable accept key** — accept the next word with Tab ⇥ (default) or the Right Arrow →. ⇧ + the key still accepts the whole suggestion.
- **Snooze** — pause suggestions for 30 min, 1 hour, or until tomorrow morning, right from the menu-bar popover, with a one-tap Resume.
- **Inline accept hint** — a faint ⇥ / → badge after the ghost text reminds you which key accepts it (toggle in General settings).
- **Smarter triggers** — suggestions are suppressed inside URLs, emails, file paths, and code-ish tokens where autocomplete is just noise.
- **Snippet variables** — `{date}`, `{time}`, `{datetime}`, and `{clipboard}` expand inside snippet text.
- **Custom model import** — add any Ollama tag (e.g. `llama3.2:3b`) from the Models tab to install and use beyond the curated catalog.
- **Diagnostics** — copy a privacy-safe snapshot of app + system state from the Privacy tab to help troubleshoot (no typed text included).
- Full Arabic localization for all of the above.

## 1.1.3 — 2026-05-29

- Ghost text matches the host field's font, size, and color more reliably (reads the run's attributes with element-level font/color fallbacks) so completions blend into your writing like Cotypist.
- Added a "Check for updates" button in General settings (works even with auto-update off), with up-to-date / download states.

## 1.1.2 — 2026-05-29

- Inline ghost text now occupies the exact caret line-box (height + baseline match) and appears instantly, so completions read as part of the line you're typing — like Cotypist — instead of a floating tooltip.

## 1.1.1 — 2026-05-29

- In-app uninstaller (Privacy tab): "Remove app, keep models & settings" or "Remove everything". Everything goes to the Trash (recoverable). Keeping data makes reinstalling instant — no model re-download, no re-setup.
- Shows your data footprint and a "Show my data in Finder" shortcut.


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
