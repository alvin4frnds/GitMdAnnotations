# GitMdScribe — Tablet App Implementation Doc

> Phase 1 (Milestones 1a–1d). Companion to [TabletApp-PRD.md](PRD/TabletApp-PRD.md).
> Authoring bias: architecture-first, subagent-driven, TDD.
> Applies the `ddd:software-architecture`, `sadd:subagent-driven-development`, and `test-driven-development` skills — see §2.6, §5.3, §6.0.

## 0. How to read this doc

This is a single monolithic spec for building Phase 1 (spec **review**) of the tablet app. Phase 2 (spec **authoring**) is deliberately out of scope here and appears only where it constrains Phase 1 decisions (e.g., module boundaries that must absorb Phase 2 later without refactor).

- §1 — scope, non-goals, target platform
- §2 — runtime architecture: layers, modules, state, threading, DI
- §3 — data & file contracts (git layout, SVG schema, review.md schema, changelog)
- §4 — per-module specs (requirements digest + public API + TDD criteria)
- §5 — directory layout and build/tooling
- §6 — milestone plan with TDD-first task breakdown
- §7 — consolidated acceptance criteria
- §8 — open questions, risks, judgment calls

The PRD remains the source of truth for **what** to build. This doc is the source of truth for **how**. Where they disagree, the PRD wins and this doc is wrong — file an issue.

---

## 1. Scope

### 1.1 In scope (Phase 1 = Milestones 1a–1d per PRD §13)

- **1a.** GitHub OAuth (Device Flow), repo picker, `claude-jobs` branch bootstrap, Sync Down, markdown read-only rendering, offline cache.
- **1b.** Pen annotation canvas (pressure + palm rejection), SVG serialization, PDF page rendering + annotation.
- **1c.** Typed review panel, Submit Review, Approve, Sync Up, changelog writer, remote-wins conflict handling.
- **1d.** Polish: history timeline, changelog viewer, local backup folder UI, edge-case recovery.

### 1.2 Out of scope

- Phase 2 spec authoring, templates, on-device linting.
- Push notifications (Phase 2b via GitHub Actions; see PRD §10.6).
- Handwriting-to-text / dictation (Phase 2c).
- iPadOS port (D-1: Android-only at launch).
- Signed commits (D-2: OAuth token only).
- Any backend, proxy, or server. Git is the bus.

### 1.3 Target platform

- **Device:** OnePlus Pad Go 2 (Android, ~90 Hz, pressure-sensitive active stylus) — PRD §3.2.
- **Min SDK:** Android 10 (API 29) for scoped-storage compliance; target SDK 34.
- **Framework:** Flutter, single codebase. iPadOS is a forward-compatibility concern, not a build target.

---

## 2. Architecture

### 2.1 Layer diagram

```
+--------------------------------------------------------------------------+
|  PRESENTATION  (lib/ui)                                                  |
|  Screens:  SignIn | RepoPicker | JobList | SpecReader | ReviewPanel      |
|            AnnotationCanvas | ChangelogViewer | SyncStatusBar | Settings |
|  Widgets:  ThemedScaffold, InkOverlay, PdfPageView, MarkdownView         |
+-------------------------------↓------------------------------------------+
|  APPLICATION / STATE  (lib/app) — Riverpod 2                             |
|  Notifiers:  AuthController | RepoController | JobListController         |
|              SpecController | AnnotationController                       |
|              ReviewController | SyncController | ThemeController         |
|  Cross-cutting: AppRouter (go_router), Logger, FeatureFlags              |
+-------------------------------↓------------------------------------------+
|  DOMAIN  (lib/domain — pure Dart, zero Flutter imports)                  |
|  Entities: Job, SpecFile, Stroke, StrokeGroup, Review, ChangelogEntry,   |
|            Commit, RepoRef, Phase, Anchor, AuthSession                   |
|  Services: PhaseResolver, AnchorResolver, ChangelogWriter,               |
|            ReviewSerializer, SvgSerializer, ConflictResolver,            |
|            CommitPlanner, OpenQuestionExtractor                          |
|  Ports (abstract):  GitPort | AuthPort | SecureStoragePort |             |
|                     FileSystemPort | MarkdownParserPort |                |
|                     PdfRasterPort | ClockPort | LoggerPort               |
+-------------------------------↓------------------------------------------+
|  INFRASTRUCTURE  (lib/infra — platform-bound adapters)                   |
|  GitAdapter (libgit2dart/FFI + isolate)  AuthAdapter (dio + Device Flow) |
|  KeystoreAdapter (flutter_secure_        FsAdapter (path_provider)       |
|   storage)                               PdfAdapter (pdfx)               |
|  MarkdownAdapter (flutter_markdown)      ClockAdapter (DateTime.now)     |
|  IsolateRunner (compute + Isolate.spawn)                                 |
+--------------------------------------------------------------------------+
            ↓                  ↓                ↓
      [ Android OS ]     [ libgit2 FFI ]   [ GitHub REST ]
```

**Dependency rule:** arrows point downward only. `domain` imports nothing from `infra` or `app` or `ui`. `app` composes domain ports with infra adapters at startup via Riverpod overrides. This is enforced by `analysis_options.yaml` import-boundary lints.

### 2.2 State management — Riverpod 2

**Chosen:** Riverpod 2 with code-gen (`riverpod_generator`).

Reasoning:

1. **Override-based DI matches our port/adapter split.** Every `Port` is a `Provider`; tests override with fakes without a separate DI framework.
2. **`AsyncValue` is a natural fit for auth/sync states** (loading / data / error). Bloc would require a dedicated event stream per controller for the same outcome.
3. **Scoped disposal via `autoDispose` + `family`.** Annotation session state must die when the SpecReader screen pops — Riverpod gives this per-job, scoped to the route.

Tradeoff: `ref.read` can be abused into a global service locator. Mitigation: a lint rule forbids `ref.read` outside notifiers; cross-notifier coordination goes through explicit domain services.

### 2.3 Cross-cutting concerns

- **Logging.** `LoggerPort` with levels; the infra adapter writes to a rolling file in the app documents dir plus stderr in debug. Every sync / commit / auth event logs a structured entry. No PII beyond repo names and usernames the user already signed in as.
- **Error handling.** Domain throws typed sealed exceptions: `SyncConflict`, `AuthRevoked`, `GitPushRejected`, `SpecParseError`, `DirtyWorkingTree`, `TokenExpired`. Controllers catch at the boundary and emit `AsyncValue.error` mapped through a single `ErrorPresenter`. No raw exceptions reach the UI.
- **Feature flags.** `FeatureFlags` backed by `--dart-define` at build time (not runtime toggles). Phase 1 flags: `enablePdfSupport`, `enablePatFallback`, `enableCrashReporting`.
- **Telemetry (PRD §15).** Opt-in only. A local `MetricsSink` records M-1 / M-4 / M-5 timings to a local SQLite file; a debug screen surfaces them. No network export in MVP.
- **Background work.** None in Phase 1. Sync is strictly user-driven (FR-1.33). Android WorkManager is not wired.

### 2.4 Threading model

- **UI isolate** stays on the render thread. Pen events must never queue behind I/O — this is a hard rule, driven by NFR-1 (<25 ms ink latency).
- **Long-lived git isolate.** `GitAdapter` spawns a dedicated `Isolate` at first use. libgit2dart FFI calls block — running them on the UI isolate would stall pen ink during sync. Communication via `SendPort`; `SyncProgress` streams back to `SyncController`.
- **Ephemeral `compute()` isolates** for: SVG parsing on load, PNG flattening on Submit Review, markdown parsing for Open-Question extraction on specs larger than ~50 KB.
- **PDF rasterization.** `pdfx` runs on a native background thread internally; we consume `Future<ui.Image>` directly.
- **Auto-save timer** (FR-1.24): `Timer.periodic(3s)` on the UI isolate writing small review drafts. Not isolated — latency budget allows.

