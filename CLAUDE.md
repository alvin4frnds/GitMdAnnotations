# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GitMdScribe — Flutter Android tablet app for pen-driven, git-synced spec review. Target device: OnePlus Pad Go 2 (Android, arm64). Phase 1 (Milestones 1a–1d) is code-complete; see `docs/PROGRESS.md` for status. The PRD (`docs/PRD/TabletApp-PRD.md`) is the source of truth for **what** to build; `docs/IMPLEMENTATION.md` is the source of truth for **how**. When in doubt, read those before writing code.

## Toolchain

Flutter is FVM-pinned (`.fvmrc` → `stable`). Use `fvm flutter …` for everything; do not invoke a system flutter. The tablet device id used in dev workflows is `NBB6BMB6QGQWLFV4` (see `docs/PROGRESS.md` for the cheatsheet).

```
fvm flutter pub get                                  # after dep changes (libgit2dart fork is git-pinned)
fvm flutter analyze                                  # lint/type check
fvm flutter test                                     # all unit + widget tests (test/)
fvm flutter test test/path/to/foo_test.dart          # a single file
fvm flutter test --name 'scenario substring'         # a single test by name
fvm flutter test integration_test/<file>.dart -d <device>   # on-device integration test
fvm flutter run -d <device>                          # debug on a real device or emulator
fvm flutter run -d <device> --release                # release run for QA / latency measurement
fvm flutter build apk --flavor dev                   # dev flavor (verbose logs, PAT fallback)
fvm flutter build apk --flavor prod                  # prod flavor
dart run flutter_launcher_icons                      # regenerate launcher icons after asset/icon changes
```

`integration_test/` requires a real Android device or emulator — `flutter test` alone (host VM) cannot run them; pdfx/libgit2dart raise `MissingPluginException` without an attached engine. Some integration tests are intentionally `skip:`ped on the host and only exercised on-device.

Build-time switches (via `--dart-define`):

- `APP_MODE=real` — switches `bootstrap.dart` from the default mockup-seeded fakes to real adapters.
- `DEV_SEED_ENABLED=true` — seeds a workdir + `RepoRef` so the JobList renders without going through RepoPicker (used while RepoPicker UI is in flight).
- `ALLOW_MOUSE_ANNOTATION=true` — relaxes the stylus-only palm-rejection rule so the emulator (no real stylus) can exercise ink flows. **Never set in release builds.**

## Architecture (read this before editing across layers)

Clean DDD layering. Arrows point down only; this is enforced by lint and by code review.

```
ui/      (lib/ui)        Flutter widgets, screens, theme
   ↓
app/     (lib/app)       Riverpod 2 notifiers + providers (composition root)
   ↓
domain/  (lib/domain)    Pure Dart — entities, ports (abstract), services
   ↓
infra/   (lib/infra)     Platform-bound adapters: libgit2dart, pdfx, dio, keystore, fs
```

**`lib/domain/` has zero Flutter imports.** It must not import `lib/infra/` or `lib/ui/` or `lib/app/`. Domain logic talks to the outside world only through ports in `lib/domain/ports/` (`GitPort`, `AuthPort`, `FileSystemPort`, `ClockPort`, `PdfRasterPort`, etc.). Adapters in `lib/infra/` implement those ports. `lib/app/` (notifiers + providers) wires ports to adapters via Riverpod overrides at the composition root in `lib/bootstrap.dart` (`buildAppScope`).

State management is **Riverpod 2 without code-gen**. `ref.read` is forbidden outside notifier files — cross-notifier coordination goes through domain services. Auth/sync/long-running state uses `AsyncValue`. Annotation session state is scoped (`autoDispose` + `family`) so it dies with the route.

**Threading:**
- UI isolate stays on the render thread. Pen events must never queue behind I/O (NFR-1: <25 ms ink latency on Pad Go 2).
- libgit2dart calls run in a dedicated long-lived `Isolate` (`infra/git/git_isolate.dart`), behind `GitAdapter`. Talk to it via `SendPort`.
- SVG parse, PNG flatten, large-markdown parse run in ephemeral `compute()` isolates.
- pdfx rasterizes on its own native thread; we just await the `Future<ui.Image>`.

