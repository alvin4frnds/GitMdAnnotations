# Spec 002 — Editable markdown, inline images/Mermaid, standalone SVG viewer

**Status**: Draft — awaiting review
**Authored**: 2026-04-23
**Touches**: `lib/domain/entities/source_kind.dart`, `lib/domain/services/spec_repository.dart`, `lib/domain/services/commit_planner.dart`, `lib/domain/services/review_serializer.dart`, `lib/app/controllers/review_submitter.dart`, `lib/app/controllers/repo_browser_controller.dart`, `lib/ui/screens/repo_browser/repo_browser_screen.dart`, `lib/ui/screens/job_list/job_list_screen.dart`, `lib/ui/screens/spec_reader_md/`, `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart`, `lib/ui/screens/spec_reader_svg/` (new), `pubspec.yaml`
**Capacitor**: existing job MD/PDF review must not regress — SourceKind.svg is non-annotatable

---

## 1. Problem

The tablet app is a read-only viewer with two readers — `.md` (`SpecReaderMdScreen`) and `.pdf` (`SpecReaderPdfScreen`) — dispatched via `SourceKind` inside the job flow. Three gaps block ongoing spec work:

1. **Markdown is not editable.** `SpecReaderMdScreen` renders `SpecFile.contents` through `flutter_markdown`'s `Markdown` widget with only a `MarkdownStyleSheet`. There is no text editor, no save flow, and no commit path for an edited spec. Any in-flight fix or typo still needs a desktop round-trip.
2. **Inline image references in `.md` don't render.** `Markdown(...)` at `lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart:508` has no `imageBuilder`. An `.md` that says `![](diagrams/foo.png)` or embeds a ` ```mermaid ` fence shows nothing (for images) or a raw code block (for Mermaid). `flutter_svg ^2.0.10+1` is in `pubspec.yaml:35` but never instantiated for rendering user content.
3. **`.svg` is not a first-class file type.** The repo browser filter at `lib/app/controllers/repo_browser_controller.dart:121-123` allows only `.md` / `.markdown` / `.pdf`. There is no `SpecReaderSvgScreen`. Flow-charts and diagrams checked into a repo as standalone `.svg` files are invisible to the tablet.