### 2.5 Module map

| Module        | Owns                                                    | Depends on                  |
|---------------|---------------------------------------------------------|-----------------------------|
| `auth`        | OAuth Device Flow, PAT fallback, token lifecycle        | `SecureStoragePort`, HTTP   |
| `git`         | libgit2 ops: clone, fetch, merge, commit, push          | `libgit2dart`, `AuthPort`, `FileSystemPort` |
| `spec`        | Job discovery, phase resolution, spec loading           | `FileSystemPort`, `MarkdownParserPort` |
| `annotation`  | Pen stroke capture, undo/redo, SVG + PNG serialization  | `domain/entities` only      |
| `review`      | `03-review.md` assembly, changelog append, commit plan  | `annotation`, `spec`, `ClockPort` |
| `sync`        | Sync Down / Sync Up orchestration, conflict resolution  | `GitPort`, `FileSystemPort` |
| `rendering`   | Markdown + PDF rendering, stable anchors                | `flutter_markdown`, `pdfx`  |
| `theme`       | Design tokens, light/dark resolution, ink-color adapt   | (none)                      |

Module boundaries are sized so one subagent can own one module end-to-end later, as the user's subagent-driven development practice requires. Public API surfaces are defined in `domain/ports/` so adapters can be swapped without touching controllers.

### 2.6 Ubiquitous language and coding standards

Derived from the `ddd:software-architecture` skill. These are enforceable rules, not suggestions — `analysis_options.yaml` carries lints for the mechanical ones.

**Ubiquitous language.** The domain vocabulary is fixed. Use these terms in code, commit messages, and conversation; don't paraphrase.

| Term            | Meaning                                                             |
|-----------------|---------------------------------------------------------------------|
| `Job`           | One spec-review unit, corresponds to `jobs/pending/spec-<id>/`      |
| `Phase`         | `spec` \| `review` \| `revised` \| `approved`                       |
| `Anchor`        | `(sourceSha, lineNumber)` or `(sourceSha, page, bbox)`              |
| `Stroke`        | One continuous pen interaction                                      |
| `StrokeGroup`   | SVG `<g>` — one or more strokes sharing an anchor and timestamp     |
| `Review`        | The `03-review.md` artifact                                         |
| `SpecFile`      | Either `02-spec.md` / `04-spec-v*.md` or a source `.pdf`            |
| `SyncProgress`  | Sealed state emitted by `SyncService`                               |
| `RepoRef`       | `(owner, name, default-branch)`                                     |
| `GitIdentity`   | `(name, email)` from `GET /user`                                    |

**Library-first.** Before writing any custom utility, check pub.dev. Examples the PRD already commits to: `libgit2dart`, `flutter_markdown`, `pdfx`, `flutter_secure_storage`, `riverpod`, `dio`, `url_launcher`, `path_provider`, `go_router`. Retry logic uses an established package (e.g., `cockatiel`-equivalent in Dart land); we do not hand-roll it. Custom code is allowed only for domain logic unique to this app (e.g., `PhaseResolver`, `SvgSerializer`, `AnnotationSession`).

**Naming.** Never use `utils/`, `helpers/`, `common/`, `shared/` as a module, class, or file name. Names express a domain role: `ChangelogWriter`, `OpenQuestionExtractor`, `PhaseResolver`, `CommitPlanner`, `InkColorAdapter`. If you're about to name something `utils`, stop — that's a sign the bounded context is wrong.

**Size limits.**

- Functions: ≤ 50 lines. Decompose if longer.
- Files: ≤ 200 lines. Split by responsibility if longer (not alphabetically).
- Max nesting depth: 3.

**Structure rules.**

- Early return over nested `if`.
- No business logic in widgets. Widgets read `AsyncValue` and render; controllers decide.
- No I/O in domain. Ports only.
- Typed sealed exceptions (§2.3), never bare `Exception` or `String`.
- One module = one bounded context. Cross-module imports go through public ports; cross-module concrete imports are a lint error.

**Enforcement.**

- `analysis_options.yaml` lints: `prefer_single_quotes`, `avoid_relative_lib_imports`, a custom `import_lint` rule forbidding `lib/domain/**` from importing `lib/infra/**` or `lib/ui/**`, and forbidding `ref.read` outside notifier files.
- PR-time check: a script scans for banned names (`utils`, `helpers`, `common`, `shared`) in any new file path and fails CI.

---

## 3. Data & File Contracts

### 3.1 Branch strategy (PRD §5.2, §8.1, D-8)

- **`main` (or repo default):** user's source branch. Tablet **never** writes here.
- **`claude-jobs`:** sidecar branch. Contains all tablet artifacts plus the merged-in `main` tree for desktop context.
- **Bootstrap:** on first Sync Down, if `origin/claude-jobs` is missing, create it locally from `origin/main` and push.
- **Invariant:** the `jobs/` directory never appears on `main`.

### 3.2 Job folder layout on `claude-jobs` (PRD §8.2)

```
jobs/pending/spec-<id>/
├── 02-spec.md                 # Desktop (or tablet in Phase 2) authored
├── 02-author-tablet           # Marker; Phase 2 only (signals tablet authored 02-spec.md)
├── 03-review.md               # Tablet writes: typed answers + spatial refs
├── 03-annotations.svg         # Markdown: strokes, text-serialized (git-diffable)
├── 03-annotations.png         # Markdown: rendered snapshot (fidelity)
├── 03-annotations-p{n}.svg    # PDF: per-page strokes
├── 03-annotations-p{n}.png    # PDF: per-page snapshots
├── 04-spec-v2.md              # Desktop writes; may loop (v3, v4, …)
├── 05-approved                # Empty marker file; TABLET-ONLY creator
├── CHANGELOG.md               # PDF specs only; mirrors the `.md`-bottom pattern
└── meta.json                  # { id, created_at, tags, target_area }
```

**Critical phase-gate invariant:** `05-approved` can only be created by the tablet. The desktop watcher refuses to implement a spec unless this sentinel exists. The desktop only *deletes* it, as part of folder deletion after implementation. This is what the README calls "Claude physically cannot skip ahead."

### 3.3 Changelog format (PRD §8.3, D-6)

At the bottom of each `.md` file (or in the sidecar `CHANGELOG.md` for PDFs):

```markdown
## Changelog

- 2026-04-20 14:32 tablet: User clarified auth flow — TOTP required.
- 2026-04-20 16:05 desktop: Spec revised to v2; added TOTP section.
```

Format: `- YYYY-MM-DD HH:mm <author>: <human description>`. Author is `tablet`, `desktop`, or a future agent name. Timestamps are **always local time** from the writing device (tablet clock for tablet entries, desktop clock for desktop entries) — no timezone suffix, no UTC. Cross-timezone ambiguity is accepted as out of scope per D-11.

### 3.4 Annotation SVG schema (PRD §8.4)

```svg
<svg xmlns="http://www.w3.org/2000/svg"
     data-source-file="02-spec.md"
     data-source-sha="a3f91c...">
  <g id="stroke-group-A"
     data-anchor-line="47"
     data-timestamp="2026-04-20T09:14:22Z">
    <path d="M120,340 Q..." stroke="#DC2626" stroke-width="2.1" opacity="0.9"/>
  </g>
</svg>
```

