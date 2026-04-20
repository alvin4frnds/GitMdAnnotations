# GitMdAnnotations — Tablet App PRD

**Status:** Draft v2 (incorporates Praveen's clarifications 2026-04-20)
**Owner:** Praveen
**Source problem statement:** `docs/initial/ProblemStatement.txt`
**Scope:** Tablet review cockpit (Phase 1) + tablet spec authoring (Phase 2)
**Target platform:** Android only (OnePlus Pad Go 2), MVP.
**Out of scope:** Mobile requirements-capture app, desktop watcher, Claude Code CLI invocation

---

## 0. What changed since v1

- **Platform:** Android only. iPadOS deferred indefinitely (or until the dev buys an iPad).
- **Source file types:** `.md` **and** `.pdf` — PDFs are read-only originals annotated via an overlay layer.
- **Branch model:** Tablet writes **only** to a dedicated `claude-jobs` branch. `jobs/` directory never exists on `main`. Keeps the source branch clean.
- **Sync model:** **Explicit Sync Down / Sync Up buttons.** No auto-sync. No push notifications in Phase 1 (GitHub Actions may drive notifications in Phase 2).
- **Change tracking:** 1-line human-readable changelog entries at the bottom of each `.md` spec file, written by both tablet and desktop. For PDFs, a sidecar `CHANGELOG.md` in the spec folder.
- **Diff UI removed** — replaced with human-readable changelog.
- **Conflict policy:** Remote wins. Local uncommitted edits saved to a backup folder on the device.
- **Signed commits / FCM backend:** dropped for MVP.

---

## 1. Overview & Context

### 1.1 The underlying workflow

AI-assisted coding today collapses specification and implementation into a single step. Given a vague prompt, the AI silently makes dozens of assumptions, skips edge cases, and produces code whose misalignment only shows up in review — when rework is expensive. The same AI, asked instead to *write a spec*, naturally surfaces open questions, concerns, and edge cases. The bottleneck isn't capability; it's workflow.

The proposed system splits AI-assisted development into five hard-gated phases:

| # | Phase               | Device   | Artifact produced                                |
|---|---------------------|----------|--------------------------------------------------|
| 1 | Requirements        | Mobile   | `01-requirements.md`                             |
| 2 | Spec Generation     | Desktop  | `02-spec.md`                                     |
| 3 | **Spec Review**     | **Tablet** | `03-review.md` + `03-annotations.svg/.png`    |
| 4 | Spec Revision       | Desktop  | `04-spec-v2.md`, `04-spec-v3.md`, …              |
| 5 | Implementation      | Desktop  | PR into `main`; `claude-jobs/jobs/pending/spec-{id}/` deleted |

Claude refuses to cross phase boundaries without explicit approval markers. Artifacts live on a **sidecar branch** (`claude-jobs`) so `main` stays clean. The desktop watcher is the only automation; git is the bus; no Anthropic API key, no proxy, no ToS gray zones.

### 1.2 Where the tablet fits

The tablet owns **Phase 3 (Spec Review)** in this PRD's Phase 1, and expands to also own **Phase 2 (Spec Generation)** of the workflow in this PRD's Phase 2 (the user's ask: "it can create new specs also in phase 2").

Source artifacts the tablet can review are **Markdown (`.md`) and PDF (`.pdf`)**. PDFs are treated as immutable originals with an overlay annotation layer; Markdown is rendered natively with typed-text quotability plus the same overlay.

The core wedge is *asynchronous, pen-first review*: the highest-leverage moment in AI-assisted coding is reviewing assumptions before code is written, and the best thinking time for that is away from the desk. This app frees it — including while offline on a commute, because sync is explicit and intentional.

### 1.3 User journey (tablet-only, adapted from problem statement)

> *Monday evening.* Before leaving home tomorrow, Praveen taps **Sync Down**. The app fetches `claude-jobs` from remote, merges `main` into it so the branch carries the latest source-file context, and caches everything locally.
>
> *Tuesday morning commute, offline.* Praveen opens the tablet, sees `02-spec.md` rendered cleanly. He strikes through an assumption that's wrong. Circles an open question and writes his answer in the margin. Taps **Submit Review**. The app writes `03-review.md`, `03-annotations.svg`, `03-annotations.png`, and appends a 1-line changelog entry — all locally, on the `claude-jobs` branch. No network needed.
>
> *Tuesday, arriving at the office.* Tap **Sync Up**. The local commits push to remote `claude-jobs`. Desktop watcher sees the push and starts its revision pass.
>
> *Tuesday lunch.* Praveen taps **Sync Down** again. `04-spec-v2.md` arrives. He reads it, finds it clean, taps **Approve**. The app creates `05-approved`, appends a changelog entry, and queues the commit. A second **Sync Up** pushes. Desktop takes over — implements the change, opens a PR into `main`, and **deletes** `jobs/pending/spec-{id}/` from `claude-jobs` once done.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- **G1.** Let a solo developer review an AI-generated spec with a stylus as fast and naturally as they'd review a paper printout.
- **G2.** Capture typed corrections and pen annotations as git-committable artifacts that a desktop Claude Code agent can parse without human translation.
- **G3.** Enforce phase gates on the tablet side — **Submit Review** and **Approve** are the only cross-phase affordances; Claude can't "helpfully skip ahead."
- **G4.** Work fully offline for reading, annotating, and committing locally. Network is only needed for the two explicit sync buttons.
- **G5.** Keep the user's source branch (`main`) clean — all tablet artifacts live on a dedicated `claude-jobs` sidecar branch.
- **G6.** (Phase 2) Let the user author a `02-spec.md` directly on the tablet, bypassing the desktop spec-generation round-trip.

### 2.2 Non-goals (explicit)

- **NG1.** iOS / iPadOS support in MVP.
- **NG2.** Mobile (phone) requirements capture — a separate app owns Phase 1 of the workflow.
- **NG3.** Desktop watcher, Claude Code CLI invocation, headless-mode orchestration.
- **NG4.** On-device LLM inference of any kind. The tablet is a thin client.
- **NG5.** Team / multiplayer features (multiple reviewers on one spec, shared comments).
- **NG6.** Self-hosted / on-prem variants. **GitHub.com only** in MVP.
- **NG7.** Code viewing / editing beyond Markdown and PDF. The tablet shows specs, not source.
- **NG8.** **Signed commits (GPG / SSH) in MVP.** OAuth token authorization only.
- **NG9.** **Push notifications in Phase 1.** Phase 2 may use GitHub Actions (no app backend) to trigger them.
- **NG10.** Auto-sync. Sync is always user-initiated.

---

## 3. Target User & Device

### 3.1 User

Solo developer with a Claude Max subscription and a personal or small-team GitHub workflow. Reviews specs during commutes, couch time, bed time — the 45–90 minutes a day that currently go to passive scrolling because typing on a phone is painful.

### 3.2 Primary device

**OnePlus Pad Go 2**, Android, with an active stylus. Design targets assume an Android tablet with a pressure-sensitive pen and ~90 Hz+ refresh rate.

### 3.3 Jobs-to-be-done

- **J1.** "When a spec is waiting, I want to review it away from my desk so I don't waste my best thinking time."
- **J2.** "When I spot a wrong assumption, I want to strike through it with a pen and write the correction — the way I'd review a paper doc — without mode-switching to a keyboard."
- **J3.** "When I'm commuting offline, I still want to submit my review locally so nothing is blocked on network."
- **J4.** "When I've approved a spec, I want the desktop to start implementing immediately once I reconnect, without any coordination step."
- **J5.** (Phase 2) "When I already know the spec, I want to draft it directly and skip the desktop spec-generation round-trip."

---

## 4. Key User Stories

### Phase 1 (MVP — Review)

- **US-1.1** As a solo dev, I sign in once with GitHub OAuth and see my repos.
- **US-1.2** I tap **Sync Down** before leaving the house. The app fetches `claude-jobs` from remote (creating it from `main` if it doesn't exist yet), merges `main` into it, and caches everything locally.
- **US-1.3** I see a list of open jobs in `jobs/pending/` — each is a `spec-{id}/` folder; I tap one to open it.
- **US-1.4** I see `02-spec.md` rendered as clean markdown, or a `.pdf` rendered page-by-page with a nav rail.
- **US-1.5** I annotate directly on the rendered document — freehand ink, strikethrough, circles, arrows, margin notes — with pressure sensitivity and palm rejection.
- **US-1.6** I type answers to the spec's "Open Questions" section in a side panel.
- **US-1.7** I tap **Submit Review**; the app writes `03-review.md` + `03-annotations.svg` + `03-annotations.png` (and for a multi-page PDF, `03-annotations-p{n}.svg/.png` per page), appends a changelog entry, and **commits locally** to `claude-jobs`. No push yet.
- **US-1.8** I tap **Sync Up** when I reach the office. All queued commits push to remote `claude-jobs`.
- **US-1.9** Later, I tap **Sync Down** again. If the desktop has produced `04-spec-v2.md`, I see it alongside the updated changelog.
- **US-1.10** When satisfied, I tap **Approve**; the app creates `05-approved`, appends a changelog entry, commits locally. I Sync Up to signal the desktop.
- **US-1.11** Everything between Sync Down and Sync Up works without network — reading, annotating, reviewing, approving, committing locally.
- **US-1.12** I can see the full changelog for any job (who changed what, when) as a human-readable scroll at the bottom of the spec file (or sidecar `CHANGELOG.md` for PDFs).

### Phase 2 (Authoring)

- **US-2.1** I tap **New Spec**, pick a repo + target area, and draft `02-spec.md` directly — typed or dictated — bypassing the desktop spec-generation round-trip.
- **US-2.2** I pick a template (API change / new feature / refactor / bug fix) that pre-fills the standard spec sections.
- **US-2.3** The app lints for required sections before I can commit.
- **US-2.4** Committing a hand-authored spec drops a marker (`02-author-tablet`) so the desktop watcher knows this spec skipped the Claude spec-generation pass.

---

## 5. Functional Requirements — Phase 1 (Review)

### 5.1 Authentication & repo access

- **FR-1.1** GitHub authentication via **OAuth Device Flow** (no backend / no client secret required). Access token stored in Android Keystore via `flutter_secure_storage`. Fine-grained Personal Access Token paste-in as fallback. Full flow detailed in §5.10.
- **FR-1.2** Paginated repo picker; remember the last N repos the user opened.
- **FR-1.3** `main` assumed as default source branch; support repos whose default is something else (detected via GitHub API on first connect).

### 5.2 Branch & folder strategy

- **FR-1.4** All tablet writes go to the `claude-jobs` branch — **never** to the default branch.
- **FR-1.5** On first Sync Down for a repo: if `origin/claude-jobs` exists, fetch it; if not, create it locally from `origin/main` and push.
- **FR-1.6** On every Sync Down thereafter: fetch `origin/claude-jobs` **and** merge `origin/main` into local `claude-jobs` so the branch always carries latest source-file context for the desktop Claude Code agent.
- **FR-1.7** Job folder convention: `jobs/pending/spec-{id}/` on `claude-jobs`. `id` is a short slug (e.g., `auth-flow-totp-2026-04-20`).
- **FR-1.8** The `jobs/` directory must not appear on `main` in any state (enforced by convention; the tablet never commits it to `main`).

### 5.3 Spec loading & rendering

- **FR-1.9** Open-jobs list = folders under `jobs/pending/` that don't contain `05-approved`.
- **FR-1.10** For each open job, show: current phase (derived from which numbered files exist), last-modified time, a 2-line preview.
- **FR-1.11** Markdown rendering: full CommonMark + GFM (tables, strikethrough, task lists, fenced code). Syntax-highlighted code blocks (not editable). Heading nav rail. Sticky section header on scroll. Theme adherence per §5.11. Typography tuned for ~40 chars per line.
- **FR-1.12** PDF rendering: page-by-page, fit-to-width by default, pinch-zoom supported. Lazy-load pages; target 60 FPS scroll on the Pad Go 2. No native text selection in MVP (treat pages as images for annotation purposes).

### 5.4 Pen annotation layer

- **FR-1.13** Annotations overlay the rendered document in a transparent canvas; the document below stays interactive (tap-to-quote on markdown; tap-to-zoom on PDF pages).
- **FR-1.14** Stroke primitives: freehand ink, straight line, arrow, rectangle, circle, highlighter, eraser.
- **FR-1.15** **Pressure sensitivity** required on the target stylus; graceful degradation on capacitive styli.
- **FR-1.16** **Palm rejection**: only stylus events leave ink; finger events scroll / pan / zoom.
- **FR-1.17** Latency target: **<25 ms on the OnePlus Pad Go 2** (Android baseline; tighter if the device supports it).
- **FR-1.18** Color palette: 6 preset colors (black, red, blue, green, yellow, orange) plus eraser. No custom colors in MVP.
- **FR-1.19** Each stroke-group captures: start-anchor (nearest markdown line number **or** PDF page number + bounding box), timestamp. Lets the desktop Claude say "the user circled the assumption on page 3 near the top-left."
- **FR-1.20** Undo / redo (≥ 50 steps).
- **FR-1.21** Annotations are persisted as **SVG (git-diffable) + flattened PNG (fidelity)**. PDFs get per-page files: `03-annotations-p{n}.svg` and `03-annotations-p{n}.png`.

### 5.5 Typed review panel

- **FR-1.22** Collapsible right-side panel shows the spec's "Open Questions" section (auto-extracted from markdown) as individual text inputs; user types answers under each question.
- **FR-1.23** Free-form notes field for anything not tied to a specific question.
- **FR-1.24** Auto-save locally every 3 seconds; no data loss on app backgrounding or battery death.

### 5.6 Submit & Approve (local commits)

- **FR-1.25** **Submit Review** action:
  1. Serialize annotations to SVG + flatten to PNG (per-page for PDFs).
  2. Write `03-review.md` = structured markdown with typed answers under each question + free-form notes + spatial-reference list (e.g., "see stroke group A anchored at line 47 / page 2").
  3. **Append a 1-line changelog entry** at the bottom of the reviewed file (for markdown specs) or to `CHANGELOG.md` in the folder (for PDFs). Format: `- YYYY-MM-DD HH:mm tablet: <human description>`.
  4. Commit locally to `claude-jobs` with message `review: <job-id>`.
- **FR-1.26** **Approve** action (enabled only when the latest spec version has no unreviewed changes):
  1. Create empty `05-approved` file.
  2. Append changelog: `- YYYY-MM-DD HH:mm tablet: Approved — ready for implementation.`
  3. Commit locally to `claude-jobs` with message `approve: <job-id>`.
- **FR-1.27** Neither action pushes automatically. Commits sit in the local `claude-jobs` until **Sync Up**.
- **FR-1.28** Both actions are irreversible in-app (external `git revert` still possible).

### 5.7 Sync (explicit, user-driven)

- **FR-1.29** **Sync Down** button: `git fetch origin`; if local `claude-jobs` doesn't exist, create from `origin/main`; otherwise fast-forward to `origin/claude-jobs` and merge `origin/main` into it. On conflict, see FR-1.32.
- **FR-1.30** **Sync Up** button: `git push origin claude-jobs`. On push rejection (remote has newer commits), trigger the same conflict flow.
- **FR-1.31** Both buttons show progress and result toast; the app badge shows unpushed-commit count.
- **FR-1.32** **Conflict policy = remote wins.** On conflict during Sync Down or Sync Up:
  1. Save the local `claude-jobs` HEAD to an on-device backup folder (`~/GitMdAnnotations/backups/<repo>/<branch>-<timestamp>/`) as a full copy of the job folders.
  2. Reset local `claude-jobs` to `origin/claude-jobs`.
  3. Merge `origin/main` on top (as normal Sync Down).
  4. Notify user: "Local changes archived — remote took precedence. Backup at …"
- **FR-1.33** No auto-sync. No background sync. Ever.

### 5.8 Offline behavior

- **FR-1.34** Every functional requirement above except FR-1.29 / FR-1.30 must work fully offline.
- **FR-1.35** Local commits queue on `claude-jobs`; badge shows count.
- **FR-1.36** Cached source files (the merged-in `main` content) are available offline read-only for the desktop Claude's context — the tablet doesn't need them for rendering, but they're present for debugging.

### 5.9 History & audit

- **FR-1.37** Changelog viewer: reads the bottom of `.md` files and the sidecar `CHANGELOG.md` for PDFs; shows a chronological, human-readable log per job.
- **FR-1.38** Full job-folder timeline available through the app: every numbered file + every commit, in order.

### 5.10 Authentication flow (detail)

GitHub auth uses the **OAuth Device Flow** because the PRD forbids an app backend (NG-x) and an Android app binary cannot safely hold a client secret. Device Flow is designed for exactly this constraint: it exchanges a device code + client ID (public) for an access token, never requiring a client secret from the device side. GitHub OAuth Apps do **not** support PKCE, so PKCE is not an option here; Device Flow is the only no-backend path.

#### 5.10.1 Flow steps

```
 1. User taps "Sign in with GitHub"
 2. App → POST https://github.com/login/device/code
          body: { client_id: <public, baked into app binary>,
                  scope: "repo" }
 3. GitHub → { user_code: "WDJB-MJHT",
               device_code: "<opaque>",
               verification_uri: "https://github.com/login/device",
               interval: 5,
               expires_in: 900 }
 4. App displays user_code on-screen and launches a Chrome Custom Tab
    to verification_uri (code prefilled via ?user_code=… when supported).
 5. User approves requested scopes in the browser.
 6. App polls every `interval` seconds:
      POST https://github.com/login/oauth/access_token
      body: { client_id,
              device_code,
              grant_type: "urn:ietf:params:oauth:grant-type:device_code" }
    Response is one of:
      - { error: "authorization_pending" }  → keep polling
      - { error: "slow_down" }              → increase interval by 5s
      - { error: "expired_token" }          → restart from step 2
      - { access_token, token_type, scope } → success
 7. App writes access_token → Android Keystore (flutter_secure_storage).
 8. App fetches GET /user to populate git commit identity
    (name, email) and caches it in secure storage alongside the token.
 9. All subsequent GitHub API + libgit2 push/fetch operations use
    `Authorization: Bearer <access_token>` (or HTTPS basic-auth with
    the token as password for git operations, per GitHub's v3 guidance).
```

#### 5.10.2 Required scopes

- **Classic OAuth App:** `repo` (read/write access to public + private repos; minimum needed to push to `claude-jobs`).
- **Fallback (fine-grained PAT, Phase 1 only):** `contents: write` and `metadata: read` on the repos the user explicitly selects.

#### 5.10.3 Storage

| Item             | Where                                   | Lifetime                                     |
|------------------|-----------------------------------------|----------------------------------------------|
| `client_id`      | App binary                              | Permanent (public value, safe to bake in).   |
| `client_secret`  | **Does not exist** for this app.        | N/A — Device Flow doesn't need one.          |
| `access_token`   | Android Keystore (hardware-backed)      | Until user signs out or revokes.             |
| Git identity     | Android Keystore alongside the token    | Same as token.                               |
| Refresh token    | Not used in MVP (see 5.10.5).           | —                                            |

#### 5.10.4 Re-auth & revocation

- On any `401` response from the GitHub API or git push, the app discards the stored token and routes the user back to step 1. No silent-refresh loop.
- Sign-out wipes the Keystore entry. Remote revocation lives at `github.com/settings/applications`; the app detects revocation on the next 401 and re-authenticates.

#### 5.10.5 Token expiration policy (MVP)

- Register the OAuth App with **"Expire user authorization tokens" turned OFF**. Access tokens then remain valid until the user revokes them — no refresh-token dance needed.
- If a future security policy forces expiring tokens, add refresh-token handling (Device Flow returns a refresh token when expiration is enabled). Defer to post-MVP.

#### 5.10.6 PAT fallback (escape hatch)

For users behind strict enterprise proxies or who prefer manual control:

- "Sign in with a token instead" link on the sign-in screen.
- User creates a fine-grained PAT on GitHub, pastes it, app validates with `GET /user`, stores in Keystore.
- Same downstream flow from that point. Worse UX; unblocks edge cases.

#### 5.10.7 Registering the OAuth App

Before first release:

1. Register a **GitHub OAuth App** (not a GitHub App — OAuth Apps support Device Flow; GitHub Apps have different auth semantics).
2. Set "Device Flow" checkbox to enabled.
3. Callback URL can be anything non-empty (not used by Device Flow).
4. Copy the **Client ID** into the app's build config.
5. **Do not generate a client secret.** If one is generated by default, never include it in the app.

#### 5.10.8 Test plan

- Fresh install → sign-in → verify token in Keystore; verify `/user` call succeeds.
- Kill app mid-poll → relaunch → polling resumes or restarts cleanly.
- Revoke token at github.com/settings/applications → next sync → 401 → app routes back to sign-in.
- PAT fallback path with a valid + invalid token.
- Device flow `slow_down` handling: simulate by polling too fast.

### 5.11 Theme & appearance

Dark mode is a first-class concern, not a polish item — much of the app's use is on couches, commutes, and in bed, where a bright white surface is fatiguing.

- **FR-1.39** **App-wide light / dark themes.** Covers every surface: status bar, app chrome, job list, rendered markdown / PDF pages, review panel, modals, changelog viewer, annotation overlay. No mixed-mode screens.
- **FR-1.40** **System-default by default.** On first launch the app honors the Android system `UI_MODE_NIGHT_*` / `prefers-color-scheme` signal. After the first manual override, user preference wins and is respected across launches.
- **FR-1.41** **Manual override persists** per device in local secure storage (same store as the OAuth token). Setting is available in-app settings and as a quick-toggle on the job list screen.
- **FR-1.42** **Pen ink colors adapt for contrast.** In dark mode the 6-color palette renders with brightened values (e.g., red `#DC2626` → `#F87171`, black → `#E5E7EB`) so strokes read against a dark background. The **stored SVG keeps the canonical light-mode hex** — the adaptation is a render-time concern only. This way a stroke drawn on a dark-mode tablet still renders correctly on a light-mode GitHub UI or a teammate's light theme.
- **FR-1.43** **Highlighter and strike-through** adapt the same way — saved SVG uses canonical colors; render-time darkens/brightens them per theme.
- **FR-1.44** **No sepia / high-contrast / custom themes** in MVP. Scope is light + dark only.
- **FR-1.45** **Rendered markdown follows the theme** — code blocks, tables, blockquotes all have tuned dark-mode colors; heading hierarchy stays readable.

#### 5.11.1 Design tokens (reference)

Implementation should lock these into a single theme object so every screen can consume them:

| Token                 | Light      | Dark       |
|-----------------------|------------|------------|
| `surface/background`  | `#FAFAF9`  | `#0A0A0B`  |
| `surface/elevated`    | `#FFFFFF`  | `#18181B`  |
| `surface/sunken`      | `#F3F4F6`  | `#0F0F10`  |
| `border/subtle`       | `#E5E7EB`  | `#27272A`  |
| `text/primary`        | `#111827`  | `#F3F4F6`  |
| `text/muted`          | `#6B7280`  | `#A1A1AA`  |
| `accent/primary`      | `#4F46E5`  | `#6366F1`  |
| `accent/soft-bg`      | `#EEF2FF`  | `rgba(99,102,241,0.15)` |
| `status/success`      | `#059669`  | `#6EE7B7`  |
| `status/warning`      | `#B45309`  | `#FCD34D`  |
| `status/danger`       | `#DC2626`  | `#F87171`  |
| `ink/red`             | `#DC2626`  | `#F87171`  |
| `ink/blue`            | `#2563EB`  | `#60A5FA`  |
| `ink/green`           | `#059669`  | `#34D399`  |
| `ink/yellow-highlight`| `#FEF9C3`  | `rgba(250,204,21,0.25)` |

*(See `docs/PRD/mockups.html` for a visual reference of both modes.)*

#### 5.11.2 Test plan

- Cold launch with system dark mode on → app renders dark.
- Toggle in-app → next cold launch respects the override, not the system.
- Draw a red stroke in dark mode, Sync Up, view on GitHub's light UI → stroke appears in the canonical light-mode red (SVG stores `#DC2626`, not `#F87171`).
- Review every screen in both modes: no unreadable text, no pure-white flashes, no invisible borders.

---

## 6. Functional Requirements — Phase 2 (Authoring)

- **FR-2.1** **New Spec** entry point: pick repo → pick target area (free text or tag from history) → choose template → open editor.
- **FR-2.2** Templates live in-repo at `.gitmdannotations/templates/*.md` if present (on `main`), otherwise fall back to bundled defaults (API change / new feature / refactor / bug fix).
- **FR-2.3** Editor: the same markdown view as review mode, but editable. Keyboard, dictation, or stylus handwriting-to-text (Android ink recognition).
- **FR-2.4** On-device linting: required sections present (`## Goals`, `## Non-Goals`, `## Open Questions`, `## File-Level Change Plan`). Linter blocks commit until satisfied.
- **FR-2.5** Commit flow: creates `jobs/pending/spec-{new-id}/02-spec.md` on `claude-jobs`, plus marker file `02-author-tablet` so the desktop watcher knows this spec didn't come from Claude's spec-generation phase.
- **FR-2.6** The user chooses at commit time: "Send to desktop for revision review" (Phase 4 of the workflow) or "Approve immediately and implement" (drops `05-approved` in the same commit).
- **FR-2.7** Drafts save locally; no partial specs reach the repo.
- **FR-2.8** (Optional, Phase 2b) Push notifications via GitHub Actions: user installs a workflow that POSTs to a notification service when specific file patterns appear on `claude-jobs`. No app backend involved.

---

## 7. Non-Functional Requirements

| ID    | Requirement                                                                                         |
|-------|-----------------------------------------------------------------------------------------------------|
| NFR-1 | Pen latency <25 ms on the OnePlus Pad Go 2 (Android baseline); tighter on higher-refresh devices.   |
| NFR-2 | Cold launch → last-opened job visible <2 s on Wi-Fi, <3 s offline.                                  |
| NFR-3 | Works fully offline for read, annotate, review-submit, approve, and local commit.                   |
| NFR-4 | All commits carry the user's configured git identity (name + email from GitHub profile). No signing in MVP. |
| NFR-5 | Annotation SVGs are git-diffable; the desktop Claude can parse stroke anchors by reading the SVG.   |
| NFR-6 | No telemetry beyond opt-in crash reports. No data leaves the device except to the user's own GitHub.|
| NFR-7 | Accessible: TalkBack support for reading specs; no pen-only affordances.                            |
| NFR-8 | Battery: 4+ hours of active review on a single charge on the Pad Go 2.                              |
| NFR-9 | Storage: local cache up to 1 GB; LRU eviction of non-active jobs.                                   |
| NFR-10| Sync Down / Up operations complete <10 s on LTE for a typical job folder (few MBs).                |

---

## 8. Data Model & File Contract

### 8.1 Branch layout

- **`main` (or repo default):** untouched by the tablet. User's normal working branch.
- **`claude-jobs`:** sidecar branch. Holds all tablet-authored artifacts. Contents:
  - The full tree of `main` at the time of the last merge (so desktop Claude has source context).
  - Plus `jobs/pending/spec-{id}/` directories.

### 8.2 Job folder layout (on `claude-jobs`)

```
jobs/pending/spec-<id>/
├── 01-requirements.md             # (Phase 1 of workflow — from mobile app in future)
├── 02-spec.md                     # Desktop Claude's spec OR tablet-authored spec (Phase 2)
├── 02-author-tablet               # Marker (Phase 2 only)
├── 03-review.md                   # Typed answers + spatial references
├── 03-annotations.svg             # (For markdown spec) strokes, text-serialized
├── 03-annotations.png             # (For markdown spec) rendered snapshot
├── 03-annotations-p{n}.svg        # (For PDF spec) per-page strokes
├── 03-annotations-p{n}.png        # (For PDF spec) per-page snapshots
├── 04-spec-v2.md                  # Desktop's revised spec
├── 04-spec-v3.md                  # …loops until approved
├── 05-approved                    # Empty marker; presence = phase-5 gate open
├── CHANGELOG.md                   # (PDF specs only) mirrors changelog-at-bottom pattern
└── meta.json                      # id, creation time, tags, target area, source file type
```

When the desktop executor finishes implementation, it **deletes** the entire `jobs/pending/spec-<id>/` directory from `claude-jobs` and commits to `main` with the actual code changes.

### 8.3 Changelog format (bottom of `.md` files)

```markdown
<!-- rest of the spec file above -->

## Changelog

- 2026-04-20 14:32 desktop: Initial spec generated from requirements.
- 2026-04-20 09:14 tablet: User clarified auth flow — TOTP required, magic link fallback.
- 2026-04-20 13:05 desktop: Revised spec. Folded in review comments; flagged 2 new open questions.
- 2026-04-20 14:20 tablet: Approved.
```

- One line per change. Timestamp in local time with timezone-neutral format.
- Author is `tablet`, `desktop`, or future agent name.
- Body is **human-readable** — no diffs, no machine output. The desktop Claude writes its entries in the same plain-English style when generating revisions.

### 8.4 Annotation SVG schema

```svg
<svg xmlns="http://www.w3.org/2000/svg"
     data-source-file="02-spec.md"
     data-source-sha="<sha of 02-spec.md at review time>">
  <g id="stroke-group-A"
     data-anchor-line="47"
     data-timestamp="2026-04-20T09:14:22Z">
    <path d="M120,340 Q…" stroke="#e24" stroke-width="2.1" opacity="0.9"/>
  </g>
</svg>
```

For PDFs, `data-anchor-line` is replaced with `data-anchor-page="3"` + `data-anchor-bbox="120,340,180,380"`.

### 8.5 `03-review.md` structure

```markdown
# Review — spec-<id>

**Source:** `02-spec.md` @ <sha>   (or `spec.pdf`)
**Reviewed at:** 2026-04-20 09:32 local time

## Answers to open questions

### Q1: Should auth flow support magic links?
> Yes, but only as fallback after TOTP. See stroke group A at line 47.

### Q2: …

## Free-form notes
- Session management section assumes Redis; we use Postgres — see stroke group B at line 102.

## Spatial references
- Stroke group A → line 47 (assumption about async auth)
- Stroke group B → line 102 (session store)
```

---

## 9. Integration Contract with Desktop Watcher

- **Bus:** git. The tablet commits to `claude-jobs`; the desktop polls (or listens via GitHub webhooks) for pushes to that branch.
- **No direct RPC.** The tablet never talks to the desktop.
- **Branch responsibility split:**
  - Tablet **only** writes to `claude-jobs`.
  - Desktop writes to `claude-jobs` (new `04-spec-v*.md`, changelog entries), **and** to `main` (when implementing).
  - Desktop is responsible for deleting `jobs/pending/spec-<id>/` from `claude-jobs` after it pushes code to `main`.
- **Commit-message prefixes the desktop greps for:**
  - `spec: <job-id>` — new spec committed (desktop or tablet)
  - `review: <job-id>` — review submitted (tablet)
  - `approve: <job-id>` — approval granted (tablet)
- **Phase advancement is data-driven:** presence of `03-*` files ⇒ phase 4 (desktop revises); presence of `05-approved` ⇒ phase 5 (desktop implements). The tablet is the only way `05-approved` gets created, which keeps the phase gate honest.
- **Conflict resolution:** the desktop is assumed online and authoritative; if two devices ever race on `claude-jobs`, the rule everywhere is **remote wins, local backs up** (FR-1.32). The desktop, being a long-running online process, effectively always has priority.
- **Files are append-only from the tablet's side.** The tablet never deletes files on `claude-jobs`. Only the desktop may delete `jobs/pending/spec-<id>/` folders (as cleanup after implementation).

---

## 10. Tech Stack Recommendation

### 10.1 Client framework: **Flutter**

- Single codebase. Keeps the door open to iPadOS later if the dev buys an iPad.
- Skia-based rendering (no JS bridge overhead).
- Native stylus events on Android via `Listener` widget with pressure in `PointerEvent`.
- Rich ecosystem for markdown rendering (`flutter_markdown`) and PDF rendering (`pdfx` or `syncfusion_flutter_pdfviewer`).

*Rejected alternatives: native Android (Jetpack Compose) — best latency but locks out future iPadOS; React Native — JS bridge latency is a non-starter for pen input.*

### 10.2 Stylus input: Flutter `Listener` + custom `CustomPainter`

- `onPointerDown/Move/Up` captures pressure + tilt + stylus-vs-finger source.
- Custom canvas paints at 60–90 FPS (matches OnePlus Pad Go 2 display).
- Strokes serialize to SVG on touch-lift.
- No platform channel needed.

### 10.3 Git client: **libgit2 via FFI** (`libgit2dart` or equivalent)

- Handles clone / pull / fetch / merge / commit / push / branch without shelling out.
- OAuth tokens stored in Android Keystore.
- Enough for Sync Down / Sync Up operations; no Working Copy-style OS-level integration needed on Android.

### 10.4 Markdown renderer: `flutter_markdown` + custom annotation overlay

- `flutter_markdown` for CommonMark + GFM rendering.
- Transparent `Stack` layer above for the annotation canvas.
- Scroll position is shared; strokes are anchored to content coordinates, not viewport.

### 10.5 PDF renderer: `pdfx` (open source) or `syncfusion_flutter_pdfviewer` (commercial)

- Page-by-page rendering as images; annotation canvas overlays each page.
- No native text selection in MVP (treat pages as images).
- Decide during Milestone 1b which library handles large PDFs better on the Pad Go 2.

### 10.6 Notifications: **none in Phase 1**

- Sync is manual. The user knows when they left home and when they arrived at the office.
- Phase 2b option: a GitHub Actions workflow on `claude-jobs` that POSTs to a third-party push service (Pushover, ntfy.sh) when `04-spec-*` files appear. The app receives a native push — no backend the user owns.

---

## 11. Competitive Landscape & Gap

| Product                     | What it does                                        | Gap for our use case                                      |
|-----------------------------|-----------------------------------------------------|-----------------------------------------------------------|
| **GitHub Mobile (Android)** | PR + issue triage                                   | No pen annotation, no markdown-level review workflow.     |
| **Linear Mobile**           | Issue tracking, PR review sync                      | Text-only comments; no spec-phase gating or pen.          |
| **GitHub Spec Kit** (2024)  | CLI spec-driven dev templates                       | Desktop-only; no review UI.                               |
| **Obsidian + Excalidraw**   | Markdown + embedded pen sketches                    | Not git-branch-aware; no review loops.                    |
| **Squid / Samsung Notes**   | Best-in-class Android pen note-taking               | Proprietary formats; no git round-trip.                   |
| **Xodo / Drawboard PDF**    | PDF annotation on Android                           | Writes into the PDF itself (binary, no git diff).         |
| **Claude Remote Control**   | Drive Claude Code from mobile                       | Real-time chat UX; no async review / pen / phase gate.    |

**The gap we fill:** an Android-first, pen-driven, offline-capable, git-sidecar-branch review loop that treats specs as the primary artifact and the desktop Claude as an execution partner you hand the review off to.

---

## 12. Phase-2 Forward Compatibility

Decisions to keep reversible in Phase 1 so Phase 2 (authoring) slots in cleanly:

- **R-1.** Markdown renderer must also work in an **edit mode** — don't hard-code "render → overlay" as the only pipeline.
- **R-2.** The annotation canvas shouldn't assume an underlying spec exists — Phase 2 may include annotating a freshly drafted spec.
- **R-3.** The commit helper takes a list of `(path, content)` pairs — not hard-coded filenames — so Phase 2 can commit `02-spec.md` instead of `03-review.md`.
- **R-4.** Phase-gate enforcement is *data-driven* (which marker files exist), never UI-driven. Phase 2 will add new commit paths that skip stages.
- **R-5.** Template discovery reads from `.gitmdannotations/templates/*` on `main`; the lookup path is stubbed in Phase 1 so Phase 2 just drops files into it.

---

## 13. Milestones

| Milestone | Scope                                                                                                          | Ship goal (solo dev) |
|-----------|----------------------------------------------------------------------------------------------------------------|----------------------|
| **1a**    | GitHub OAuth, repo picker, `claude-jobs` branch bootstrap, Sync Down, markdown read-only rendering, offline cache. | Week 2–3             |
| **1b**    | Pen annotation canvas (pressure + palm rejection), SVG serialization, PDF page rendering + annotation.             | Week 4–5             |
| **1c**    | Typed review panel, Submit Review, Approve, Sync Up, changelog writer, remote-wins conflict handling.              | Week 6–7             |
| **1d**    | Polish: history timeline, changelog viewer, local backup folder UI, edge-case recovery.                           | Week 8               |
| **2a**    | New Spec flow, template library, linting, tablet-author marker.                                                   | Post-launch          |
| **2b**    | GitHub Actions-driven push notifications (no app backend).                                                        | Post-launch          |
| **2c**    | Handwriting-to-text, dictation polish.                                                                            | Post-launch          |

---

## 14. Resolved decisions (formerly "Open questions")

| # | Decision                                                                                           |
|---|----------------------------------------------------------------------------------------------------|
| D-1 | **Platform:** Android only at launch. OnePlus Pad Go 2 is the target device. iPadOS deferred.    |
| D-2 | **Signed commits:** not in MVP. OAuth token is the only auth.                                    |
| D-3 | **Notifications:** none in Phase 1. Phase 2b uses GitHub Actions + a third-party push service.   |
| D-4 | **Merge conflicts:** assumed rare (tablet writes only to `claude-jobs/jobs/pending/`). When they happen, **remote wins**; local is archived as a backup. |
| D-5 | **Phase-2 templates:** both repo-local (`.gitmdannotations/templates/`) and bundled defaults, repo-local wins. Future work. |
| D-6 | **Change tracking:** 1-line human-readable changelog at the bottom of each `.md` file (or in sidecar `CHANGELOG.md` for PDFs). Both tablet and desktop append entries. **No diff viewer.** |
| D-7 | **Multi-device:** supported. GitHub.com remote is the source of truth; remote wins on conflict; local is archived as a backup. |
| D-8 | **Branch model:** tablet writes only to `claude-jobs` branch. `jobs/` never exists on `main`. On Sync Down, merge `main` into `claude-jobs` so Claude has latest source context. |
| D-9 | **Sync:** always manual, always user-initiated. Two buttons: **Sync Down**, **Sync Up**. No background sync.                                                         |
| D-10 | **PDF annotations:** stored as per-page SVG + PNG overlays next to the source PDF (same pipeline as markdown). Original PDF stays untouched. |

### Still open (narrow, non-blocking)

- **O-1.** Which PDF renderer library? (`pdfx` vs `syncfusion`) — decide during Milestone 1b based on Pad Go 2 performance.
- **O-2.** Does `Sync Down` also `git pull --rebase` on the `main` tracking branch, or only merge `main` into `claude-jobs`? Probably both, for completeness — revisit during 1a.
- **O-3.** Changelog timestamp format — local time (reader-friendly) vs ISO-8601 (machine-friendly) vs both? Default: `YYYY-MM-DD HH:mm` local, revisit if ambiguous.

---

## 15. Success Metrics

- **M-1.** 80%+ of specs get reviewed within 24 hours of being generated.
- **M-2.** User reports >50% of spec review happens away from a desk.
- **M-3.** Zero rework-because-of-misalignment PRs over a 3-month stretch (down from the baseline of 2–3 per month in the problem statement).
- **M-4.** Pen latency felt-experience: "feels like paper" on the Pad Go 2.
- **M-5.** Sync Down + Sync Up together complete in <15 s on office Wi-Fi for a typical session.

---

## 16. References

Research sources that informed this PRD:

1. [Flutter stylus detection across Android stylus devices](https://thiele.dev/blog/flutter-tablet-app-that-detects-stylus-apple-pencil-samsung-pen-open-source-app/)
2. [Open-source Flutter stylus demo (Stift)](https://github.com/AlexanderThiele/stift_flutter_app)
3. [Jetpack Compose stylus input in text fields](https://developer.android.com/develop/ui/compose/touch-input/stylus-input/stylus-input-in-text-fields)
4. [Obsidian Excalidraw plugin (pen + markdown)](https://github.com/zsviczian/obsidian-excalidraw-plugin)
5. [Markdown + Excalidraw cross-platform pattern](https://patrickwthomas.net/markdown-notes-with/)
6. [Flutter vs React Native in 2026](https://dev.to/dhruvjoshi9/flutter-vs-react-native-in-2026-i-tried-both-again-heres-the-one-id-bet-my-next-mobile-app-on-1k6h)
7. [GitHub Spec Kit](https://github.com/github/spec-kit)
8. [Spec-Driven Development guide (2026)](https://evangelistsoftware.com/blog/spec-driven-development-guide/)
9. [Linear PR review automation](https://linear.app/docs/pull-request-reviews)
10. [Linear GitHub integration](https://linear.app/integrations/github)
11. [GitHub PR review best practices (2026)](https://dev.to/rahulxsingh/github-pr-review-best-practices-and-tools-2026-1p90)
12. [GitHub changelog — SVG upload in markdown](https://github.blog/changelog/2022-01-21-allow-to-upload-svg-files-to-markdown/)
13. [SVG in markdown workflows](https://blog.mdconvrt.com/how-to-use-svg-images-in-markdown/)
14. [Draw.io GitHub markdown embedding](https://www.drawio.com/blog/embed-diagrams-github-markdown)
15. [Claude Code agentic workflow patterns](https://www.mindstudio.ai/blog/claude-code-agentic-workflow-patterns)
16. [Claude Code spec-driven workflow example](https://github.com/Pimzino/claude-code-spec-workflow)
17. [Claude Code headless / common workflows](https://code.claude.com/docs/en/common-workflows)

---

*End of PRD v2 draft. All D-1 through D-10 decisions locked in; O-1 through O-3 are tactical and non-blocking. Ready to start Milestone 1a.*