**Module map** (each module is a bounded context owned by `lib/domain/services/<x>` + `lib/domain/ports/<x>` + `lib/infra/<x>` + `lib/app/(controllers|providers)/<x>`):

| Module       | Purpose                                                          |
|--------------|------------------------------------------------------------------|
| `auth`       | GitHub OAuth Device Flow + PAT fallback; token in Keystore       |
| `git`        | libgit2 ops in an isolate (clone/fetch/merge/commit/push)        |
| `spec`       | Job discovery, `PhaseResolver`, spec loading, OQ extraction      |
| `annotation` | Stroke capture, undo/redo, SVG serialization, PNG flatten        |
| `review`     | `03-review.md` assembly, changelog append, `CommitPlanner`       |
| `sync`       | Sync Down / Sync Up orchestration, remote-wins conflict          |
| `rendering`  | Markdown + PDF rendering with stable anchors; Mermaid via WebView |
| `theme`      | Design tokens, light/dark, ink-color render-time adapt           |

## Branch and file contracts (do not violate)

- Tablet **only** writes under `jobs/pending/spec-<id>/` on the `claude-jobs` sidecar branch. Never on `main`. Never deletes (append-only from tablet side).
- `05-approved` is created **only** by the tablet. The desktop watcher refuses to implement a spec without it. This is the phase gate the README calls "Claude physically cannot skip ahead."
- Annotation SVGs always store **canonical light-mode hex** (e.g., `#DC2626`). `InkColorAdapter` brightens for dark mode at render time only; round-trip to git is stable across theme changes.
- Every `<g>` stroke group has `data-anchor-line` (markdown) or `data-anchor-page`+`data-anchor-bbox` (PDF), plus `data-timestamp` and the SVG root carries `data-source-sha`. Submit Review writes `03-review.md` + `03-annotations.svg` + `03-annotations.png` + changelog append in **one atomic commit** (`CommitPlanner`).
- Changelog format: `- YYYY-MM-DD HH:mm <author>: <description>`. Local time only, no timezone suffix (D-14).
- Commit message prefixes: `review: <id>` (tablet), `approve: <id>` (tablet), `spec: <id>` (either), `revise: <id>` (desktop).

Sync Down sequence (`SyncService.syncDown`, see IMPLEMENTATION.md §4.6 D-13): `fetch origin` → fast-forward local `main` onto `origin/main` → ensure local `claude-jobs` exists → fast-forward `claude-jobs` to `origin/claude-jobs` → merge `main` into `claude-jobs`. The `main` update is mandatory; without it the sidecar misses newly pushed source files.

## Coding standards (enforced)

- **TDD is the iron law** (`docs/IMPLEMENTATION.md` §5.3). No production code without a failing test first. RED → verify failure → GREEN → verify green → REFACTOR. Bug fixes get a failing reproduction test before the fix.
- **Fakes over mocks.** Each port has an in-memory fake under `test/` (or `lib/domain/fakes/`). Tests override the Riverpod provider with the fake. Reach for a mocking library only as a last resort — if a test needs `mock.verify(...)`, the port surface is wrong.
- **Naming.** `utils/`, `helpers/`, `common/`, `shared/` are banned as module / class / file names. Names express domain roles: `ChangelogWriter`, `OpenQuestionExtractor`, `PhaseResolver`, `CommitPlanner`, `InkColorAdapter`. If you're about to name something `utils`, the bounded context is wrong.
- **Library-first.** Check pub.dev before writing utilities; custom code is for domain logic unique to this app.
- **Size limits.** Functions ≤ 50 lines. Files ≤ 200 lines. Max nesting depth 3. Early-return over nested `if`. No business logic in widgets — widgets read `AsyncValue` and render.
- **Errors.** Domain throws typed sealed exceptions (`SyncConflict`, `AuthRevoked`, `GitPushRejected`, `SpecParseError`, `DirtyWorkingTree`, `TokenExpired`). Controllers map to `AsyncValue.error` through `ErrorPresenter`. No raw `Exception` or string errors reaching the UI.
- **Ubiquitous language.** Use `Job`, `Phase`, `Anchor`, `Stroke`, `StrokeGroup`, `Review`, `SpecFile`, `SyncProgress`, `RepoRef`, `GitIdentity` verbatim — don't paraphrase in code or commits.