For PDFs: replace `data-anchor-line="47"` with `data-anchor-page="3"` and `data-anchor-bbox="120,340,180,380"`.

**Ink colors are canonical light-mode hex** (e.g., `#DC2626` red). The UI adapts at render time based on theme — see §4.8.

### 3.5 `03-review.md` structure (PRD §8.5)

```markdown
# Review — spec-<id>
**Source:** 02-spec.md @ <sha>   (or spec.pdf)
**Reviewed at:** 2026-04-20 09:32 local time

## Answers to open questions

### Q1: Should auth flow support magic links?
> Answer text. See stroke group A at line 47.

### Q2: ...

## Free-form notes

- Notes referencing spatial anchors.

## Spatial references

- Stroke group A → line 47 (description)
```

### 3.6 Commit message conventions (PRD §9)

| Message prefix    | Created by | Effect                                                           |
|-------------------|------------|------------------------------------------------------------------|
| `review: <id>`    | Tablet     | `03-*` files present; desktop watcher triggers revision          |
| `approve: <id>`   | Tablet     | `05-approved` present; desktop watcher triggers implementation   |
| `spec: <id>`      | Either     | New `02-spec.md` or tablet-authored Phase 2                      |
| `revise: <id>`    | Desktop    | New `04-spec-v*.md` appears                                      |

All commits carry the user's GitHub git identity (name + email from `/user`). No signing in MVP (D-2).

### 3.7 Data integrity invariants

Enforced as unit-test-visible preconditions in `CommitPlanner`:

- Every stroke group has `data-anchor-line` (markdown) or `data-anchor-page` + `data-anchor-bbox` (PDF).
- Every SVG carries `data-source-sha` of the source file version reviewed.
- PNG snapshot and SVG are created in the same commit — missing either blocks Sync Up.
- Each stroke group has `data-timestamp`.
- Changelog entry is appended atomically with the file creation (single commit).
- Tablet never deletes files on `claude-jobs` (append-only from tablet side).

### 3.8 Schema versioning

No schema version field in MVP. Forward-compat is deferred. Desktop Claude parses SVG with graceful degradation on unknown attributes. If schema changes post-MVP, add `data-schema-version` to SVG root and a `<!-- review-schema: 2 -->` HTML comment to `03-review.md`.

---

## 4. Module Specs

Each module below follows the same template:
1. **Responsibility** (one sentence)
2. **Public API** (domain port + key domain services)
3. **Functional requirements** (PRD-sourced, numbered)
4. **Error / edge cases**
5. **Acceptance criteria** (TDD: given / when / then)
6. **Libraries & config**

### 4.1 `auth` module (Milestone 1a)

**Responsibility.** Own GitHub OAuth Device Flow, PAT fallback, and access-token lifecycle.

**Public API.**
```dart
abstract class AuthPort {
  Stream<DeviceCodeChallenge> startDeviceFlow();
  Future<AuthSession> pollForToken(DeviceCodeChallenge c);
  Future<AuthSession> signInWithPat(String pat);
  Future<void> signOut();
  Future<AuthSession?> currentSession();
}

class AuthSession {
  final String token;
  final GitIdentity identity; // { name, email }
}
```

**Functional requirements** (PRD §5.1, §5.10):

1. Initiate OAuth Device Flow with a public, binary-baked `client_id`; no client secret.
2. Display `user_code` (e.g., `WDJB-MJHT`) and launch Chrome Custom Tab to `verification_uri`.
3. Poll `POST /login/oauth/access_token` at 5s intervals; honor `slow_down` by adding 5s.
4. On `access_token`, fetch `GET /user`, cache `(name, email)` + token in Android Keystore via `flutter_secure_storage`.
5. PAT fallback: user pastes fine-grained PAT (scopes: `contents:write`, `metadata:read`); app calls `/user` to validate; same downstream flow.
6. All GitHub API calls use `Authorization: Bearer <token>`; git push/fetch use the token as HTTPS password.
7. On any 401, discard token and route back to sign-in. No silent-refresh loop in MVP (tokens do not expire per OAuth App config).
8. Single account per device (multi-account is post-MVP).

**Error / edge cases.**

| Case                              | Handling                                                              |
|-----------------------------------|-----------------------------------------------------------------------|
| Device code expires (900s)        | Restart Device Flow from scratch                                      |
| Mid-flow app kill                 | Relaunch resumes polling with same `device_code` if still valid       |
| `slow_down` response              | Interval += 5s, persists for remainder of that flow                   |
| `authorization_pending`           | Keep polling at current interval                                      |
| `expired_token`                   | Restart Device Flow                                                   |
| Enterprise proxy blocks Device Flow | User falls back to PAT paste-in                                      |
| Token revoked at github.com       | Next 401 → discard → sign-in screen                                   |
| Invalid PAT                       | `/user` returns 401 → "Invalid token" error → retry                   |
| Factory reset / Keystore wipe     | User re-authenticates; no recovery flow needed                        |

**Acceptance criteria.**

```gherkin
Scenario: Fresh install Device Flow sign-in
  Given app has no stored session
  When user taps "Sign in with GitHub"
  Then app POSTs /login/device/code with public client_id
    And user_code is displayed
    And Chrome Custom Tab opens verification_uri
    And app polls /login/oauth/access_token every 5s
  When user approves in browser
  Then access_token is returned
    And token + identity are persisted to Android Keystore
    And user lands on repo picker

Scenario: slow_down backoff
  Given app is polling at 5s intervals
  When GitHub responds with { "error": "slow_down" }
  Then subsequent polls use 10s interval

Scenario: Revoked-token recovery
  Given user has a valid session
  When user revokes access at github.com and then taps Sync Up
  Then git push fails with 401
    And app discards token and routes to sign-in
    And next Sync Up after re-auth succeeds

Scenario: PAT fallback
  Given user pastes a valid fine-grained PAT
  When app calls GET /user
  Then 200 response → token stored → repo picker visible

Scenario: PAT invalid
  Given user pastes an invalid PAT
  When app calls GET /user
  Then 401 response → "Invalid token" error → input field cleared
```

**Libraries & config.**

| Dependency                   | Notes                                                    |
|------------------------------|----------------------------------------------------------|
| `flutter_secure_storage`     | Hardware-backed via Android Keystore                     |
| `dio` or `http`              | Device Flow POST + /user GET                             |
| `url_launcher` (Chrome Tabs) | Launch verification_uri                                  |
| GitHub OAuth App config      | Device Flow enabled; "Expire user tokens" OFF in MVP     |

---

### 4.2 `git` module (Milestone 1a core, 1c push)

**Responsibility.** All libgit2 operations. Stateless — every call takes a repo workdir and returns.

**Public API.**
```dart
abstract class GitPort {
  Future<void> cloneOrOpen(RepoRef r, {required String workdir});
  Future<void> fetch(RepoRef r, {required String branch});
  Future<void> mergeInto(String sourceBranch, {required String target});
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
  });
  Future<PushOutcome> push(RepoRef r, {required String branch});
  Future<void> resetHard(String ref);
  Future<BackupRef> backupBranchHead(String branch, {required String backupRoot});
  Future<List<ChangelogEntry>> readChangelog(String path);
}

sealed class PushOutcome {
  const PushOutcome();
}
class PushSuccess extends PushOutcome { ... }
class PushRejectedNonFastForward extends PushOutcome { ... }
class PushRejectedAuth extends PushOutcome { ... }
```

**Functional requirements** (PRD §5.2, §5.7–5.9, §9):

