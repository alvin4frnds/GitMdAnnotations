# spec-005: Multi-select + batch "Convert to spec" in the repo browser

**Slug:** `batch-convert-to-spec`  **Status:** Draft  **Authored:** 2026-07-03

> The repo browser converts exactly one file at a time today: each `.md`/`.pdf`
> row carries a "Convert to spec" button that fires `SpecImportController.run(relPath)`
> (`repo_browser_screen.dart:223-231`). Reviewers importing a batch of source docs
> tap-wait-tap-wait N times. This spec adds a left-hand checkbox per convertible row,
> a select-all toggle, a single "Convert N selected" action that loops the **existing**
> importer once per file, and a determinate progress bar with Cancel. Per the pre-spec
> interview: **per-file commits (N commits), skip-and-report on failure**, and the
> **full UI** (checkbox + select-all + cancel + progress).

---

## 1. Context

The "convert existing repo file → spec" flow is single-file only. The wiring, end to end:

- Entry point: JobList "New spec" button pushes `RepoBrowserScreen` (`job_list_screen.dart:101-104`, `:153-159`).
- Browser screen: `RepoBrowserScreen` (`lib/ui/screens/repo_browser/repo_browser_screen.dart:22`) watches `repoBrowserControllerProvider` (dir listing) + `specImportControllerProvider` (import outcome), and pops on `SpecImportSuccess` (`:36-42`).
- Row list: `_EntryList` (`repo_browser_screen.dart:198`) is a `ListView.separated`; each entry is a `_DirectoryRow` (`:274`) or a `_FileRow` (`:314`).
- `_FileRow` today (`:314-397`): `Material > InkWell(onTap: onOpen) > Padding > Row[ description icon, name+relPath column, "Convert to spec" ElevatedButton ]`. The button is hidden for `.svg` (`:331`, `:372` — SVG is non-annotatable, spec-002). Row-body tap **opens** the reader (`_openFile`, `:236`); only the button **converts**.
- Convert action: `SpecImportController.run(sourceRelPath)` (`lib/app/controllers/spec_importer.dart:280-314`) → guards `state.isLoading` re-entry (`:281`), requires `AuthSignedIn` (`:292-298`), builds a `SpecImporter` from `fileSystemProvider`/`gitPortProvider`/`clockProvider` (`:299-303`), calls `importFromRepoPath(...)`.
- One conversion = one git commit: `SpecImporter.importFromRepoPath` (`spec_importer.dart:43-125`) reads the source, slugifies via `slugify()` (`:233`), resolves name collisions with `-2, -3, …` by probing `$workdir/jobs/pending/<candidate>` (`_resolveCollision`, `:214-225`), writes `jobs/pending/<jobId>/02-spec.md` (+ inline images) or `spec.pdf`, then `_git.commit(files, message: 'Import <path> as <jobId>', branch: 'claude-jobs')` (`:112-117`). Returns sealed `SpecImportOutcome` (`:253`): `SpecImportSuccess{job, commit}` / `SpecImportCancelled` / `SpecImportFailure{message, cause}`.
- Post-success: the JobList top chrome `ref.listen`s `specImportControllerProvider` and, on `SpecImportSuccess`, shows a SnackBar and calls `ref.invalidate(jobListControllerProvider)` + `ref.invalidate(pendingPushCountProvider)` (`job_list_screen.dart:538-564`).

**No multi-select exists anywhere in the app.** There is no `Checkbox`, no selection-set state, no bulk action. This spec introduces the first one.

**Reusable patterns to mirror exactly:**

- **Stream→sealed-state controller:** `SyncController` (`lib/app/controllers/sync_controller.dart:48-92`) maps a run onto a sealed `SyncState` (`SyncIdle`/`SyncInProgress`/`SyncDone`/`SyncErrored`, `:14-42`), guards re-entry with `bool _running` (`:49`, `:62-63`), flips state synchronously on start so the UI reflects in-flight from the first frame (`:64-68`). The new `BatchConvertController` mirrors this skeleton: a sealed `BatchConvertState`, `_running` guard, synchronous flip to `BatchRunning`.
- **Determinate/inline progress bar already in the browser:** `if (importState.isLoading) const LinearProgressIndicator(minHeight: 2)` (`repo_browser_screen.dart:159`). The batch bar is a determinate variant (`value: done/total`) in the same slot.
- **Invalidate-on-terminal:** `job_list_screen.dart:514-515`, `:549-550` — `ref.invalidate(jobListControllerProvider)` + `ref.invalidate(pendingPushCountProvider)`.
- **Importer test harness:** `test/app/controllers/spec_importer_test.dart` — `FakeFileSystem` + `FakeGitPort` + `_FixedClock`, no mocking library (CLAUDE.md "fakes over mocks"). The batch test mirrors it exactly.

