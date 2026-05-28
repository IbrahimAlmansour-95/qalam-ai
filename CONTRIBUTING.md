# Contributing to QalamAI

Thanks for thinking about contributing — issues, PRs, and bug reports are all welcome.

## Setting up

```bash
git clone <repo>
cd qalamai
brew install create-dmg          # for the installer step
bash scripts/ship.sh             # full build + DMG
```

If you only need a quick iteration loop (no DMG, no Ollama embed):

```bash
SKIP_OLLAMA=1 bash scripts/build.sh
open build/Export/QalamAI.app
```

## House rules

- **Swift 6 strict concurrency** everywhere. The codebase compiles cleanly under `SWIFT_STRICT_CONCURRENCY=complete`; new code must too.
- **arm64 only.** Don't add x86_64 conditionals or universal-binary tooling.
- **No telemetry.** Ever. No analytics, no usage-reporting endpoints, no third-party SDKs that phone home.
- **No new top-level Scenes in SwiftUI App.** We use a plain `@main enum QalamAIMain` because SwiftUI `Settings` auto-opens an empty window on macOS Tahoe. Keep it that way.
- **Persistence goes through `QalamDefaults.suite`,** never `UserDefaults.standard`. The standard suite isn't reliably bound to our bundle when launched outside LaunchServices.

## Versioning — always bump

Every change that ships **must** bump the version. There is one source of truth: `Constants.version` in `Qalam/App/Constants.swift`. The build scripts read it to stamp `Info.plist` and name the DMG, and `UpdateChecker` compares it to GitHub releases — so editing that one line is all it takes.

Bump rule:

- **Minor change** (fix, tweak, small feature) → bump the **patch**: `1.0.0` → `1.0.1`
- **Major change** (significant feature or batch) → bump the **minor**: `1.0.x` → `1.1.0`

Then tag the GitHub release to match (`v1.0.1`, `v1.1.0`) and attach the DMG, so the in-app updater offers it.

## Reporting bugs

Open an issue with:
- Your Mac model + macOS version
- The exact app you were typing in
- A screenshot of the menu-bar popover's status badge
- The relevant lines from Console.app, filtered to process `QalamAI` (we log `NSLog("QalamAI: …")` for the noisy paths)

## Translation contributions

Adding a third language is a single-file change — add a case to [`LocalizationStore.Language`](Qalam/Persistence/LocalizationStore.swift) plus translations into `Translations.dict`. The whole UI re-renders with the new strings (and RTL flips automatically if the language warrants it).