1. `Sync Down`: `fetch origin` → fast-forward (rebase) local `main` onto `origin/main` so the tracking branch is current → ensure local `claude-jobs` exists (create from `origin/main` if not) → merge `main` (now current) into local `claude-jobs`. The initial `main` update is required so newly pushed source items land in `claude-jobs`; skipping it would leave the sidecar stale (D-13).
2. `Sync Up`: `push origin claude-jobs`; on non-fast-forward, trigger conflict flow (see §4.6).
3. Commits are atomic: `commit()` writes all `FileWrite` entries and creates exactly one commit.
4. All commits use the identity returned by `AuthPort.currentSession().identity`.
5. Tablet writes **only** under `jobs/pending/spec-<id>/` on `claude-jobs`.
6. `readChangelog` parses the `## Changelog` section of a `.md` file or a sidecar `CHANGELOG.md` into `ChangelogEntry` records.

**Error / edge cases.**

| Case                           | Handling                                                         |
|--------------------------------|------------------------------------------------------------------|
| Detached HEAD (remote)         | Surface loudly; do not auto-recover                              |
| Force-push from desktop        | Sync Down detects divergence → conflict flow (remote wins)       |
| Dirty working tree on Sync Down | Refuse; prompt "Commit or discard?"                              |
| Corrupted `.git`               | Surface libgit2 error verbatim; suggest manual `git fsck`        |
| 401 during push/fetch          | Map to `PushRejectedAuth`; caller triggers `auth` re-sign-in     |
| Merge conflict on `main` → `claude-jobs` | Rare by design; remote wins (§4.6)                    |

**Acceptance criteria.**

```gherkin
Scenario: First Sync Down creates claude-jobs from main
  Given repo has no origin/claude-jobs branch
  When SyncController.syncDown runs
  Then local claude-jobs is created from origin/main
    And pushed to origin/claude-jobs

Scenario: Commit is atomic
  Given a ReviewController submission with 3 file writes
  When GitPort.commit runs
  Then exactly one commit exists containing all 3 files
    And HEAD advances once

Scenario: Push rejection surfaces as typed outcome
  Given remote claude-jobs has newer commits
  When SyncController.syncUp runs
  Then GitPort.push returns PushRejectedNonFastForward
    And SyncController triggers ConflictResolver
```

**Libraries & config.**

- `libgit2dart` (FFI bindings to libgit2). Pin exact version; commit `pubspec.lock`.
- libgit2 built from source in CI with a caching step (build is slow).
- Runs in a dedicated long-lived `Isolate`. Messages cross via `SendPort`.

---

### 4.3 `spec` module (Milestone 1a)

**Responsibility.** Discover jobs on disk, resolve current phase, load spec content, extract Open Questions.

**Public API.**
```dart
abstract class SpecRepository {
  Future<List<Job>> listOpenJobs(RepoRef r);
  Future<SpecFile> loadSpec(JobRef j);
  Future<List<ChangelogEntry>> readChangelog(JobRef j);
}

class PhaseResolver {
  Phase resolve(Set<String> filesInJobDir);
}

class OpenQuestionExtractor {
  List<OpenQuestion> extract(String markdown);
}

enum Phase { spec, review, revised, approved }
```

**Functional requirements** (PRD §5.3).

1. List all folders under `jobs/pending/` on `claude-jobs` as `Job` records.
2. For each job, derive phase from file set: `05-approved` → `approved`; `04-spec-v*.md` → `revised`; `03-review.md` → `review`; `02-spec.md` → `spec`.
3. Load the latest version of the spec (highest `04-spec-v*.md` or `02-spec.md`).
4. Parse `## Open Questions` section for the typed review panel.
5. Support both markdown (`02-spec.md`) and PDF (`spec.pdf`) sources.

**Acceptance criteria.**

```gherkin
Scenario: Phase resolution truth table
  Given a job folder with files {02-spec.md}
  Then PhaseResolver returns Phase.spec
  Given {02-spec.md, 03-review.md}
  Then Phase.review
  Given {02-spec.md, 03-review.md, 04-spec-v2.md}
  Then Phase.revised
  Given {02-spec.md, 03-review.md, 04-spec-v2.md, 05-approved}
  Then Phase.approved

Scenario: Open question extraction
  Given a spec with "## Open Questions\n\n### Q1: Redis?\n### Q2: Caching?\n"
  When OpenQuestionExtractor.extract runs
  Then result = [OpenQuestion(Q1, "Redis?"), OpenQuestion(Q2, "Caching?")]
```

All derivations are pure functions. Inject an in-memory `FileSystemPort` for tests; no real I/O required.

---

### 4.4 `rendering` module (Milestone 1a markdown, 1b PDF)

**Responsibility.** Render markdown and PDF pages with stable content-coordinate anchors so strokes survive scroll and reflow.

**Public API.**
```dart
abstract class MarkdownRenderer {
  Widget build(String md, ThemeSpec t);
  Anchor anchorAtOffset(Offset o);          // logical → anchor
  Offset? offsetForAnchor(Anchor a);        // anchor → logical (may return null after reflow)
}

abstract class PdfRenderer {
  Future<ui.Image> page(int n, Size target);
  Anchor anchorFor(int page, Rect bbox);
}
```

**Functional requirements** (PRD §5.3, §10.2, §10.4, §10.5).

**Markdown:**
1. CommonMark + GFM (tables, strikethrough, task lists, fenced code).
2. Syntax-highlighted read-only code blocks.
3. Heading navigation rail; sticky section header on scroll.
4. Typography tuned to ~40 chars/line.
5. Library: `flutter_markdown`.

**PDF:**
1. Page-by-page rendering; fit-to-width default; pinch-zoom supported.
2. Lazy-load pages.
3. No native text selection in MVP; pages are treated as images.
4. Library: **`pdfx`** (MIT-licensed, open source). Fixed per D-12. No runtime renderer swap.

**Anchor contract:**
- Markdown: `Anchor.line(lineNumber, sourceSha)`.
- PDF: `Anchor.pdfRegion(page, bbox, sourceSha)`.
- Anchors embed `sourceSha` so that when `04-spec-v2.md` ships with shifted line numbers, the desktop watcher can re-anchor against the original `sourceSha` snapshot.

**Performance budget** (PRD §7):

- **NFR-1:** pen latency <25 ms on Pad Go 2.
- **NFR-2:** cold launch → last-opened job <2 s on Wi-Fi, <3 s offline.
- Target 60 FPS scroll.

**Error / edge cases.**

- Huge specs (>10 MB PDF, >10k lines markdown): lazy-page PDF; LRU eviction of non-active job caches (NFR-9, 1 GB budget).
- CRLF vs LF: libgit2 normalizes on checkout; SVG anchors operate on normalized content.
- Re-anchoring on spec revision: `data-source-sha` captures the source version reviewed; desktop re-anchors.
- Stylus hover vs touch: distinguish via `PointerDeviceKind.stylus` vs `.touch`.
- Rotation: markdown reflows; PDF zoom resets.
- Split-screen: treated as full-window.

**Acceptance criteria.**

```gherkin
Scenario: Anchor stability across scroll
  Given a 1000-line markdown rendered at offset 0
  When user scrolls 500 px
  Then MarkdownRenderer.anchorAtOffset(newOffset) still maps to the correct line

Scenario: PDF lazy-load budget
  Given a 200-page PDF
  When user opens page 1
  Then only pages 1-3 are rasterized
    And memory residency stays < 200 MB
```

---

### 4.5 `annotation` module (Milestone 1b)

**Responsibility.** Capture pen strokes, own the undo/redo stack, serialize to SVG, flatten to PNG.

