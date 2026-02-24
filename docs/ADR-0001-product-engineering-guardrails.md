# ADR-0001: Product And Engineering Guardrails

- Status: Accepted
- Date: 2026-02-23

## Context

The app has grown beyond basic device switching. BusyLight control, rule logic, REST integration, and localization now interact across core logic, settings, and UI.

Recent regressions and missed expectations showed recurring failure modes:

- Feature code shipped without complete localization keys.
- Behavior changed without corresponding tests.
- API and Preferences drifted (state not fully mirrored both ways).
- Trigger logs became noisy and less useful for users.

This ADR records non-negotiable guardrails for all future changes.

## Decision

1. Tests are mandatory for behavior changes.

- Any new runtime behavior or settings field must include tests.
- At minimum, update/extend unit tests in `Tests/SentrioTests/`.
- CI/local checks must pass with `swift test`.

2. Localization coverage is mandatory for user-facing strings.

- New user-visible strings must use `L10n.tr(...)`/`L10n.format(...)`.
- New keys must be added to `en` and all supported localizations.
- `LocalizationTests` must remain green.

3. API and Preferences must represent the same source of truth.

- If a setting can be changed via REST, that same state must be visible and editable in Preferences.
- If a setting changes in Preferences, API state endpoints must immediately reflect it.
- No shadow state that diverges between UI and API.

4. BusyLight control model is standardized.

- `auto` mode means rules drive output.
- `manual` mode means manual action drives output.
- Preferences exposes this as a single toggle: rules enabled/disabled.
- REST may use explicit `auto/manual` paths, but semantics remain identical.

5. Logging is trigger-oriented and in-memory.

- Keep an in-memory ring buffer of the most recent 20 BusyLight events.
- Do not persist BusyLight logs.
- Keepalive ticks must not be logged.
- Log user/API triggers and meaningful state transitions only.

6. REST API shape must remain extensible.

- Canonical path must be versioned under `/v1/...`.
- BusyLight endpoints live under `/v1/busylight/...`.
- Backward-compatible aliases are allowed, but versioned paths are the contract.

7. REST-triggered light changes imply manual control.

- Any REST action that directly sets a BusyLight action must switch control to `manual`.
- `/auto` (or equivalent) explicitly returns control to rules.
- Trigger logs must include who/what initiated the change (REST path, rule name, startup, settings, etc.).

8. BusyLight Preferences and hardware presence behavior is fixed.

- The BusyLight tab is shown only when a BusyLight device is connected.
- If the active tab is BusyLight and the device disconnects, selection must move to a safe tab.
- Reconnection brings the tab back without leaving UI state in an invalid selection loop.

9. BusyLight signal naming and limits must be explicit.

- The `music` signal is presented to users as **Alert sounds**.
- Detection is best-effort based on available system signals; it is not guaranteed per-app media playback truth.
- Any stronger detection mode that requires extra permissions must be explicit and opt-in.

10. BusyLight API port input is strict integer UX.

- Preferences must accept plain integer entry for port (no decimal/grouping formatting behavior).
- Stored/served port values remain normalized to valid range.

11. Continuity route switching must be explicit and failure-safe.

- Continuity/iPhone-style routes are manual-connect only.
- Failed manual connects must not block UI or switching loops; selection must fall back immediately to the next eligible priority.
- Priority status should remain user-comprehensible in UI (no misleading skipped rank badges for visible rows).

12. BusyLight lifecycle behavior must be deterministic.

- On first device detection after app start, run a short hello sequence before normal rule/manual evaluation.
- On app termination, send explicit BusyLight `off`.

## Consequences

- Slightly more implementation overhead per feature, but fewer regressions.
- Better user trust: UI, API, and logs consistently tell the same story.
- Faster maintenance: architectural decisions are explicit and testable.
