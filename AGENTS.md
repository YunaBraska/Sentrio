# Repository Guidelines

## Project Structure & Module Organization

This is a Swift Package Manager (SwiftPM) macOS menu bar app.

- `Package.swift` — SwiftPM manifest (macOS 13+, Swift 5.9+)
- `Sources/Sentrio/` — thin executable target (`main.swift`)
- `Sources/SentrioCore/` — app logic (CoreAudio wrappers, rules engine, settings, SwiftUI views)
- `Tests/SentrioTests/` — unit tests for `SentrioCore` (XCTest)
- `.github/` — issue/PR templates and the release workflow
- `build.sh` — assembles a distributable `build/Sentrio.app`

Generated folders like `.build/` and `build/` should not be committed.

## Build, Test, and Development Commands

```bash
swift build                 # Debug build
swift build && .build/debug/Sentrio   # Build + run from terminal
swift test                  # Run XCTest suite
./build.sh [VERSION]        # Build app bundle into ./build/ (VERSION optional)
open Package.swift          # Open in Xcode (optional)
```

## Coding Style & Naming Conventions

- Keep `Sources/Sentrio/` minimal; put testable logic in `Sources/SentrioCore/`.
- Match existing Swift conventions: 4-space indentation, `// MARK: –` section headers, minimal comments (explain *why*).
- Prefer `let` and small types; use `final class` for shared state containers (`AppState`, managers).
- Naming: types `UpperCamelCase`, members `lowerCamelCase`, tests `*Tests` with methods named `test_*`.

No SwiftLint/SwiftFormat config is currently enforced—use Xcode formatting and keep diffs tidy.

## Testing Guidelines

- Framework: XCTest (`swift test`).
- Add tests under `Tests/SentrioTests/` and target `SentrioCore`.
- Keep tests deterministic (e.g., use `UserDefaults(suiteName:)` like `AppSettingsTests`).

## Commit & Pull Request Guidelines

- Use the PR template in `.github/PULL_REQUEST_TEMPLATE.md` (summary, type, linked issue, testing checklist).
- Commit messages follow `type: short summary` (e.g., `fix: …`, `feat: …`, `test: …`, `docs: …`), present tense.
- Releases are created via **Actions → Release → Run workflow**; version tags are UTC timestamps (`YYYY.MM.DDDHHMM`).
- Homebrew: the Release workflow updates the cask in `YunaBraska/homebrew-tap` (requires `HOMEBREW_TAP_TOKEN` secret).