**Public API.**
```dart
class AnnotationSession {
  AnnotationSession({required Anchor initialAnchor, required InkTool tool});

  void beginStroke(PointerDownEvent e);
  void extendStroke(PointerMoveEvent e);
  void endStroke(PointerUpEvent e);

  void undo();              // ≥50 steps
  void redo();

  List<StrokeGroup> snapshot();
  void setTool(InkTool t);
}

abstract class SvgSerializer {
  String serialize(List<StrokeGroup> groups, SpecRef src);
}

abstract class PngFlattener {
  Future<Uint8List> flatten(List<StrokeGroup> groups, Size canvas);
}

enum InkTool { pen, highlighter, line, arrow, rect, circle, eraser }
```

**Functional requirements** (PRD §5.4, §10.2).

1. Pen-only input: capture stylus `PointerEvent`s; ignore finger events on the ink layer (finger scrolls/pans/zooms the underlying renderer).
2. Pressure + tilt captured from `PointerEvent.pressure`, `.tilt`.
3. Palm rejection: derive from `PointerDeviceKind.stylus` only; ignore `.touch`.
4. Latency: <25 ms end-to-end (NFR-1).
5. Serialize to SVG on pointer-up (per stroke group).
6. Primitives: freehand, line, arrow, rect, circle, highlighter, eraser.
7. Color palette: 6 presets (black, red, blue, green, yellow, orange) + eraser. Canonical light-mode hex stored in SVG.
8. Undo/redo depth ≥ 50.
9. Capture timestamp per stroke group: `data-timestamp="2026-04-20T09:14:22Z"`.

**Acceptance criteria.**

```gherkin
Scenario: Palm rejection
  Given the annotation canvas is active
  When a touch event (PointerDeviceKind.touch) fires
  Then no stroke is created
  When a stylus event fires on the same coordinate
  Then a stroke begins

Scenario: SVG serialization golden
  Given a scripted sequence of 3 strokes with known pressures and anchors
  When SvgSerializer.serialize runs
  Then output matches golden file test/golden/three_strokes.svg

Scenario: Undo depth
  Given 60 strokes drawn
  When user undoes 50 times
  Then 10 strokes remain
    And further undo is a no-op

Scenario: Pen latency budget
  Given stylus touching the screen on Pad Go 2
  When a stroke is drawn
  Then visual feedback appears within 25 ms of PointerMove
```

**Implementation notes.**

- UI layer: `Listener` widget feeds a `CustomPainter` that paints the current stroke from a `ValueNotifier<List<Offset>>`. Avoids rebuilding the full tree on every pointer event.
- SVG serialization runs on pointer-up in the UI isolate (string work is fast for per-stroke-group size). PNG flattening runs in `compute()` to avoid jank on Submit Review.

---

### 4.6 `sync` module (Milestone 1a Sync Down, 1c Sync Up + conflicts)

**Responsibility.** Sequence Sync Down and Sync Up. Handle remote-wins conflicts with on-device backup.

**Public API.**
```dart
class SyncService {
  Stream<SyncProgress> syncDown(RepoRef r);
  Stream<SyncProgress> syncUp(RepoRef r);
}

class ConflictResolver {
  Future<BackupRef> archiveAndReset(RepoRef r);
}

sealed class SyncProgress { ... }
class SyncStarted extends SyncProgress { ... }
class SyncFetching extends SyncProgress { ... }
class SyncConflictArchived extends SyncProgress { final BackupRef backup; ... }
class SyncComplete extends SyncProgress { ... }
class SyncFailed extends SyncProgress { final SyncError error; ... }
```

**Functional requirements** (PRD §5.7, §5.8, §5.9, D-4, D-7, D-9).

1. Sync Down:
   - `git fetch origin`.
   - Fast-forward (rebase) local `main` onto `origin/main`. If local `main` has diverged from `origin/main` (should never happen — tablet never commits to `main`), abort with `DirtyWorkingTree`-class error. This step ensures step 4 pulls the *latest* source into the sidecar.
   - If local `claude-jobs` missing, create from `origin/main` and push.
   - Fast-forward local `claude-jobs` to `origin/claude-jobs`.
   - Merge the updated local `main` into local `claude-jobs` so desktop has the latest source context.
   - On merge conflict → remote wins (§4.6 below).
2. Sync Up:
   - `git push origin claude-jobs`.
   - On non-fast-forward rejection → conflict flow.
3. Conflict flow (remote wins):
   - Copy local `claude-jobs` HEAD into backup dir.
   - Reset local to `origin/claude-jobs`.
   - Merge `origin/main` on top.
   - Emit `SyncConflictArchived(backup)` so UI can surface "Local changes archived — remote took precedence."
4. Both sync operations are idempotent with no intermediate commits.
5. Sync is always manual (FR-1.33). No background sync. No push notifications in Phase 1.

**Backup path.** PRD §5.7 writes `~/GitMdScribe/backups/<repo>/<branch>-<timestamp>/`. On Android scoped storage (>= API 29), this resolves to the app's documents directory: `getApplicationDocumentsDirectory() + "/backups/<repo>/<branch>-<timestamp>/"`. A Settings screen "Export backups" action surfaces them via the Storage Access Framework.

**Offline behavior** (FR-1.34, §5.8).

| Operation                          | Offline? | Notes                                                  |
|------------------------------------|----------|--------------------------------------------------------|
| Open job list, view cached specs   | ✓        | Read-only; lists from last Sync Down                   |
| Render markdown / PDF              | ✓        | Cached content                                         |
| Annotate (pen + typed)             | ✓        | Local; queued for later sync                           |
| Submit Review                      | ✓        | Local commit to `claude-jobs`                          |
| Approve                            | ✓        | Local commit creating `05-approved`                    |
| Sync Down / Sync Up                | ✗        | Fails loudly; no retry loop                            |

Local unpushed commit count shown as a badge (FR-1.31, FR-1.35).

**Acceptance criteria.**

```gherkin
Scenario: Sync Down fast-forwards main before merging into claude-jobs
  Given origin/main has 3 commits ahead of local main
    And origin/claude-jobs exists
  When SyncService.syncDown runs
  Then local main is fast-forwarded to origin/main
    And local claude-jobs is fast-forwarded to origin/claude-jobs
    And local main is merged into local claude-jobs (single merge commit)
    And new files from main are visible in the workdir under claude-jobs
    And SyncComplete is emitted

Scenario: Sync Down happy path (no new main commits)
  Given origin/main and local main are equal
    And origin/claude-jobs exists
  When SyncService.syncDown runs
  Then main fast-forward is a no-op
    And merge into claude-jobs is a no-op
    And SyncComplete is emitted

Scenario: Remote-wins conflict on Sync Up
  Given local claude-jobs has 2 commits ahead
    And origin/claude-jobs has 1 commit ahead (diverged)
  When SyncService.syncUp runs
  Then push is rejected (non-fast-forward)
    And ConflictResolver.archiveAndReset runs
    And local backup exists at <appdocs>/backups/<repo>/<branch>-<ts>/
    And local HEAD == origin/claude-jobs HEAD after merge

Scenario: Dirty tree refuses Sync Down
  Given uncommitted changes in the workdir
  When user taps Sync Down
  Then app shows "You have unsaved changes. Commit or discard?"
    And no fetch runs
```

---

### 4.7 `review` module (Milestone 1c)

**Responsibility.** Assemble `03-review.md`, append changelog entries, plan the Submit Review / Approve commits.

