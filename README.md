# GitMdScribe

> Pen-driven spec review, synced to git.

A tablet app (status: design only — [see below](#status)) that turns the commute, the couch, and the bedside hour into productive spec-review time for AI-assisted coding. Part of a mobile + tablet + desktop workflow that enforces hard gates between specification and implementation — so Claude Code can't "helpfully skip ahead" and miss what you actually wanted built.

## Why

Vibe coding with AI assistants fails in a predictable way: given "build X," the AI silently makes dozens of assumptions, skips edge cases, and produces code whose misalignment only shows up after implementation — when rework is expensive. The same AI, asked instead to *write a spec*, naturally surfaces open questions and edge cases. The bottleneck isn't capability; it's workflow.

Desktop tools collapse specification and implementation into one step. Mobile tools are built for real-time chat, not asynchronous review. Your best thinking time (commutes, couch, bed) is lost because typing detailed technical thoughts on a phone is painful, and no existing tablet app handles git-driven, pen-annotated spec review.

## How it works

Five hard-gated phases, each run on the device best suited for it:

| # | Phase            | Device     | Artifact                                           |
|---|------------------|------------|----------------------------------------------------|
| 1 | Requirements     | Mobile     | `01-requirements.md`                               |
| 2 | Spec Generation  | Desktop    | `02-spec.md` (Claude Code headless)                |
| 3 | **Spec Review**  | **Tablet** | `03-review.md` + `03-annotations.svg` / `.png`     |
| 4 | Spec Revision    | Desktop    | `04-spec-v2.md`, `04-spec-v3.md`, …                |
| 5 | Implementation   | Desktop    | PR into `main`; `jobs/pending/spec-<id>/` cleaned up |

Everything lives on a **sidecar branch** (`claude-jobs`) so `main` stays clean. The desktop watcher drives Claude Code in headless mode using the user's existing Claude Max subscription — **no Anthropic API key, no backend, no proxy.** Git is the bus.

## The tablet app (this repo's focus)

- **Phase 1:** Review `02-spec.md` or source PDFs with a stylus. Pen strokes serialize to SVG (git-diffable) + PNG (fidelity snapshot). Typed answers live in `03-review.md`. One-line human-readable changelog entries track every change at the bottom of each spec file.
- **Phase 2:** Author specs directly on the tablet, bypassing the desktop round-trip. Templates plus on-device linting.

### UX principles

- **Offline-first.** Review, annotate, commit locally without network. Two explicit buttons — **Sync Down** and **Sync Up** — handle all network state. No auto-sync, no push notifications in Phase 1.
- **Pen-native.** Pressure sensitivity, palm rejection, <25 ms ink latency on the target device (OnePlus Pad Go 2). Ink strokes anchor to markdown line numbers or PDF page regions so the desktop Claude knows *what* was annotated, not just that annotations exist.
- **Phase gates live in the filesystem.** The tablet is the only thing that can drop `05-approved`. Claude physically cannot skip ahead.
- **Remote wins on conflict.** GitHub is the source of truth. Local changes on conflict are archived to a backup folder — never lost, never automatically merged.

## Tech stack (planned)

- **Flutter** — Android first (OnePlus Pad Go 2). iPadOS deferred.
- **libgit2** via FFI for all git operations (clone, fetch, merge, commit, push).
- **GitHub OAuth Device Flow** — no backend, no client secret in the app binary. PAT paste-in as fallback.
- **Android Keystore** (via `flutter_secure_storage`) for access token + git identity.
- **SVG + PNG hybrid** for annotation storage — SVG is text-diffable in git, PNG is the rendering-fidelity snapshot.

## Status

**Pre-implementation.** No code yet. This repo currently contains design artifacts only:

- [`docs/initial/ProblemStatement.txt`](docs/initial/ProblemStatement.txt) — source problem statement and user-journey vignette.
- [`docs/PRD/TabletApp-PRD.md`](docs/PRD/TabletApp-PRD.md) — full Product Requirements Doc (v2, ~620 lines). Goals / non-goals, functional + non-functional requirements, data model, branch strategy, auth flow detail, theme tokens, tech stack rationale, resolved design decisions.
- [`docs/PRD/mockups.html`](docs/PRD/mockups.html) — 12-screen interactive mockup of the tablet user journey. Open in any browser. Light and dark themes; `d` toggles.

**Milestone 1a** (GitHub OAuth + repo picker + `claude-jobs` branch bootstrap + markdown read-only rendering + offline cache) is the first build target. See the PRD §13 for the full milestone map.

## Documentation

Start with the PRD — everything else is derived from it:

- [**Tablet App PRD v2**](docs/PRD/TabletApp-PRD.md)
- [**Interactive mockups**](docs/PRD/mockups.html) — walk the 12-screen journey (sign in → Sync Down → review → annotate → submit → Sync Up → revision → approve → conflict → new spec).
- [**Problem statement**](docs/initial/ProblemStatement.txt) — the motivation, the Monday-evening-to-Tuesday-evening vignette, and the constraints that shaped everything downstream.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal, research, educational, hobby, and other noncommercial use. Commercial use requires a separate license.