## Testing tiers

```
test/domain/**       Pure Dart, no Flutter binding. Fast, deterministic. Target >90% coverage.
test/app/**          Riverpod ProviderContainer with fake ports. Controller state transitions.
test/golden/**       SVG and review.md golden files.
test/infra/**, test/ui/**   Adapter and widget tests; may use tmp dirs / pumpWidget.
integration_test/**  On-device only. OAuth, full sync against bare-repo fixtures, pen latency.
```

Every Gherkin scenario in `docs/IMPLEMENTATION.md` §4 maps to at least one test file. If a scenario lacks a test, the module is incomplete regardless of how the code looks.

## Subagent-driven development

Per-task ceremony for non-trivial work (`docs/IMPLEMENTATION.md` §6.0): dispatch a fresh implementation subagent for the task → it does TDD + commits → dispatch a code-reviewer subagent → fix Critical issues with another fix subagent (don't fix manually — preserves context isolation) → mark complete. **Sequential within a milestone** (tasks share state). Don't run multiple implementation subagents in parallel on the same milestone. Per-milestone close-out adds a final review subagent + on-device QA subagent + triage subagent.

## Notable platform/dependency details

- **libgit2dart** is consumed from a git fork pinned by SHA in `pubspec.yaml` (`alvin4frnds/libgit2dart-fork`, ref `f68760e`) because the published 1.2.2 is discontinued and has no Android support. The fork ships NDK-built `libgit2.so` + mbedTLS family under `android/src/main/jniLibs/<abi>/` for `arm64-v8a`, `armeabi-v7a`, `x86_64`. Bump the SHA explicitly when rolling forward — never leave it at `main`.
- **mbedTLS CA bundle.** Our forked libgit2 links mbedTLS 2.28, which has no CA store. `assets/ca/cacert.pem` is copied to the cache dir at startup (`installBundledTrustStore` in `lib/app/ssl_trust_store.dart`) and handed to libgit2 via `Libgit2.setSSLCertLocations` — without this, every HTTPS clone from github.com fails with "certificate is not correctly signed by the trusted CA".
- **Mermaid rendering** is offline. `assets/js/mermaid.min.js` is loaded into a headless `webview_flutter` page; rendered SVG comes back through a JS channel and is cached on disk by SHA-256 (`MermaidCache`). Cache key normalizes CRLF→LF. Renderer is consumed only from `lib/ui/widgets/mermaid_view/`.
- **PDF renderer is fixed as `pdfx`** (D-12). MIT licensed; no runtime swap. Domain code talks to `PdfRasterPort`; the adapter lives in `lib/infra/pdf/pdfx_adapter.dart`.
- **Backups.** PRD §5.7 says `~/GitMdScribe/backups/…` but Android scoped storage (API 29+) makes that inaccessible. The actual path is `getApplicationDocumentsDirectory() + "/backups/<repo>/<branch>-<timestamp>/"`. Settings → "Export backups" surfaces them via Storage Access Framework (`shared_storage` package).
- **Bundled fonts** (Inter, JetBrainsMono) are required — without them `fontFamily: 'monospace'` falls back to Roboto on Android and the header breadcrumb renders with squiggly-underline artifacts.

## When the user references docs

- `docs/PRD/TabletApp-PRD.md` — what to build (requirements, data model, theme tokens).
- `docs/PRD/mockups.html` — 12-screen interactive mockup (open in a browser; `d` toggles light/dark).
- `docs/IMPLEMENTATION.md` — how to build (architecture, module specs, milestones, acceptance criteria).
- `docs/PROGRESS.md` — live milestone tracker; the toolchain cheatsheet for Windows + Pad Go 2 lives here.
- `docs/Issues.md` — deferred Medium/Low defects; check before reporting "new" bugs.
- `docs/initial/ProblemStatement.txt` — motivation and the user-journey vignette.