**Public API.**
```dart
class ReviewSerializer {
  String buildReviewMd(TypedAnswers a, List<StrokeGroup> g, SpecRef src);
}

class ChangelogWriter {
  String append(String existing, ChangelogEntry e);
}

class CommitPlanner {
  List<FileWrite> planReview({
    required JobRef job,
    required String reviewMd,
    required String annotationsSvg,
    required Uint8List annotationsPng,
    required String changelogEntry,
  });

  List<FileWrite> planApprove({
    required JobRef job,
    required String changelogEntry,
  });
}
```

**Functional requirements** (PRD §5.5, §5.6, §8.5).

1. Typed answers auto-save every 3 s (FR-1.24) to a local draft file (not committed until Submit Review).
2. Submit Review produces a single commit with:
   - `03-review.md`
   - `03-annotations.svg` (markdown) or per-page `03-annotations-p{n}.svg` (PDF)
   - `03-annotations.png` (markdown) or per-page `03-annotations-p{n}.png` (PDF)
   - Changelog append (in the spec file, or `CHANGELOG.md` for PDFs)
   - Commit message: `review: <job-id>`.
3. Approve produces a single commit:
   - Empty `05-approved` file
   - Changelog append (`Approved — ready for implementation.`)
   - Commit message: `approve: <job-id>`.
4. Tablet is the **only** entity allowed to create `05-approved`. This is enforced by not exposing a desktop-visible API for it; desktop code only *deletes* it via folder deletion.

**Acceptance criteria.**

```gherkin
Scenario: Submit Review is a single commit
  Given a markdown spec with 3 typed answers and 5 annotation strokes
  When ReviewController.submit runs
  Then exactly 1 commit is created on claude-jobs
    And commit contains: 03-review.md, 03-annotations.svg, 03-annotations.png
    And changelog line is appended to 02-spec.md
    And commit message is "review: <job-id>"

Scenario: Approve writes 05-approved
  Given a reviewed job
  When user taps Approve
  Then 05-approved (empty) is committed
    And changelog appended
    And commit message is "approve: <job-id>"

Scenario: Typed answers auto-save
  Given user has typed into review panel
  When 3 seconds pass
  Then draft is written to <appdocs>/drafts/<job-id>/03-review.md.draft
    And app can crash and recover the draft on next launch
```

---

### 4.8 `theme` module (Milestone 1a)

**Responsibility.** Own design tokens, resolve light/dark, adapt ink colors at render time.

**Public API.**
```dart
class ThemeSpec {
  factory ThemeSpec.light();
  factory ThemeSpec.dark();
  Color color(TokenRef ref);
}

class InkColorAdapter {
  Color adapt(String canonicalHex, Brightness mode);
}
```

**Design tokens** (PRD §5.11.1).

| Token               | Light                          | Dark                              |
|---------------------|--------------------------------|-----------------------------------|
| `surface/background`| `#FAFAF9`                      | `#0A0A0B`                         |
| `surface/elevated`  | `#FFFFFF`                      | `#18181B`                         |
| `surface/sunken`    | `#F3F4F6`                      | `#0F0F10`                         |
| `border/subtle`     | `#E5E7EB`                      | `#27272A`                         |
| `text/primary`      | `#111827`                      | `#F3F4F6`                         |
| `text/muted`        | `#6B7280`                      | `#A1A1AA`                         |
| `accent/primary`    | `#4F46E5`                      | `#6366F1`                         |
| `accent/soft-bg`    | `#EEF2FF`                      | `rgba(99,102,241,0.15)`           |
| `status/success`    | `#059669`                      | `#6EE7B7`                         |
| `status/warning`    | `#B45309`                      | `#FCD34D`                         |
| `status/danger`     | `#DC2626`                      | `#F87171`                         |
| `ink/red`           | `#DC2626`                      | `#F87171` *(render-time adapt)*   |
| `ink/blue`          | `#2563EB`                      | `#60A5FA`                         |
| `ink/green`         | `#059669`                      | `#34D399`                         |
| `ink/yellow-hilite` | `#FEF9C3`                      | `rgba(250,204,21,0.25)`           |

**Ink-color discipline.** SVG always stores the canonical light-mode hex. `InkColorAdapter.adapt` brightens for dark mode at render time only. Round-trip to git is stable across theme changes.

**Acceptance criteria.**

```gherkin
Scenario: SVG stores canonical hex in dark mode
  Given user is in dark mode
  When user draws with ink/red
  Then SVG contains stroke="#DC2626"
    And on-screen render uses #F87171

Scenario: Theme persists across launches
  Given user toggles dark mode
  When app is killed and relaunched
  Then dark mode persists
```

---

## 5. Directory Layout and Build

### 5.1 Project tree

```
gitmdscribe/
├── pubspec.yaml
├── analysis_options.yaml          # strict lints + import-boundary rules
├── android/
├── lib/
│   ├── main.dart                  # composition root: Riverpod overrides bind ports → adapters
│   ├── bootstrap.dart             # flavor-aware startup (dev/prod)
│   ├── app/                       # Riverpod notifiers + router + theme controller
│   │   ├── feature_flags.dart     # --dart-define-backed, compile-time visible
│   │   └── (notifiers, router, controllers)
│   ├── domain/
│   │   ├── entities/              # pure Dart data classes
│   │   ├── ports/                 # abstract interfaces (git, auth, fs, …)
│   │   └── services/              # pure domain logic (PhaseResolver, ChangelogWriter, …)
│   ├── infra/
│   │   ├── git/git_adapter.dart
│   │   ├── git/git_isolate.dart
│   │   ├── auth/oauth_device_flow.dart
│   │   ├── auth/pat_adapter.dart
│   │   ├── storage/keystore_adapter.dart
│   │   ├── fs/fs_adapter.dart
│   │   ├── pdf/pdfx_adapter.dart
│   │   ├── markdown/markdown_adapter.dart
│   │   ├── logging/file_logger.dart       # LoggerPort adapter; rolling file + stderr
│   │   └── clock/system_clock.dart
│   └── ui/
│       ├── screens/               # sign_in/, repo_picker/, job_list/, spec_reader/, …
│       ├── widgets/               # ink_overlay.dart, sync_status_bar.dart, …
│       └── theme/                 # tokens.dart, ink_color_adapter.dart
├── test/
│   ├── domain/                    # mirrors lib/domain; no Flutter binding
│   ├── app/                       # ProviderContainer tests with fake ports
│   ├── infra/                     # adapter tests (may use tmp dirs / test http)
│   └── golden/                    # SVG and review.md golden files
└── integration_test/
    ├── sync_happy_path_test.dart
    ├── sync_conflict_test.dart
    ├── annotation_latency_test.dart
    └── oauth_device_flow_test.dart
```

### 5.2 Build & tooling

- **Flavors:** `dev` (verbose logging, dev OAuth `client_id`, PAT allowed) and `prod`. Chosen via `flutter build apk --flavor <name>`.
- **Feature flags:** `--dart-define` at build time. Compile-time-visible, tree-shakeable.
- **CI pipelines:**
  - `test/` runs on Linux with no emulator (domain + app + goldens). Required per PR.
  - `integration_test/` runs on a cached Android emulator image (SDK 34). Optional per PR, required on release tag.
  - libgit2 builds from source in CI with a caching step.
- **Lockfiles:** commit `pubspec.lock`.
- **Signing & distribution:** unspecified in PRD. Judgment call: use Android upload-key signing + Play Internal Testing track for dev, with a sideload-APK exit in the Settings screen. Revisit once distribution policy is set.

### 5.3 Testing strategy (TDD — the iron law)

Derived from the `test-driven-development` skill. This project is strictly TDD.

> **NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

If you catch yourself writing code without a test, delete the code and start over. "Keep it as reference" is rationalization; delete means delete.