**Convertible vs not** (mirror the existing rule): a row is convertible iff it is a file (`!entry.isDirectory`) whose name does **not** end in `.svg` (`repo_browser_screen.dart:331`). `.md`/`.markdown`/`.pdf` are convertible; directories and `.svg` are not and get **no checkbox**.

**User-confirmed scope from the pre-spec interview:**

- Failure model: **per-file commits, skip failures** — N commits, one per file, reusing `SpecImporter` unchanged. A failing file (name collision surfaced as a git error, unreadable source) is skipped; the rest convert; the summary reports which failed. Partial success is allowed and expected.
- UI scope: **full** — left checkbox per convertible row, a select-all toggle, a "Convert N selected" action bar, a determinate progress bar (k of n) with a Cancel button.

## 2. Objective

After this ships, a reviewer in the repo browser can tick a checkbox on any subset of convertible files, optionally "select all" in the current folder, and tap "Convert N selected" once. The app converts them sequentially — one commit per file on `claude-jobs`, exactly as a single convert does today — showing a determinate progress bar (k/n + current filename) that they can Cancel. Files that fail to convert are skipped and named in a summary ("Converted 4, 1 failed") without aborting the batch; the single-file "Convert to spec" button keeps working unchanged.

## 3. Assumptions

- `SpecImporter.importFromRepoPath` (`spec_importer.dart:43`) is safe to call sequentially in a loop; each call is self-contained (reads source, one commit) with no shared mutable state between calls today. The only cross-call coupling this spec must add is **in-batch jobId reservation** (see §5 / AC-8).
- `GitPort.commit` to the `claude-jobs` sidecar branch does **not** materialize `jobs/pending/<jobId>/` into the on-disk working tree (the working tree tracks the current/`main` branch, not `claude-jobs`). Therefore `_resolveCollision`'s disk probe (`spec_importer.dart:215`, `_fs.exists('$workdir/jobs/pending/<candidate>')`) will **not** see specs committed earlier in the same batch. This is why AC-8's in-memory reservation is required and not optional. `<INPUT_REQUIRED>` to confirm the `GitAdapter` behavior — but the reservation design is correct either way, so it is not a blocker.
- `Notifier`/`AutoDisposeNotifier` subclasses can call `ref.invalidate(...)` and `ref.read(...)` (they hold a `Ref`); the batch controller invalidates `jobListControllerProvider` + `pendingPushCountProvider` on finish, mirroring `job_list_screen.dart:549-550`.
- Selection is keyed by `RepoBrowserEntry.relPath` (repo-relative, forward-slash, unique — `repo_browser_controller.dart:18-19`). A `Set<String>` of relPaths is the selection model.
- The current `AutoDisposeNotifier` re-entry guard idiom (`spec_importer.dart:281`, `sync_controller.dart:62`) is the project's re-entrancy convention; the batch controller adopts it.
- No new package is needed. `Checkbox`, `LinearProgressIndicator` are Flutter SDK; everything else is existing Riverpod 2 (no code-gen).

## 4. Out of Scope