The concrete ask: on the tablet, wherever a spec is opened (repo browser, job list), dispatch to the correct reader for **md / pdf / svg**. `.md` must be editable, and the markdown body must render inline **PNG/JPG**, **SVG**, and **Mermaid** (both fenced ` ```mermaid ` blocks and `![](file.mmd)` references). Mermaid is only ever embedded in markdown — there is no standalone `.mmd` editor.

## 2. Proposed Change

Three milestones, each QA-able independently (per `feedback_milestone_qa_loop`).

### Milestone A — Inline images, SVG viewer, dispatch everywhere

1. **`SourceKind.svg`** — add to `lib/domain/entities/source_kind.dart`. `dart analyze` will surface every switch/branch that needs an arm. Known sites:
   - `lib/domain/services/spec_repository.dart:105` — detect `spec.svg` alongside `spec.pdf`.
   - `lib/ui/screens/job_list/job_list_screen.dart:904` — new switch arm dispatching to `SpecReaderSvgScreen`.
   - `lib/ui/screens/job_list/job_list_screen.dart:1129` — `_FileKindChip` label `.svg`.
   - `lib/domain/services/commit_planner.dart:83,114,142,163` — non-annotatable path. Strokes with an `.svg` source error out; in practice the reader never offers Annotate so this is a defensive guard.
   - `lib/domain/services/review_serializer.dart:95`, `lib/app/controllers/review_submitter.dart:86,180,185`, `lib/ui/screens/submit_confirmation/planned_writes_preview.dart:46` — `.svg` branches. Treated as "pdf-but-no-annotations": changelog-only commit, no stroke artifacts.
2. **`SpecReaderSvgScreen`** — new file `lib/ui/screens/spec_reader_svg/spec_reader_svg_screen.dart`, modeled on `SpecReaderPdfScreen`. Body = `InteractiveViewer(minScale: 0.5, maxScale: 8, child: SvgPicture.file(File(filePath)))`. Top chrome = breadcrumb + close only (no Annotate/Submit in this scope).
3. **Inline `imageBuilder`** for `.md` reader at `spec_reader_md_screen.dart:508`. Extract to `lib/ui/screens/spec_reader_md/md_image_resolver.dart`:
   - Resolve relative URIs against `path.dirname(spec.path)`.
   - Dispatch on lowercased extension:
     - `.png` / `.jpg` / `.jpeg` / `.gif` → `Image.file`
     - `.svg` → `SvgPicture.file` (flutter_svg already in pubspec)
     - `.mmd` → `FutureBuilder` reads the file, hands to the Mermaid renderer (Milestone C). Until C lands: show a muted placeholder card with the raw source + "Mermaid preview pending".
     - Unknown → fall through to a muted "unsupported" card with the alt text.
4. **Repo-browser filter** — `repo_browser_controller.dart:121-123` adds `.svg`.
5. **Open-from-browser** — today `_FileRow` at `lib/ui/screens/repo_browser/repo_browser_screen.dart:272-316` only exposes "Convert to spec". Wrap the row body with an `InkWell onTap` that:
   - `.md`/`.markdown` → `SpecReaderMdScreen.fromPath(absPath)` (new named ctor that bypasses `specFileProvider` and reads via `FileSystemPort.readString`; `jobRef = null`).
   - `.pdf` → `SpecReaderPdfScreen(filePath: absPath, jobRef: null)`. Make `jobRef` nullable and gate Annotate/Submit chrome on non-null (same pattern as md at line 28).
   - `.svg` → `SpecReaderSvgScreen(filePath: absPath)`.
   - "Convert to spec" button stays for `.md` / `.pdf`; hidden for `.svg`.

### Milestone B — Markdown editor

1. **Mode toggle** on the existing `SpecReaderMdScreen` (`spec_reader_md_screen.dart:27`). Add an enum `{preview, edit, split}` held in the `StatefulWidget`. Swap `_MarkdownBodyView` for one of:
   - **preview** — today's `Markdown(...)` widget (reused verbatim, now with `imageBuilder`).
   - **edit** — `TextField(maxLines: null, controller: _controller)` + monospace token styling.
   - **split** — `Row` of edit on the left and preview on the right, preview rebuilt live from `_controller.text` on every change.
2. **Save flow** — new `lib/app/controllers/md_editor_submitter.dart`, mirroring `review_submitter.dart:32-146`. Builds a single `FileWrite(path: specPath, contents: newText)` and calls `GitPort.commit(files: [write], message: 'Edit <basename>', id: identity, branch: 'claude-jobs')`. No separate disk-write step — `GitPort.commit` already stages through `FileWrite` (same idea as the review submitter).
3. **Dirty tracking + confirm-on-back** — keep `_originalContents` + `_controller.text`. `bool get isDirty => _controller.text != _originalContents`. Wrap the screen with `PopScope` that shows a confirm sheet (same visual pattern as `_DeleteJobSheet` referenced at `job_list_screen.dart:926`: Cancel + Discard). Disable Save while `!isDirty`.
4. **Works from the repo browser too** — the `.fromPath` ctor added in Milestone A supports edit. For non-job files the commit goes to the default branch, not `claude-jobs`, and there is no changelog append — it's a plain file edit + commit.

### Milestone C — Mermaid renderer

Render ` ```mermaid ` fenced blocks and `![](file.mmd)` inline refs as diagrams.

1. **Engine** — no pure-Dart Mermaid renderer exists. Recommended: `webview_flutter` + bundled `assets/js/mermaid.min.js`. Runs fully offline.
2. **`MermaidView`** widget (`lib/ui/widgets/mermaid_view/mermaid_view.dart`) — hosts a headless `WebViewController` that loads a tiny HTML shell referencing the bundled JS asset, invokes `mermaid.render(id, source)` via a JS channel, and returns the rendered SVG string.
3. **Cache** — `lib/domain/services/mermaid_cache.dart`: SHA-256 key of the source text, written under app-docs `mermaid-cache/<sha>.svg`. Cache hit → skip WebView, render via `SvgPicture.string`. Cache miss → spin WebView, persist result, then render. Prevents spinning a WebView per diagram on re-open.
4. **Fenced-block builder** — `lib/ui/screens/spec_reader_md/md_mermaid_builder.dart`: a `MarkdownElementBuilder` for `code` that inspects `element.attributes['class']` for `language-mermaid` and returns a `MermaidView`; otherwise returns `null` and `flutter_markdown` falls back to default `pre/code` rendering. Wire via `Markdown(builders: {'code': ...})`.
5. **Inline `.mmd` refs** — the `imageBuilder` dispatch from Milestone A's `.mmd` branch routes to the same `MermaidView`.
6. **New deps** — `webview_flutter`, `crypto` (SHA-256). Asset: `assets/js/mermaid.min.js`.

### 2a. Scope — what changes

- `lib/domain/entities/source_kind.dart` — add `svg` variant.
- `lib/domain/services/spec_repository.dart` — `_detectSourceKind` gains `if (names.contains('spec.svg')) return SourceKind.svg;`. `_resolvePhase` gains a `spec.svg` fallback.
- `lib/domain/services/commit_planner.dart` — `_annotationWrites`, `_changelogTarget`, `_assertAnnotationPairing`, `_assertAnchorsMatchSource` each gain an `.svg` arm. SVG is non-annotatable (no stroke writes; pairing asserts both `md` and `pdf` annotations are null).
- `lib/domain/services/review_serializer.dart`, `lib/app/controllers/review_submitter.dart`, `lib/ui/screens/submit_confirmation/planned_writes_preview.dart` — handle `SourceKind.svg` per the compiler.
- `lib/app/controllers/repo_browser_controller.dart:121-123` — allow `.svg`.
- `lib/ui/screens/repo_browser/repo_browser_screen.dart` — row `InkWell onTap` with extension dispatch; "Convert to spec" hidden for `.svg`.
- `lib/ui/screens/job_list/job_list_screen.dart:904,1129` — svg arm + chip label.
- `lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart` — `imageBuilder`, `builders`, edit/split mode, `.fromPath` ctor.
- `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart` — make `jobRef` nullable; gate Annotate/Submit chrome on non-null.
- `pubspec.yaml` — add `webview_flutter`, `crypto`; declare `assets/js/mermaid.min.js`.
- **New**:
  - `lib/ui/screens/spec_reader_svg/spec_reader_svg_screen.dart`
  - `lib/ui/screens/spec_reader_md/md_image_resolver.dart`
  - `lib/ui/screens/spec_reader_md/md_mermaid_builder.dart`
  - `lib/ui/widgets/mermaid_view/mermaid_view.dart`
  - `lib/domain/services/mermaid_cache.dart`
  - `lib/app/controllers/md_editor_submitter.dart` + paired provider
  - `assets/js/mermaid.min.js`

### 2b. Scope — what stays the same

- **Job review pipeline** — Annotate / Submit / Approve for `.md` and `.pdf` jobs are untouched. `commit_planner` keeps its existing branches; `SourceKind.svg` adds a parallel arm.
- **Legacy annotation artifacts** — SVG + PNG + PDF + JSON quad on MD submit stays as-is (per `feedback_milestone_qa_loop`'s no-regression expectation).
- **Git / isolate** — no changes to `GitPort`, `_git_isolate`, or `FakeGitPort`. The editor submitter uses the existing `commit(files: [...], removals: [])` contract.
- **Repo picker / auth / sync** — no changes.
- **Existing `SpecReaderMdScreen` reader UX** — preview mode is default; edit is an explicit toggle. No behavior change unless the user enters edit.

## 3. Implementation notes

- **`jobRef` nullability** — the current `SpecReaderMdScreen` and `SpecReaderPdfScreen` both assume a job. Making `jobRef` nullable ripples into the chrome widgets (Annotate button, Submit button, outline rail). Gate each on `jobRef != null` rather than forking the widget trees. This is the smallest diff and keeps a single screen for both job-flow and browser-flow reads.
- **Commit branch for browser-flow edits** — for non-job `.md` files the repo browser is browsing the *default* checked-out branch (usually `main`), not `claude-jobs`. The editor submitter must inspect the current branch (via `GitPort.currentBranch` or equivalent) and commit back to that branch, not to `claude-jobs`. This is the main behavioral split between job-flow and browser-flow saves. If `GitPort` doesn't expose the current branch yet, extend it (keep the extension minimal: a single getter, no new commit params).
- **Mermaid first-paint latency** — WebView spin-up is ~200-500 ms on tablet. The cache matters: a spec with five fences on cold re-open should render from disk in one frame, not trigger five WebView constructions. Key on the *exact* source text SHA — whitespace differences invalidate intentionally (users expect a typo fix to re-render).
- **Inline `.mmd` rendering is async** — `imageBuilder` returns a widget synchronously. The `.mmd` branch must return a `FutureBuilder<Widget>` that shows a small "Rendering…" placeholder while reading the file and (on cache miss) running the WebView. Keep the placeholder height stable so scrolling doesn't jump.
- **SVG viewer is read-only** — no annotations planned in this scope. If later we want to annotate SVGs, the flow mirrors PDF annotations: reader owns an `InkOverlay`, submitter emits per-region SVG + PNG. Flag as a future spec; out of scope here.
- **`flutter_markdown` 0.7.4 API** — the `Markdown` widget supports both `imageBuilder: Widget Function(Uri uri, String? title, String? alt)` and `builders: Map<String, MarkdownElementBuilder>`. The inline image path uses `imageBuilder`; the fenced-code path uses a custom builder for `'code'`.
- **Offline guarantee** — `mermaid.min.js` ships as a bundled asset. No network requirements introduced by this spec.

## 4. UI — where it lives

- **Repo browser row** — single-tap the filename area (new `InkWell`) to open the reader matching the file extension. "Convert to spec" button unchanged for `.md` / `.pdf`; removed for `.svg`.
- **MD reader top bar** — add a three-state segmented control `{Preview | Split | Edit}`. Default = Preview. Save button appears when dirty; disabled otherwise. Discard confirmation on back when dirty.
- **MD editor pane** — full-height `TextField` with JetBrains Mono 14pt token. No syntax highlighting (out of scope).
- **Split view** — 50/50 by default. Drag handle between panes optional; keep fixed for the first cut.
- **SVG viewer** — blank canvas with centered SVG inside `InteractiveViewer`. Pinch-zoom + pan, same gestures as PDF reader. Top bar = breadcrumb + close only.
- **Mermaid diagrams inline** — render at the fence's natural position in the document flow. Width = content column width; height = rendered SVG aspect ratio. Muted border to visually separate from body text.

## 5. Test cases

### 5a. Domain / unit

- `test/domain/entities/source_kind_test.dart` — `SourceKind.values` includes `svg`.
- `test/domain/services/spec_repository_test.dart` — repo with `spec.svg` in `jobs/pending/<id>/` detects `SourceKind.svg` and phase `spec`.
- `test/domain/services/commit_planner_test.dart` — `.svg` source + null annotations → produces a changelog-only plan; `.svg` source + any strokes → throws `CommitPlannerAnchorKindMismatch` (or a new typed error).
- `test/app/controllers/md_editor_submitter_test.dart` (new) — happy path: given a `FakeGitPort`, `submit(path, contents, identity)` produces one commit with a single `FileWrite` and the expected message. Also asserts a dirty-but-unchanged (no-diff) save is a no-op (leans on `CommitNoop` from spec-001).
- `test/domain/services/mermaid_cache_test.dart` (new) — SHA keyed correctly; second call with identical source hits the cache.

### 5b. UI / widget

- `test/ui/screens/spec_reader_md/md_image_resolver_test.dart` (new) — given a `.md` at `/tmp/specs/foo.md` with `![](diagrams/a.png)`, the resolver returns an `Image.file('/tmp/specs/diagrams/a.png')`. Same for `.svg` → `SvgPicture.file`. `.mmd` → `FutureBuilder` (smoke assertion).
- `test/ui/screens/spec_reader_md/edit_mode_test.dart` (new) — toggle to edit, type a character, Save button enables; tap back without save → confirm sheet appears.
- `test/ui/screens/spec_reader_svg/spec_reader_svg_screen_test.dart` (new) — loads a file-fixture `.svg` and asserts `SvgPicture.file` is in the tree.
- `test/ui/screens/repo_browser/repo_browser_open_test.dart` (new) — tap row for `.svg` pushes `SpecReaderSvgScreen`; for `.md` pushes `SpecReaderMdScreen.fromPath`; for `.pdf` pushes `SpecReaderPdfScreen(jobRef: null)`.

### 5c. Manual / integration

Fixture repo under `workdir/test-fixtures/`:

1. `fixtures/inline.md` with:
   - `![png](diagrams/a.png)`, `![svg](diagrams/b.svg)`, `![mmd](diagrams/c.mmd)`
   - a ` ```mermaid\ngraph TD; A-->B\n``` ` fence
   - corresponding files dropped next to it
2. `fixtures/standalone.svg` and `fixtures/spec.pdf` at repo root

Checks (OnePlus Pad Go 2 / landscape):

- **Milestone A.** Repo browser → tap each file opens the correct reader. `inline.md` shows PNG + SVG inline; `.mmd` shows placeholder; fenced mermaid still raw-blocked. `standalone.svg` zooms/pans smoothly. Existing job MD/PDF review still opens and Submit still commits strokes.
- **Milestone B.** Open `inline.md` from the browser, toggle to edit, change a heading, Save. `git log` shows one commit with the expected message and file diff; `git status` clean. Dirty nav → confirm sheet blocks.
- **Milestone C.** Reopen `inline.md`. `.mmd` inline and fenced mermaid both render diagrams. Close and reopen — second load is fast (cache hit under `mermaid-cache/`). Touch the fence, change a node name, Save → diagram re-renders on next preview paint.

Per-milestone: run the full existing `integration_test/` suite to catch regressions in PDF raster / libgit2 paths.

## 6. Open Questions

- **Android WebView availability on OnePlus Pad Go 2.** The Mermaid path requires Android System WebView. Modern Android ships it by default but worth a one-minute on-device check before committing to `webview_flutter`. Fallback: keep the Milestone A `.mmd` placeholder (muted card + raw source) as the permanent behavior. Decision: verify at the start of Milestone C.
- **Milestone-B branch policy.** For a `.md` edited from the repo browser on `main`, should the commit land on `main`, or force-branch to `claude-jobs` like the job-flow does? Recommended: land on the currently checked-out branch (matches user mental model — "I'm editing what I see"). Force-branching would surprise users who pulled a fresh checkout.
- **Split view default ratio.** 50/50 is the planned default. Tablet landscape is ~2400×1600 with a left rail already eating ~220 px; preview at 50% may feel cramped. Open to user feedback in QA round 1.
- **`.svg` annotation.** Out of scope. Flag: if users start asking to pen-annotate SVGs (diagrams + review marks), that's a future spec following the PDF-annotation pattern.
- **"Edit everywhere" vs job-flow only.** Current plan: edit works for both job-flow MD (`SpecReaderMdScreen(jobRef: …)`) *and* browser-flow MD (`SpecReaderMdScreen.fromPath(...)`). Is this the user's intent, or should edit be gated to job-flow only? Recommended: enable both; limiting to job-flow would mean typos in `docs/` still need a desktop round-trip.

## 7. Critical files (reference)

- `lib/domain/entities/source_kind.dart` — enum, add `svg`.
- `lib/domain/services/spec_repository.dart:104-111` — detect kind, resolve phase.
- `lib/domain/services/commit_planner.dart:83-176` — annotation writes + pairing asserts.
- `lib/app/controllers/review_submitter.dart:86,180,185` — source-kind branches.
- `lib/app/controllers/repo_browser_controller.dart:108-124` — file-type filter.
- `lib/ui/screens/repo_browser/repo_browser_screen.dart:272-316` — `_FileRow` — add onTap.
- `lib/ui/screens/job_list/job_list_screen.dart:896-915,1122-1140` — open-job dispatch + kind chip.
- `lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart:27,499-574` — host the edit toggle, wire `imageBuilder` + `builders`.
- `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart:36-49` — nullable `jobRef`.
- `pubspec.yaml:35,44,62` — existing `flutter_svg`, `flutter_markdown`, `pdfx`; add `webview_flutter` + `crypto` + mermaid asset.

## 8. Verification plan

1. `flutter analyze` clean after each milestone.
2. Unit + widget tests green, including the new `md_editor_submitter_test`, `md_image_resolver_test`, `mermaid_cache_test`, `spec_reader_svg_screen_test`.
3. Manual QA on the OnePlus Pad Go 2 per §5c, per-milestone, fresh context (per `feedback_milestone_qa_loop`). Triage Critical/High before moving to the next milestone; defer rest to `docs/Issues.md`.
4. Regression: existing `integration_test/` suite — particularly PDF raster (`pdf_raster_test.dart`) and libgit2 clone/commit paths — must stay green.
5. Commit cadence: follow `feedback_git_workflow` — commit after every logical chunk on the current branch; the user handles pushes.