**Red-Green-Refactor, every feature, every fix.**

1. **RED.** Write one minimal failing test expressing the behavior. Name the test for the behavior, not the method. One assertion-family per test.
2. **Verify RED.** Run the test. It must fail, and the failure must be the expected one (feature missing, not a typo). If it errors, fix the error until it *fails correctly*. If it passes, you're testing existing behavior — rewrite the test.
3. **GREEN.** Write the smallest code that makes the test pass. No options parameters "for later", no extra branches.
4. **Verify GREEN.** Test passes, all other tests still pass, output pristine (no warnings).
5. **REFACTOR.** Only after green. Remove duplication, improve names, extract helpers. Do not add behavior. Tests stay green.

**Fakes, not mocks.** Every port has an in-memory fake in `test/fakes/` (e.g., `FakeGitPort`, `FakeAuthPort`, `FakeFileSystemPort`, `FakeClockPort`). Tests override the Riverpod provider with the fake. Mocking libraries are a last resort — if a test needs `mock.verify(...)` to express what's being tested, the design is too coupled; refactor the port surface first.

**Test tiers.**

1. **Domain tests** (`test/domain/**`). Pure Dart, no Flutter binding. Fast, deterministic. Every domain service and port contract lives here. Target: >90% line coverage.
2. **App tests** (`test/app/**`). Riverpod `ProviderContainer` with fake ports. Exercises controllers' state transitions and error mapping.
3. **Integration tests** (`integration_test/**`). Real Android emulator. Exercises OAuth flow (test-mode GitHub OAuth App), full sync against a local bare-repo fixture, and pen-latency measurement against NFR-1.

**Every Gherkin scenario in §4 maps to at least one test file.** Scenarios are the acceptance criteria; the test file proves them. If a scenario has no corresponding test, the module is incomplete regardless of what the code looks like.

**Verification checklist — before marking any task complete.**

- [ ] Every new function has a test written first.
- [ ] Watched each test fail (saw the red output) before writing code.
- [ ] Each test failed for the expected reason.
- [ ] Minimal code written to pass each test.
- [ ] All tests pass; other suites still green.
- [ ] Output pristine (no warnings, no `print`).
- [ ] Tests use real code or in-memory fakes; mocks only if unavoidable.
- [ ] Edge cases and error paths covered.

If any box is unchecked, TDD was skipped. Start over.

**Bug-fix rule.** No bug gets fixed without a failing test that reproduces it first. The test proves the fix and prevents regression.

---

## 6. Milestone Plan

### 6.0 Execution model — subagent-driven development

Derived from the `sadd:subagent-driven-development` skill. Each milestone's task list below is executed with this ceremony:

**Per task:**