- **Single atomic multi-file commit.** Rejected in the interview in favor of per-file commits. Reason: per-file reuses `SpecImporter` verbatim, keeps the existing `Import <path> as <jobId>` message + one-revert-per-spec granularity, and is the only model that supports partial success. An atomic-commit variant is a separate spec if ever wanted.
- **Recursive / cross-folder "select all".** "Select all" toggles only the convertible entries in the **currently listed** directory (`repoBrowserControllerProvider`'s `entries`). Reason: the browser lists one directory at a time (`repo_browser_controller.dart:80-107`); a recursive walk is a different feature with its own tree-walk + perf cost.
- **Reordering / prioritizing the conversion order.** Files convert in listing order (directories-first, then name-sorted — `repo_browser_controller.dart:102-105`). Reason: no user need expressed; deterministic order is enough.
- **Retry-failed-only affordance.** The summary names failures but offers no one-tap retry. Reason: the user can re-tick and re-run; a dedicated retry queue is gold-plating for v1.
- **Progress persistence across screen dispose.** If the user backs out of the browser mid-batch, the `autoDispose` controller dies and the in-flight file finishes but state is lost. Reason: matches every other `autoDispose` flow in the app; a resumable job queue is out of scope.
- **Converting `.svg`.** Unchanged: SVG is non-annotatable (spec-002), gets no checkbox and no convert path.
- **Changing single-convert behavior** (auto-pop on success, `repo_browser_screen.dart:39-42`). The single-row button and its pop-on-success are preserved exactly; batch is additive.

## 5. Open Questions / `<INPUT_REQUIRED>`

- **OQ-1 — Selection persistence across folder navigation.** Chosen default: selection **persists** across `enter`/`up` (the `Set<String>` is keyed by repo-relative path and is not cleared on navigation), so a user can check files in folder A, browse into folder B, and convert both. The action-bar count reflects the total across folders. If the intended UX is per-directory-only (clear selection on navigate), that is a one-line change (`clear()` in `enter`). **Confirm** the persist default is desired; low-risk either way.
- **OQ-2 — `GitAdapter.commit` working-tree materialization** (see §3). Confirm whether a `claude-jobs` commit writes `jobs/pending/` into the on-disk workdir. The AC-8 in-memory reservation makes the batch correct regardless, so this is informational, not blocking.
- **OQ-3 — Cancel granularity.** Cancel stops **after** the in-flight file's commit completes (a git commit is not safely interruptible mid-write). Confirm this "finish current, then stop" semantic is acceptable (the alternative — killing the isolate mid-commit — risks a corrupt sidecar and is explicitly not done).

## 6. Pre-flight Checklist

- [ ] Required skill loaded: **`clean-code`** — Always.
- [ ] Required skill loaded: **`test-driven-development`** — new behavior (batch loop, selection, skip-on-failure, cancel, jobId reservation); every AC gets a failing test first (CLAUDE.md "TDD is the iron law").
- [ ] `vibesec` — **not required.** No new auth/token/secret/external-input surface; the batch reuses the existing `AuthSignedIn` gate (`spec_importer.dart:292-298`) and the same `GitPort.commit`. If the implementation adds any new network or token path, stop and load `vibesec`.
- [ ] Working tree clean; branch up to date with `main`.
- [ ] Signed in on the dev build (batch requires `AuthSignedIn`, same as single convert).
- [ ] Read before editing: `lib/ui/screens/repo_browser/repo_browser_screen.dart:116-397`, `lib/app/controllers/spec_importer.dart:43-125,214-319`, `lib/app/controllers/sync_controller.dart:44-92`, `lib/app/providers/spec_import_providers.dart`, `lib/app/controllers/repo_browser_controller.dart:9-35`, `job_list_screen.dart:538-564`.
- [ ] Read the test template: `test/app/controllers/spec_importer_test.dart` (fakes, `_FixedClock`, group structure).
- [ ] Confirm `fvm flutter test` (host VM) is green **before** starting — batch controller + widget tests run on host; only the on-device QA (§12b FE) needs the tablet.

## 7. Acceptance Criteria

- **AC-1 — Checkbox on convertible rows only.** In `_EntryList`, each convertible file row (`.md`/`.markdown`/`.pdf`) renders a leading `Checkbox` at the left of the row. Directory rows and `.svg` rows render **no** checkbox (asserted in a widget test that seeds one of each).
- **AC-2 — Toggle updates count; selection persists across navigation.** Ticking a row adds its `relPath` to the selection set and the action bar shows "N selected"; unticking removes it. Navigating into a folder and back (`enter`/`up`) preserves prior selections (per OQ-1 default).
- **AC-3 — Select all / clear (current directory).** A "Select all" control ticks every convertible entry currently listed; when all are already selected it flips to "Clear" and deselects them. Directories/`.svg` are never included.
- **AC-4 — "Convert N selected" runs per-file commits.** With N rows selected, the action bar's "Convert N selected" button starts a batch that calls `SpecImporter.importFromRepoPath` once per selected relPath, producing **N commits** on `claude-jobs`, each with message `Import <path> as <jobId>` (byte-identical to single convert). Verified in the batch controller test with a `FakeGitPort` recording N commits.
- **AC-5 — Determinate progress bar.** While the batch runs, a `LinearProgressIndicator(value: done/total)` plus the label `Converting <done>/<total> · <basename(current)>` renders in the browser (in the slot currently at `repo_browser_screen.dart:159`). `done` increments after each file's commit resolves.
- **AC-6 — Skip-and-report on failure.** Given 3 selected files where the middle one fails (source unreadable → `FsError`, or `GitError` on commit), the batch converts files 1 and 3 and records file 2 as a failure; final state is `BatchFinished{converted:[f1,f3], failures:[f2], cancelled:false}` and the summary SnackBar reads "Converted 2, 1 failed". No exception escapes; the loop does not abort early.
- **AC-7 — Cancel stops after the in-flight file.** Tapping Cancel mid-batch sets a cancel flag; the loop finishes the current file's commit, then stops. Already-committed specs remain; remaining selected files are left unconverted. Final state `BatchFinished{cancelled:true}`; summary notes the cancel (e.g. "Converted 1, cancelled — 2 not run").
- **AC-8 — In-batch jobId collision resolved.** Two selected files that slugify to the same base (e.g. `a/notes.md` and `b/notes.md` → both `spec-notes`) produce **distinct** jobIds (`spec-notes`, `spec-notes-2`) even though the first commit is not visible to the disk probe. Implemented by threading a growing `reservedJobIds` set: `importFromRepoPath({..., Set<String> reservedJobIds = const {}})` and `_resolveCollision` treating a candidate as taken when `reservedJobIds.contains(candidate) || await _fs.exists(...)`; the batch controller adds each returned `job.jobId` to the set before the next file. Verified with a `FakeGitPort` whose commit does **not** write to the fake FS.
- **AC-9 — Terminal invalidation + badge.** On `BatchFinished` with ≥1 conversion, the batch controller calls `ref.invalidate(jobListControllerProvider)` + `ref.invalidate(pendingPushCountProvider)`. After closing the browser, the JobList shows the new spec rows and the unpushed-push badge increased by the number converted.
- **AC-10 — Auth gate.** Starting a batch while signed out (no `AuthSignedIn`) performs **zero** commits and ends in a failure summary ("Sign in before importing specs."), mirroring `spec_importer.dart:292-298`.
- **AC-11 — Re-entrancy + mutual exclusion.** While a batch is running, `_running` makes a second "Convert N selected" a no-op; the per-row single "Convert to spec" buttons, checkboxes, select-all, and directory navigation are disabled (the existing `disabled` flag in `_EntryList` at `repo_browser_screen.dart:216,225,230` is extended to `importState.isLoading || batchRunning`).
- **AC-12 — Single-convert path unchanged.** The per-row "Convert to spec" button still fires `SpecImportController.run` and the browser still auto-pops on `SpecImportSuccess` (`repo_browser_screen.dart:39-42`). `fvm flutter test test/app/controllers/spec_importer_test.dart` stays green (existing assertions intact; the new `reservedJobIds` param defaults to `const {}` so existing call sites are untouched).

## 8. Implementation Guardrails

### 8a. Hard NO list

- **Do not modify `SpecImporter.importFromRepoPath`'s existing behavior** beyond adding the optional `reservedJobIds` parameter (defaulted so no existing caller changes). The commit message, branch (`claude-jobs`), file paths (`02-spec.md` / `spec.pdf`), provenance header, and inline-image copy stay byte-identical. `git diff lib/app/controllers/spec_importer.dart` must touch only the signature at `:43-48`, the `_resolveCollision` signature/body at `:214-225`, and its one call site at `:78`.
- **Do not write to `main`, and do not delete anything.** The batch only appends under `jobs/pending/spec-<id>/` on `claude-jobs`, same contract as single convert (CLAUDE.md "Branch and file contracts").
- **Do not make the batch atomic / all-or-nothing.** Per-file commits with partial success is the chosen model (§4). A single combined `GitPort.commit(files: allWrites)` is explicitly wrong here.
- **Do not interrupt a git commit mid-flight on Cancel.** Cancel is checked between files only (OQ-3). Never cancel the isolate mid-commit.
- **Do not reuse `SpecImportController` for the batch.** It holds a single `AsyncValue<SpecImportOutcome?>` and pops-on-success; the batch needs its own sealed multi-file state and must not pop. Add a separate `BatchConvertController`.
- **Do not clear selection on every list rebuild.** Selection lives in its own notifier and survives `repoBrowserControllerProvider` re-lists; only `clear()` (post-batch or user action) empties it.
- **Do not exceed the size limits on the new files.** Functions ≤ 50 lines, files ≤ 200 lines (CLAUDE.md). `repo_browser_screen.dart` is already 443 lines — put the new action bar + progress bar in a **new** sibling file, not inline, to avoid growing it further than the minimal checkbox + wiring.

### 8b. Coding / quality principles

- **`clean-code`** — domain-named types: `BatchConvertController`, `BatchConvertState` (`BatchIdle`/`BatchRunning`/`BatchFinished`), `BatchFailure`, `RepoSelectionController`. No `utils`/`helpers`/`common`. Early-return on `_running`, on empty selection, on signed-out. The per-file loop body is one short method; the widget reads state and renders (no business logic in widgets).
- **`test-driven-development`** — write these RED first, then GREEN: `test/app/controllers/batch_spec_importer_test.dart` (AC-4/6/7/8/9/10), `test/app/controllers/repo_selection_controller_test.dart` (AC-2/3), `test/ui/screens/repo_browser/repo_browser_batch_test.dart` (AC-1/5/11/12), and extend `test/app/controllers/spec_importer_test.dart` for `reservedJobIds` (AC-8). Verify red, then implement.
- **Mirror existing patterns by `path:line`:**
  - Sealed-state + `_running` + synchronous flip: `sync_controller.dart:44-92`.
  - Auth gate + `SpecImporter` construction from providers: `spec_importer.dart:290-303`.
  - Terminal invalidation: `job_list_screen.dart:549-550`.
  - Provider registration idiom: `spec_import_providers.dart:7-16`.
  - Fakes-only test harness: `test/app/controllers/spec_importer_test.dart`.

## 9. Behavior Spec (per file)

### `lib/app/controllers/spec_importer.dart`

- **Current state (`:43-48`, `:76-78`, `:214-225`):** `importFromRepoPath` takes `{sourceRelPath, repo, workdir, identity}`; jobId via `_resolveCollision(baseSlug, workdir)` which probes disk only.
- **Required edit:** add optional `Set<String> reservedJobIds = const {}` to `importFromRepoPath`; pass it into `_resolveCollision(baseSlug, workdir, reservedJobIds)`; in `_resolveCollision`, treat a candidate as taken when `reservedJobIds.contains(candidate) || await _fs.exists('$workdir/jobs/pending/$candidate')` (apply to both the base and the `-n` loop).
- **Estimated diff:** ~12 LOC.
- **Subtleties:** default `const {}` keeps all existing callers (`SpecImportController.run`, `:304`) unchanged. This is the sole change to the shared importer; do not touch commit/message/paths.

### `lib/app/controllers/repo_selection_controller.dart` (new)

- **Required edit:** new file. `class RepoSelectionController extends AutoDisposeNotifier<Set<String>>` with `build() => const {}` and methods `toggle(String relPath)`, `selectAll(Iterable<String> relPaths)` (union), `deselectAll(Iterable<String> relPaths)` (difference — used when select-all flips to clear for the current dir), `clear()`, and `bool isSelected(String relPath)`. State is an unmodifiable copy on each mutation (no in-place mutation of the exposed `Set`).
- **Estimated diff:** ~55 LOC.
- **Subtleties:** `autoDispose` so it dies with the browser route (CLAUDE.md scoped-session rule). Selection is not cleared on directory navigation (OQ-1). Keep it dumb — it knows nothing about conversion.

### `lib/app/controllers/batch_spec_importer.dart` (new)

- **Required edit:** new file. Sealed `BatchConvertState`: `BatchIdle`; `BatchRunning({int total, int done, String currentRelPath, List<BatchFailure> failures})`; `BatchFinished({List<JobRef> converted, List<BatchFailure> failures, bool cancelled})`. `class BatchFailure { final String relPath; final String message; }`. `class BatchConvertController extends AutoDisposeNotifier<BatchConvertState>` with `build() => const BatchIdle()`, `bool _running`, `bool _cancelRequested`, `Future<void> run(List<String> relPaths)`, `void cancel()`. `run`: early-return if `_running` or `relPaths.isEmpty`; read `currentRepoProvider`/`currentWorkdirProvider`; require `AuthSignedIn` (mirror `spec_importer.dart:292-298`) else `BatchFinished` with an all-failed summary and zero commits; build one `SpecImporter`; loop the list — before each file check `_cancelRequested` (stop → `BatchFinished{cancelled:true}`), set `BatchRunning{done, currentRelPath}`, call `importFromRepoPath(..., reservedJobIds: assigned)`, on `SpecImportSuccess` add `job.jobId` to `assigned` + `job` to converted, on `SpecImportFailure`/caught error append a `BatchFailure`; after the loop set `BatchFinished` and, if `converted.isNotEmpty`, `ref.invalidate(jobListControllerProvider)` + `ref.invalidate(pendingPushCountProvider)`. `cancel()` sets `_cancelRequested = true`.
- **Estimated diff:** ~120 LOC.
- **Subtleties:** `assigned` is the in-batch reservation set (AC-8). Guard `_running` in a `try/finally` like `sync_controller.dart:62-91`. Flip to `BatchRunning` synchronously before the first `await` so the bar shows from frame one. Do **not** pop the browser.

### `lib/app/providers/spec_import_providers.dart`

- **Current state (`:7-16`):** registers `specImportControllerProvider` + `repoBrowserControllerProvider`.
- **Required edit:** add `final repoSelectionControllerProvider = NotifierProvider.autoDispose<RepoSelectionController, Set<String>>(RepoSelectionController.new);` and `final batchConvertControllerProvider = NotifierProvider.autoDispose<BatchConvertController, BatchConvertState>(BatchConvertController.new);`.
- **Estimated diff:** ~+14 LOC.
- **Subtleties:** keep them `autoDispose` to match the browser's scoped lifetime.

### `lib/ui/screens/repo_browser/batch_convert_bar.dart` (new)

- **Required edit:** new file with two `ConsumerWidget`s (public within the package, no leading underscore so they can live outside the screen file): `SelectionActionBar` — shown when selection is non-empty and no batch is running; renders "N selected", a "Select all"/"Clear" text button (computed against the current directory's convertible entries), and a primary "Convert N selected" button that calls `batchConvertControllerProvider.notifier.run(selected.toList())`. `BatchProgressBar` — shown while `BatchRunning`; renders `LinearProgressIndicator(value: done/total)` + `Converting <done>/<total> · <basename>` + a "Cancel" `TextButton` calling `.cancel()`.
- **Estimated diff:** ~90 LOC.
- **Subtleties:** `basename` already exists (`spec_importer.dart:246`) — reuse it, do not re-implement. Use theme tokens (`context.tokens`) for colors, mirroring `_FailureBanner` (`repo_browser_screen.dart:399-442`). Keep each widget's `build` ≤ 50 lines.

### `lib/ui/screens/repo_browser/repo_browser_screen.dart`

- **Current state (`:116-171`, `:198-234`, `:314-397`):** `_Body` renders failure banner + `if (importState.isLoading) LinearProgressIndicator` + `_EntryList`; `_EntryList` builds `_DirectoryRow`/`_FileRow` with a `disabled` flag from `importState.isLoading`; `_FileRow` has no checkbox.
- **Required edit:**
  - `RepoBrowserScreen.build`: also watch `batchConvertControllerProvider`; `ref.listen` it — on `BatchFinished` show a summary SnackBar and call `repoSelectionControllerProvider.notifier.clear()`; do **not** pop.
  - `_Body`: compute `batchRunning = batchState is BatchRunning`; pass `disabled: importState.isLoading || batchRunning` to `_EntryList`; render `SelectionActionBar` above the list when selection non-empty and not running; swap the line-159 indicator for `BatchProgressBar` when `batchRunning` (keep the thin single-import bar for `importState.isLoading`).
  - `_EntryList`/`_FileRow`: for convertible file rows, add a leading `Checkbox(value: isSelected, onChanged: disabled ? null : (_) => selection.toggle(relPath))` as the first child of the `Row` (before the description icon at `:341`); read selection via `ref.watch(repoSelectionControllerProvider.select((s) => s.contains(relPath)))` to avoid rebuilding the whole list on every toggle. Directory rows and `.svg` rows get no checkbox.
- **Estimated diff:** ~+70 LOC (checkbox + wiring + bar mounts + listener).
- **Subtleties:** `_FileRow` is currently `StatelessWidget`; converting the checkbox lookup to a `Consumer`/`ConsumerWidget` (or wrapping just the checkbox in a `Consumer`) keeps rebuilds narrow. The row-body tap (`onOpen`) and the single "Convert to spec" button both stay; the checkbox is additive. Keep `_FileRow.build` ≤ 50 lines — if it grows past, extract the checkbox into a small `_RowCheckbox` widget.

### Tests (new + extended)

- **`test/app/controllers/batch_spec_importer_test.dart` (new, ~180 LOC):** mirror `spec_importer_test.dart` harness. Cases: N files → N commits (AC-4); middle file fails → skip + report, 2 converted (AC-6); cancel after 1 → `cancelled:true`, 1 converted, 2 not run (AC-7); two same-slug sources → distinct jobIds with a `FakeGitPort` that does **not** write to the FS (AC-8); signed-out → 0 commits + failure summary (AC-10); progress sequence `done` = 1..n observed via state stream (AC-5); invalidation invoked on finish (AC-9 — assert via a spy provider or a re-read of an invalidatable).
- **`test/app/controllers/repo_selection_controller_test.dart` (new, ~60 LOC):** toggle add/remove; selectAll union; deselectAll difference; clear; isSelected (AC-2/3).
- **`test/ui/screens/repo_browser/repo_browser_batch_test.dart` (new, ~120 LOC):** `pumpWidget` the browser with a fake dir listing containing a `.md`, a `.pdf`, a `.svg`, and a folder → checkbox present on md/pdf only (AC-1); tapping a checkbox updates the "N selected" bar; "Convert N selected" drives the batch and a determinate bar appears (AC-5/11); single "Convert to spec" button still present + still pops (AC-12).
- **`test/app/controllers/spec_importer_test.dart` (extend):** add a `reservedJobIds` case — a base whose slug is in the reserved set resolves to `-2` even when disk is empty (AC-8); confirm existing tests still pass with the defaulted param (AC-12).

## 10. Risk / Failure Modes

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| In-batch same-slug files clobber each other (second overwrites first) because the disk probe can't see uncommitted-to-workdir specs | Med | High | AC-8 `reservedJobIds` reservation; dedicated test with a `FakeGitPort` that does not touch the FS |
| Batch aborts on first failure instead of skipping (wrong model) | Med | High | AC-6 explicit; loop catches per file and continues; test seeds a mid-list failure |
| Cancel corrupts the sidecar by interrupting a commit | Low | High | Hard NO (no mid-commit cancel); cancel checked only between files (OQ-3); AC-7 |
| Selection silently cleared on folder navigation, surprising the user mid-multi-folder select | Med | Med | Selection notifier not cleared on `enter`/`up` (OQ-1); AC-2 test navigates and re-checks |
| Single-convert regression (pop-on-success or message changes) | Low | High | AC-12; `reservedJobIds` defaults to `const {}`; existing `spec_importer_test.dart` stays green; §8a limits the importer diff |
| Whole list rebuilds on every checkbox toggle → jank on large dirs | Med | Low | `ref.watch(...select((s) => s.contains(relPath)))` narrows rebuilds to the toggled row; note in §9 |
| Batch runs while a single import is in flight (double writer to `claude-jobs`) | Low | Med | AC-11 mutual exclusion: `disabled` flag disables single-convert during batch and `_running` guards batch; single-import `state.isLoading` already guards its side |
| `jobListControllerProvider`/`pendingPushCountProvider` not invalidated → new specs invisible until manual refresh | Low | Med | AC-9; invalidation in the controller's terminal branch, mirroring `job_list_screen.dart:549-550` |
| New widget file pushes `repo_browser_screen.dart` further past the 200-line limit | Low | Low | §8a: action bar + progress bar in a new sibling file; screen file gains only checkbox + wiring |
| Progress bar `value: done/total` divides by zero on empty selection | Low | Low | `run` early-returns on empty selection; `BatchRunning` only exists with `total ≥ 1` |

## 11. Rollback / Revert Plan

1. Identify the commits: `git log --oneline --grep="spec-005"` (and/or `-- docs/todos/spec-005-batch-convert-to-spec.md`).
2. Revert the series: `git revert <first>..<last>` (or `git revert -m 1 <merge-sha>` if squashed/merged).
3. Rebuild: `fvm flutter clean && fvm flutter pub get && fvm flutter build apk --flavor dev`.
4. Verify revert took: `fvm flutter test test/app/controllers/spec_importer_test.dart` green (original assertions), and on the tablet the repo browser shows **no** checkboxes / no "Convert N selected" bar — only the per-row "Convert to spec" button, which still converts + pops (pre-spec-005 behavior).
5. State-dependent fork: if `reservedJobIds` was already relied on by any later change, keep the `spec_importer.dart` signature (harmless defaulted param) and revert only the batch controller / selection controller / UI additions. Spell out kept-vs-dropped paths in the revert message.
6. Notify: one-line note in `docs/Issues.md` with the revert SHA and the failure reason.

## 12. Verification + Definition of Done

### 12a. Automated verification

```sh
# Lint clean
fvm flutter analyze

# Full suite green (host VM — no device needed for these)
fvm flutter test

# Targeted new/extended tests
fvm flutter test test/app/controllers/batch_spec_importer_test.dart
fvm flutter test test/app/controllers/repo_selection_controller_test.dart
fvm flutter test test/ui/screens/repo_browser/repo_browser_batch_test.dart
fvm flutter test test/app/controllers/spec_importer_test.dart   # AC-12: still green

# Hard NO — the shared importer diff is minimal (signature + collision only)
git diff lib/app/controllers/spec_importer.dart \
  | grep -E '^\+' | grep -E "branch: 'claude-jobs'|Import \$normalized as" \
  && echo "REVIEW: importer commit line changed — confirm intentional" || true
```

### 12b. Manual QA cases (MANDATORY)

Per `feedback_milestone_qa_loop`: domain/controller first, then on-device UI. No web frontend → Chrome DevTools `N/A`; no third-party operator step → Operator `N/A`.

#### Backend / Domain (host)
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| BE-1 | N files → N commits | `fvm flutter test test/app/controllers/batch_spec_importer_test.dart --name 'converts all selected'` | Green; `FakeGitPort` records N commits, messages `Import <path> as <jobId>` | Pass |
| BE-2 | Skip-and-report on failure | `--name 'skips a failing file'` | Green; 2 converted, 1 `BatchFailure`; no early abort | Pass |
| BE-3 | Cancel after first | `--name 'cancel stops after in-flight file'` | Green; `cancelled:true`, 1 converted, 2 not run | Pass |
| BE-4 | In-batch slug reservation | `--name 'same-slug sources get distinct jobIds'` | Green; jobIds `spec-notes`, `spec-notes-2` with an FS-blind fake commit | Pass |
| BE-5 | Auth gate | `--name 'signed out does nothing'` | Green; zero commits; all-failed summary | Pass |
| BE-6 | Selection controller | `fvm flutter test test/app/controllers/repo_selection_controller_test.dart` | Green; toggle/selectAll/deselectAll/clear behave | Pass |
| BE-7 | Single-convert unchanged | `fvm flutter test test/app/controllers/spec_importer_test.dart` | All pre-existing tests green with defaulted `reservedJobIds` | Pass |

#### Frontend / UI (on-device, OnePlus Pad Go 2 / device `NBB6BMB6QGQWLFV4`, landscape)
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| FE-1 | Checkboxes on convertible rows only | Open New spec → browser into a folder with `.md`, `.pdf`, `.svg`, and a subfolder | Checkbox on `.md`/`.pdf` rows; none on `.svg` or the folder row | Not Run |
| FE-2 | Multi-select + count | Tick 3 files | Action bar shows "3 selected" + "Convert 3 selected" | Not Run |
| FE-3 | Select all / clear | Tap "Select all"; tap again | First ticks all convertible in the dir; second unticks all | Not Run |
| FE-4 | Selection persists across folders | Tick 2 in folder A, go Up, into folder B, tick 1 | Count reads "3 selected"; convert produces 3 specs from both folders | Not Run |
| FE-5 | Batch convert + progress | Tap "Convert 3 selected" | Determinate bar advances 1/3 → 2/3 → 3/3 with current filename; rows/nav disabled during run | Not Run |
| FE-6 | Summary + list update | After FE-5, close browser | SnackBar "Converted 3, 0 failed"; JobList shows 3 new spec rows; unpushed badge +3 | Not Run |
| FE-7 | Partial failure | Select two source files whose names slugify identically **plus** a valid one, or an unreadable file; convert | Bar completes; summary "Converted X, 1 failed"; valid specs present; no crash | Not Run |
| FE-8 | Cancel mid-batch | Select 4; convert; tap Cancel after the first bar tick | Batch stops; summary notes cancel; only already-committed specs exist | Not Run |
| FE-9 | Single-convert regression | Tap a single row's "Convert to spec" button (no checkboxes) | Converts + browser pops on success, exactly as before | Not Run |
| FE-10 | Signed-out guard | Sign out (or dev build without auth); attempt a batch | No commits; failure summary prompting sign-in | Not Run |

#### Chrome DevTools / extension verification
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| CHROME-1 | N/A — no web frontend | — | N/A — Flutter Android app; no DevTools surface | N/A |

#### Operator-executed (post-cutover)
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| OP-1 | N/A — no external/operator step | — | N/A — no API keys, partner config, or migration | N/A |

### 12c. Definition of Done

- [ ] AC-1 through AC-12 satisfied.
- [ ] §12a all commands pass locally.
- [ ] BE-1 through BE-7 in §12b have Status `Pass`.
- [ ] FE-1 through FE-10 in §12b have Status `Pass` on OnePlus Pad Go 2 (device `NBB6BMB6QGQWLFV4`).
- [ ] No `<INPUT_REQUIRED>` remains in §5 (OQ-1/2/3 resolved during pre-flight / QA).
- [ ] §8a Hard NO list respected — `spec_importer.dart` diff limited to the signature + collision resolver; no `main` writes; no deletions.
- [ ] §11 Rollback plan rehearsed mentally; revert verifiable.
- [ ] Mediums/Lows surfaced during QA filed under `docs/Issues.md` with severity + screen/area + proposed fix.
- [ ] Per `feedback_git_workflow`: every logical chunk committed on the current branch; user handles all pushes.

---

End of Task Packet — `spec-005`
