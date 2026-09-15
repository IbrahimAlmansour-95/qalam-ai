# Changelog

<<<<<<< Updated upstream
=======
## 1.3.11 — 2026-05-31

- **Fixed the onboarding window drifting/"floating".** The Welcome/Get Started window could be dragged by clicking anywhere on its background, so it moved around while you tried to press buttons. It now stays put (still movable by its title bar).

## 1.3.10 — 2026-05-31

- **Restored stable inline placement.** The v1.3.9 attempt to keep the ghost on-field in apps that misreport the caret (clamp, then fit-or-hide) regressed the apps that worked — it could overlap text or stop showing Arabic in Notes. Reverted to the proven placement: Arabic works in Notes and other well-behaved fields, English everywhere, plus the Terminal/Chromium caret fixes.
- Known limitation: **Telegram reports the Arabic (RTL) caret incorrectly** (pinned to the box edge), so inline suggestions there can be mispositioned. This is a Telegram Accessibility issue we can't correct without breaking other apps; left as-is by design.

>>>>>>> Stashed changes
## 1.3.9 — 2026-05-31

- **Ghost can no longer fly off the text field.** Some apps misreport the caret — e.g. Telegram pins the Arabic (RTL) caret to the box's left edge — which threw the suggestion far outside the field. The ghost is now clamped to stay within the focused field's bounds. (No effect on apps that report the caret correctly.)
- Made the field-frame coordinate conversion consistent with the caret (correct on multi-monitor setups).

## 1.3.8 — 2026-05-31

- **Inline ghost works in more apps.** Fixed positioning in Terminal and Chromium/Electron apps (Claude Desktop, etc.), which report a garbage zero-length caret rect — we now validate the caret X and fall back to the real glyph edge, so the ghost lands at the cursor instead of flying to the screen corner.
- **Mixed Arabic/English lines** place the ghost on the side the line is actually flowing (base direction), so it no longer overlaps existing text.
- **Arabic autocorrect** now works: since macOS's Arabic dictionary can't catch errors, finished Arabic sentences are proof-read by the local model (e.g. `انا ذهبت الي المدرسه` → `أنا ذهبت إلى المدرسة`). English keeps using the instant system spell-checker.
- **Context-aware suggestions**: clipboard, nearby on-screen text, and screen OCR now feed the model (all cached so typing stays fast).
- Lingering ghost no longer sticks after you finish a word; suggestions stay snappy (engine kept warm, no orphaned processes).
- Internal: unified script detection into one shared helper.

## 1.3.7 — 2026-05-31

- **Fixed slow suggestions.** The bundled Ollama engine wasn't shut down on quit, so it (and its model-loaded runners) were orphaned on every launch and piled up, thrashing memory. The engine is now stopped on quit, its runner children are reaped, and any orphans from a prior crash are cleared on launch. Warm completions are ~0.3s again.
- **Pre-warm the model at launch** so your first suggestion is instant instead of paying a multi-second cold load.
- **Fixed the black title-bar strip in Light mode** — the Settings window forced a dark appearance and background; it now follows your chosen theme.
- **Ghost text no longer clips and sits on the baseline** — its width is measured directly from the font (long suggestions were truncated to a sliver) and it bottom-aligns to the line.
- **New: Inline suggestion calibration** (General settings) — Size and Vertical sliders to align the ghost in apps that misreport caret geometry (e.g. Apple Notes).

## 1.3.6 — 2026-05-31

- **Ghost text now matches your text's size, so it reads as truly inline.** It's sized from the caret's actual line height instead of the app-reported font size — those disagree in large-font docs, zoomed/presentation views, and some HiDPI cases, which made the suggestion look like a tiny floating tag. Now it scales to match the surrounding text.

## 1.3.5 — 2026-05-31

- **Autocomplete actually works now.** Root cause of the empty/garbage suggestions: modern models like Gemma 4 are *reasoning* models that send their answer to a hidden "thinking" channel, leaving the response empty unless thinking is disabled. We now send `think: false` to Ollama, so the model answers directly — and faster (no hidden reasoning tokens). Verified producing relevant English and Arabic completions.

## 1.3.4 — 2026-05-31

- **Much better, on-context completions.** Rebuilt the prompt to be lean and completion-focused (like Cotypist): it now leads with your immediate text instead of burying a small model under a long instruction block plus app/clipboard/screen/style context. Lower temperature, single-line output, and harder cleanup (strips echoed text, stray labels, and rambling) make suggestions far more relevant and consistent.

## 1.3.3 — 2026-05-31

- **Fixed ghost text appearing above the line on multi-monitor setups.** The caret position was converted using a mismatched coordinate space, which picked the wrong screen and offset the suggestion vertically. Now uses a correct global flip — suggestions sit inline on the caret's line on every display.
- **Ghost text is always dimmed inline now (no more yellow/amber).** Completions, snippets, and corrections all render as a faded version of your own text color, like Cotypist — instead of a branded color that read as a floating tag.
- **Snappier suggestions.** The model is kept warm (30-min keep-alive) so quick typing bursts don't pay the multi-second cold-reload cost.
- Builds are now signed with a stable self-signed identity, so the Accessibility grant survives future updates instead of resetting each time.

## 1.3.2 — 2026-05-31

- **Appearance switch now applies live.** Setting NSApp.appearance alone didn't repaint already-open windows; the theme is now pushed onto every window so Light/Dark/System takes effect immediately.
- **Auto re-prompt for Accessibility after an update.** When a returning user launches a build whose (ad-hoc) signature changed — which makes macOS silently drop the Accessibility grant and stops autocomplete — QalamAI now triggers the system permission prompt and opens Settings, instead of silently doing nothing.

## 1.3.1 — 2026-05-31

- **Fixed a crash on launch.** A duplicated block of localization strings made the translation table trap the moment any text was loaded, so the app quit immediately. Removed the duplicate. (Affected 1.2.0 and 1.3.0.)

## 1.3.0 — 2026-05-29

- **Light mode** — new Appearance setting (System / Light / Dark) in General. The whole UI uses adaptive colors and follows your choice instantly.
- **In-app update install** — "Download & Install" downloads the new DMG inside the app with a progress bar, then opens it for the drag-to-Applications step (no more bouncing to the browser).
- **Multi-suggestion cycle** — press ⌥ ] while a completion is showing to regenerate a different alternative.
- **Tone rewrite on selection** — select text in any app and press ⌃⌥R to rewrite it as Formal, Casual, Concise, Expanded, or grammar-fixed, in place.
- Full Arabic localization for all of the above.

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