1. Dispatch a **fresh general-purpose subagent** with the specific task from the list below. Brief it with: the task, pointer to this doc + PRD, directory to work in, explicit instruction to follow TDD (§5.3), and the expected report-back.
2. The subagent does RED → verify fail → GREEN → verify pass → REFACTOR (§5.3), commits its work, and reports files-changed + test results.
3. Dispatch a **code-reviewer subagent** with: what was implemented, the task text as requirements, base and head git SHAs. Reviewer returns Strengths / Critical / Important / Minor.
4. Fix Critical issues immediately (dispatch a fix subagent, don't fix manually — preserves context isolation). Fix Important before moving on. Note Minor.
5. Mark the task complete. Move to the next.

**Sequential within a milestone.** Milestone task lists below are ordered because tasks share state (domain ports defined in task 1 are consumed in task 5, etc.). Do **not** dispatch implementation subagents in parallel within a milestone — they'll conflict on the same files.

**Parallel across independent failures.** Allowed *only* for the parallel-investigation pattern: if multiple failing tests live in disjoint subsystems and fixing one provably cannot affect the others, one subagent per file is fine. Default is still sequential.

**Per milestone close-out.**

1. After the last task, dispatch a **final code-reviewer subagent** to review the whole milestone against its exit criteria.
2. Deploy the build to the tablet.
3. Dispatch a **QA subagent** (fresh context, general-purpose) that uses ADB to screenshot every affected screen, walks through interactions, and reports findings ranked **Critical / High / Medium / Low**.
4. Dispatch a **triage subagent** (separate fresh context) that reads the QA report and produces a fix plan for **Critical + High** only. Medium and Low are deferred.
5. If any Critical or High findings exist, dispatch fix subagents, redeploy, and return to step 3 (round 2, 3, …) until a clean Critical/High pass.
6. Append all remaining Medium + Low findings to `docs/Issues.md` (create if missing).
7. Announce: *"I'm using the finishing-a-development-branch skill to complete this work."* and follow that skill (verify tests, present options, execute).
8. Only then is the milestone done.

**Never:**

- Skip code review between tasks.
- Proceed with unfixed Critical issues.
- Run multiple implementation subagents in parallel on the same milestone.
- Let a subagent implement without reading this doc + the task text.
- Fix a failing subagent's output by hand — dispatch a fix subagent.

**Stop-and-ask triggers:** blocker mid-task, unclear instruction, repeated verification failure, plan gap. Do not guess.

### 6.1 Milestone 1a — OAuth + repo picker + bootstrap (Week 2–3)

**Goal:** sign in with GitHub, pick a repo, bootstrap `claude-jobs`, Sync Down, render one markdown spec read-only, offline cache.

**TDD-first task order:**

1. `theme` tokens + light/dark tests.
2. `auth` domain port + fakes + `signInWithPat` test scenarios.
3. `auth` infra adapter: OAuth Device Flow + Chrome Tab integration.
4. `SecureStoragePort` + Keystore adapter.
5. `git` domain port + scripted `FakeGitPort` + conflict truth tables.
6. `git` infra adapter: libgit2dart isolate + first integration test against a local bare repo.
7. `FileSystemPort` + `PhaseResolver` + domain tests (phase truth table).
8. `SpecRepository` listing jobs from a fixture filesystem.
9. `MarkdownRenderer` + anchor math unit tests.
10. `RepoController`, `JobListController`, `SpecController` — wire the above.
11. UI screens: SignIn, RepoPicker, JobList, SpecReader (read-only).
12. Sync Down — `SyncService.syncDown`: fetch → fast-forward local `main` → merge `main` into `claude-jobs` (happy path + no-op path).
13. Integration test: OAuth Device Flow end-to-end on the emulator using a test OAuth app.

**Exit criteria:** the Gherkin scenarios in §4.1, §4.2, §4.3, §4.4 (markdown only), §4.6 (Sync Down happy path + dirty-tree), §4.8 all pass.

### 6.2 Milestone 1b — Annotation + PDF (Week 4–5)

**Goal:** pen annotation on markdown and PDF, SVG + PNG serialization, anchor stability.

**TDD-first task order:**

1. `annotation` domain entities (`Stroke`, `StrokeGroup`, `InkTool`) + tests.
2. `SvgSerializer` golden tests (scripted stroke sequences → SVG).
3. `AnnotationSession` state machine tests (undo/redo, palm rejection).
4. `PngFlattener` behind an interface; fake used by domain tests; real one exercised by widget tests.
5. `PdfRasterPort` + `pdfx` adapter (renderer fixed per D-12).
6. `InkOverlay` widget (Listener + CustomPainter). Widget tests for event plumbing.
7. Pen-latency integration test on emulator (proxy for Pad Go 2 — measure delta against NFR-1).

**Exit criteria:** scenarios in §4.4 (PDF) and §4.5 pass.

### 6.3 Milestone 1c — Review submission, Sync Up, conflicts (Week 6–7)

**Goal:** Submit Review and Approve write to git; Sync Up pushes; remote-wins conflict flow works.

**TDD-first task order:**

1. `ReviewSerializer` golden tests (`03-review.md` structure).
2. `ChangelogWriter` tests (append idempotency, format compliance).
3. `CommitPlanner.planReview` + `.planApprove` unit tests.
4. `ConflictResolver` tests with `FakeGitPort` returning `PushRejectedNonFastForward`.
5. `SyncService.syncUp` wiring + backup path resolution tests.
6. Integration test: diverged-branch conflict end-to-end with a bare repo fixture.
7. UI: Review panel, auto-save timer, Submit + Approve buttons, conflict-archived banner.

**Exit criteria:** scenarios in §4.6 (Sync Up + conflict) and §4.7 pass.

### 6.4 Milestone 1d — Polish (Week 8)

**Goal:** history timeline, changelog viewer, backup-folder UI, edge-case recovery.

**Tasks:**

1. `ChangelogViewer` — parse `## Changelog` across all jobs, render a timeline.
2. Settings: "Export backups" action using Storage Access Framework.
3. Recovery flows: corrupted `.git` surfacing; token-expired re-auth loop polish.
4. Cold-start NFR-2 tuning (preload last-opened job metadata).
5. Battery profiling against NFR-8 (4+ hours active review).

**Exit criteria:** NFR-2, NFR-8, NFR-9, NFR-10 measured and within budget on Pad Go 2.

---

## 7. Consolidated Acceptance Criteria

All Gherkin scenarios from §4 apply. Additionally, the following NFR tests gate release:

```gherkin
Scenario: NFR-1 — pen latency under 25 ms
  Given stylus active on OnePlus Pad Go 2
  When a freehand stroke is drawn
  Then ink lag (PointerMove → frame) is < 25 ms p95

Scenario: NFR-2 — cold launch
  Given app not in memory, last-opened job cached
  When user taps icon (online)
  Then last-opened job is visible within 2 s
  When offline
  Then within 3 s

Scenario: NFR-8 — battery
  Given Pad Go 2 charged to 100%, display at 50% brightness
  When user performs continuous review (annotate + scroll + type) for 4 hours
  Then battery remains > 20%

Scenario: NFR-9 — storage LRU
  Given > 1 GB of cached jobs locally
  When a new Sync Down brings in another job
  Then least-recently-used non-active jobs are evicted
    And active job is never evicted

Scenario: NFR-10 — sync duration
  Given a typical job folder (~5 MB) on LTE
  When Sync Down or Sync Up runs
  Then operation completes within 10 s p90
```

Accessibility gate (NFR-7):

```gherkin
Scenario: TalkBack reads the spec
  Given TalkBack is enabled
  When user focuses the SpecReader
  Then markdown content is read correctly in order
    And no element requires stylus input to operate
```

---

## 8. Open Questions, Risks, Judgment Calls

### 8.1 Open questions — resolved

All three PRD §14 "still open" items resolved on 2026-04-20:

- **D-12 (was O-1). PDF renderer = `pdfx`.** MIT-licensed, open source; no runtime swap. `syncfusion_flutter_pdfviewer` dropped from consideration. Rationale: license simplicity and "any will do" — performance re-evaluated only if the 1b integration test violates NFR-1/NFR-2.
- **D-13 (was O-2). Sync Down rebases local `main` first, then merges `main` into `claude-jobs`.** Required so newly pushed source items actually propagate into the sidecar — without the `main` update, new files would not appear in the merge. See §4.6 and the two Gherkin scenarios added there.
- **D-14 (was O-3). Changelog timestamps are local time only.** Format remains `YYYY-MM-DD HH:mm`. No timezone suffix, no UTC. Cross-timezone use is explicitly out of scope; each device uses its own clock.

### 8.2 Judgment calls made in this doc (not in PRD)

1. **State management = Riverpod 2.** Justified in §2.2. If the project ever onboards a second engineer with strong Bloc preference, the port/adapter boundaries are stable regardless — state management is local to `lib/app/`.
2. **Anchor stability.** SVG stores `(sourceSha, lineNumber)`. Desktop re-anchors after spec revisions against the `sourceSha` snapshot rather than walking forward-diffs. This matches the PRD's phrasing in §8.4 but makes the algorithm explicit.
3. **Backup path on Android scoped storage.** PRD writes `~/GitMdScribe/backups/…` which is inaccessible post-API-29. Use `getApplicationDocumentsDirectory() + "/backups/…"` and expose via Storage Access Framework in Settings.
4. **Atomic review commit.** `CommitPlanner` assembles the full `FileWrite` list before calling `GitPort.commit`, ensuring one commit per Submit Review / Approve. Avoids a two-commit "review, then changelog" drift.
5. **libgit2 isolate IPC cost.** File writes crossing the isolate boundary serialize their bytes. Fine for MB-scale review payloads; re-measure in 1a if sync latency slips.
6. **No schema version field (MVP).** Deferred. Graceful-degradation contract documented in §3.8.
7. **Phase 1 milestone count.** PRD §13 lists 1a–1d (not 1a–1f). This doc tracks the PRD. 1e/1f are reserved for late additions (crash reporting adapter, metrics screen) without refactoring module boundaries.
8. **Signing & distribution.** Not specified in PRD. Defaulting to Play Internal Testing for dev + sideload-APK exit. Requires user decision before Milestone 1d ship.
9. **No `lib/util/` folder.** Per the `ddd:software-architecture` skill, `utils`/`helpers`/`common`/`shared` are banned names. `LoggerPort`'s file adapter lives in `lib/infra/logging/`; `FeatureFlags` in `lib/app/`. If a function has no domain home, that's a signal to create or expand a bounded context — not a signal to create a dumping ground.

### 8.3 Technical risks

- **libgit2dart build in CI.** Slow and platform-specific. Mitigate with a caching layer; fall back to a prebuilt libgit2 binary if caching is flaky.
- **Pen latency budget on Pad Go 2.** NFR-1 is aggressive for Flutter's rendering pipeline. If widget tests show >25 ms on the device, fallback plan is a native Android canvas view embedded via `AndroidView` — adds complexity but preserves the module boundary (only `InkOverlay` implementation changes).
- **`05-approved` tampering.** Desktop could, in principle, create `05-approved` directly on `claude-jobs`. The phase-gate is procedural, not cryptographic. Judgment: acceptable for a single-user workflow; revisit if multi-user.

---

## 9. Appendices

### 9.1 References

- [PRD](PRD/TabletApp-PRD.md) — source of truth for Phase 1 scope.
- [Interactive mockups](PRD/mockups.html) — 12-screen user journey walkthrough.
- [Problem statement](initial/ProblemStatement.txt) — motivation and vignette.

### 9.2 Glossary

| Term              | Meaning                                                                       |
|-------------------|-------------------------------------------------------------------------------|
| `claude-jobs`     | Sidecar git branch; tablet writes only here                                   |
| Phase gate        | Filesystem marker (`03-*`, `05-approved`) that transitions workflow state     |
| Sync Down         | `fetch origin` → fast-forward local `main` → merge `main` into local `claude-jobs` |
| Sync Up           | `push origin claude-jobs`; on reject → remote-wins conflict flow              |
| Anchor            | `(sourceSha, lineNumber)` or `(sourceSha, page, bbox)`; ties a stroke to content |
| Stroke group      | SVG `<g>` element holding one continuous pen interaction                      |
| Port              | Abstract interface in `lib/domain/ports/` — no Flutter imports                |
| Adapter           | Platform-bound implementation in `lib/infra/` behind a port                   |
