# Contributing to Sentrio

Thank you for taking the time to contribute! This document explains how to get involved.

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating you agree to uphold its standards.

---

## Ways to contribute

- **Bug reports** — open an [issue](https://github.com/YunaBraska/Sentrio/issues/new?template=bug_report.md)
- **Feature requests** — open an [issue](https://github.com/YunaBraska/Sentrio/issues/new?template=feature_request.md)
- **Code contributions** — fork, branch, and open a pull request (see below)
- **Documentation fixes** — even small typo fixes are appreciated

---

## Development setup

```bash
git clone https://github.com/YunaBraska/Sentrio.git
cd Sentrio

# Build (debug)
swift build

# Run tests — always run before submitting a PR
swift test

# Build distributable .app
./build.sh
```

Requirements: macOS 13+, Swift 5.9+. No Xcode required (though it can be opened with `open Package.swift`).

---

## Pull Request process

1. **Fork** the repository and create a branch from `main`:
   ```bash
   git checkout -b fix/my-bugfix
   ```
2. **Write tests** for any new behaviour or bug fix.
   All existing tests must continue to pass (`swift test`).
3. **Follow existing code style** — SwiftUI/Swift conventions, `// MARK: –` section headers, minimal comments that explain *why* not *what*.
4. **Keep PRs focused** — one logical change per PR makes review easier.
5. **Update documentation** if your change affects user-facing behaviour (README, inline comments).
6. Open the PR against the `main` branch and fill in the PR template.

---

## Commit message style

```
<type>: <short summary in present tense>

<optional body explaining why>
```

Types: `fix`, `feat`, `test`, `docs`, `refactor`, `chore`

Examples:
```
fix: filter CADefaultDeviceAggregate from device list
feat: add per-device icon picker
test: cover deleteDevice edge cases
```

---

## Release process

Releases are created manually via GitHub Actions:
**Actions → Release → Run workflow**.
The version tag is generated from the current UTC date/time in the format `YYYY.MM.DDDHHMM`
(e.g. `2026.02.0521048` = year 2026, month 02, day-of-year 052, 10:48).

You do not need to manually tag or version releases.

---

## Architecture overview

```
SentrioApp          — @main SwiftUI App, MenuBarExtra
  AppState              — top-level ObservableObject, wires everything together
    AppSettings         — UserDefaults-backed settings (priority lists, volume memory, icons)
    AudioManager        — CoreAudio wrapper (enumerate devices, get/set defaults and volumes)
    RulesEngine         — Combine-driven priority logic, applies rules on device change
```

All heavy logic lives in `SentrioCore` (library target) so it can be fully unit-tested without running the app. The `Sentrio` target is a thin executable that only calls `SentrioApp.main()`.

---

## Licensing

By submitting a contribution you agree that your code will be released under the [MIT License](LICENSE).
