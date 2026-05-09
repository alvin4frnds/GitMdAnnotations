# spec-004: Render markdown images end-to-end (spec reader, review pane, annotation canvas)

**Slug:** `md-images-render-everywhere`  **Status:** Draft  **Authored:** 2026-05-09

> Spec-002 Milestone A landed `imageBuilder` wiring at all three markdown call sites
> (`Markdown(...)` in the spec reader and `MarkdownBody(...)` in the annotation canvas + review
> pane, both routed through `resolveInlineImage`). User reports images still don't render in
> the annotation/review surfaces, and HTTPS image links never work anywhere. This spec closes
> both gaps end-to-end across the three views.

---

## 1. Context

`![](…)` references in `.md` files don't visibly render in two of the three surfaces a reviewer uses, and HTTPS URLs don't work in any of them.

Code-side wiring of `sizedImageBuilder → resolveInlineImage` is already in place at all three call sites:

- Spec reader: `lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart:1031-1041` (`Markdown(...)`).
- Annotation canvas: `lib/ui/screens/annotation_canvas/markdown_stub.dart:62-77` (`MarkdownBody(shrinkWrap: true)`), itself mounted under `lib/ui/screens/annotation_canvas/main_content.dart:204` inside a `RepaintBoundary` + `Positioned.fill InkOverlay`.
- Review pane: `lib/ui/screens/review_panel/markdown_pane.dart:50-77` re-uses `MarkdownStub`.

`flutter_markdown 0.7.7+1` (`pubspec.yaml:44`) fires `sizedImageBuilder` for every image (verified at `~/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_markdown-0.7.7+1/lib/src/builder.dart:683-686`). The existing `test/ui/screens/spec_reader_md/md_image_resolver_test.dart` passes with 9/9. So the seam is wired and the unit-level resolver works in isolation.

Two distinct gaps explain the user-reported failure (interview-confirmed: HTTPS links + relative paths, with images alongside the spec):

- **Gap A — `MarkdownBody(shrinkWrap: true)` + intrinsic-size async image inside `CanonicalPage`.** `Image.file` and `SvgPicture.file` (returned by `resolveInlineImage` at `lib/ui/screens/spec_reader_md/md_image_resolver.dart:46-56`) have no explicit width/height. Inside the annotation canvas / review pane, the markdown lays out at `kAnnotatedContentWidth = 900` (`lib/ui/screens/annotation_canvas/main_content.dart:38`) under `MarkdownBody(shrinkWrap: true)` → image height is zero until the file decode finishes, and on dark-themed surfaces the unsupported-card fallback (also returned by the resolver on missing files at `md_image_resolver.dart:48-49`) is faint enough to read as "no image" rather than "image failed to load."
- **Gap B — HTTPS URIs are explicitly refused** at `lib/ui/screens/spec_reader_md/md_image_resolver.dart:36, 75`. README-style references like `![](https://github.com/foo/bar/raw/main/diagram.png)` always render the muted "remote URL" placeholder.

Existing patterns to mirror exactly:

- `_MmdReference` `ConsumerStatefulWidget` (`md_image_resolver.dart:117-166`) — async-load-then-render with stable-height placeholder. The new HTTPS branch must follow this shape, not invent a new one.
- `MermaidCache` (`lib/domain/services/mermaid_cache.dart`) — SHA-256-keyed on-disk cache under app docs. The new `NetworkImageCache` should mirror its directory layout (`<appDocs>/image-cache/<sha>.<ext>`).
- `feedback_milestone_qa_loop` — milestone-level QA + triage before close-out; defer Medium/Low to `docs/Issues.md`.

User-confirmed scope from the pre-spec interview:

- Image link types in scope: HTTPS URLs **and** relative file paths.
- Image-on-disk location in scope: same folder as the `.md`.

## 2. Objective

After this ships, every `![](…)` reference in any `.md` opened on the tablet renders end-to-end across spec reader, annotation canvas, and review pane — for both relative on-disk paths and HTTPS URLs. The annotation canvas's submit-time PDF raster (`03-annotations.pdf`) captures the rendered images. Offline opens render text + relative-path images normally and degrade HTTPS images to a loud "fetch failed" card without crashing.

## 3. Assumptions

- `flutter_markdown 0.7.7+1`'s `sizedImageBuilder` is the only image-routing seam in use; `MarkdownBuilder._buildImage` (`pub.dev/flutter_markdown-0.7.7+1/lib/src/builder.dart:683-699`) fires it for every `![](…)` regardless of widget host (`Markdown` vs `MarkdownBody`).
- `dio: ^5.7.0` (`pubspec.yaml:37`) is the project's HTTP client; no new HTTP dep is needed.
- `crypto: ^3.0.5` (`pubspec.yaml:77`) is already pulled in for SHA-256 — re-use for the cache key.
- `path_provider: ^2.1.5` (`pubspec.yaml:40`) supplies `getApplicationDocumentsDirectory()` for the cache root.
- Public HTTPS URLs only for v1 (no auth, no GitHub PAT pass-through). User confirmed README-style links are the primary case.
- The tablet has network on first online open; subsequent offline opens read the on-disk cache.
- `FileSystemPort` exposes a binary-write method (`writeBytes` or equivalent). `<INPUT_REQUIRED>` if it doesn't — see §5.

## 4. Out of Scope

- **Authed HTTPS fetches** (GitHub PAT, OAuth bearer). v1 is public-anonymous. Reason: 90% of README-style links in real specs hit `github.com/.../raw/...` paths, which are public. Authed fetch is its own spec with token-handling implications.
- **Cache eviction UI.** v1 grows unbounded under `<appDocs>/image-cache/`. A "Clear image cache" Settings button is its own follow-up. Reason: typical image budget is ~250 MB for 1,000 images; bearable for the device class.
- **`data:image/png;base64,…` URIs.** Inline data URIs are technically valid markdown but rare in spec docs. Reason: the resolver's `else` branch already produces an unsupported card; revisit if a real spec uses one.
- **`![](foo.png#100x50)` dimension syntax.** `flutter_markdown` parses these into `MarkdownImageConfig.width/height` (`builder.dart:668-674`); the resolver currently ignores them. Reason: no spec in the repo uses the syntax today; adding support is a one-line follow-up if needed.
- **Eager prefetch / `<link rel=preload>` semantics.** Images mount on first paint of the markdown subtree and fetch lazily. Reason: a `MarkdownBody(shrinkWrap: true)` doesn't virtualize, so all 10–30 inline images mount at once already; eager prefetch adds no value.
- **Editor-mode (split / edit) preview** of newly added image references — out of scope for this spec; the existing `_MarkdownLivePreview` already routes through the same resolver and will benefit for free, but is not a verification target here.

## 5. Open Questions / `<INPUT_REQUIRED>`

- **Width clamp number.** Spec proposes a single `maxWidth: 880` clamp (canonical content width 900 minus padding) across all three surfaces. Spec reader has 32-px horizontal padding; canvas/review have 48-px. If on-device QA shows a giant image looks squished or off-center on the spec reader, revisit per-surface clamps. **Who can answer:** user, after Milestone-A on-device QA.
- **HTTP (cleartext) policy.** Android `targetSdk ≥ 28` blocks cleartext HTTP by default via `network-security-config`. Spec treats `http://` identically to `https://`; if a real spec references a cleartext URL, it'll fail at the platform layer with `CleartextNotPermittedException`. Document the failure mode rather than relax the security config. **Who can answer:** user, but no action needed unless a real spec hits this.
- **`FileSystemPort.writeBytes` existence.** Spec assumes a binary-write method on the port. If only `writeString` exists today (`lib/domain/ports/file_system_port.dart`), the implementer adds `Future<void> writeBytes(String path, Uint8List bytes)`, mirroring in `FakeFileSystem` + `DartIoFileSystem`. **Who can answer:** implementer at pre-flight (§6) by reading the port file.
- **In-flight fetch memoization scope.** Spec proposes per-instance memoization inside `NetworkImageCache` (a `Map<String, Future<String>>` keyed on SHA, cleared on completion) so two concurrent `_NetworkImage` widgets for the same URL share one fetch. If `networkImageCacheProvider` is `autoDispose`, the memoization map dies between screen mounts — acceptable. If it's a singleton, the map needs a TTL or size cap. **Who can answer:** implementer at provider-wiring time, default to non-autoDispose so the in-flight cache survives screen re-mount.
- **Cache directory naming.** Spec proposes `<appDocs>/image-cache/`. `MermaidCache` uses `<appDocs>/mermaid-cache/`. Confirm naming consistency rather than picking ad hoc. **Who can answer:** implementer; default is `image-cache` to match the dash-separated MermaidCache convention.

## 6. Pre-flight Checklist

Required skills (per spec-writer skill matrix):

- [ ] Required skill loaded: **`clean-code`** — Always.
- [ ] Required skill loaded: **`test-driven-development`** — Behavior change with new ACs covering both new code (`NetworkImageCache`) and existing code (`resolveInlineImage` HTTPS branch).
- [ ] Required skill loaded: **`prod-safety-gate`** — Touches the spec-rendering path that ships in every build; a regression silently breaks every spec view.
- [ ] Required skill loaded: **`vibesec`** — Introduces an outbound HTTPS fetch with user-supplied URLs (markdown image links). URL handling, response-size policy, and error-surface logging are vibesec-relevant. Public-only by policy, but auth headers must never appear.

Environment / state:

- [ ] Working tree clean; on a feature branch off `main`.
- [ ] `fvm flutter pub get` clean (libgit2dart fork resolves; mbedTLS bundle path unchanged).
- [ ] `fvm flutter analyze` baseline green before first commit.
- [ ] `fvm flutter test` baseline green (full suite) before first commit.
- [ ] OnePlus Pad Go 2 reachable: `adb -s NBB6BMB6QGQWLFV4 shell getprop ro.product.model` returns the device model.

Read-before-write (each before editing):

- [ ] `lib/ui/screens/spec_reader_md/md_image_resolver.dart:1-233` — entire file; the resolver is small and the `_MmdReference` pattern at lines 117-166 must be mirrored verbatim by the new `_NetworkImage`.
- [ ] `lib/domain/ports/file_system_port.dart` — confirm `writeBytes` (or add it; see §5).
- [ ] `lib/domain/services/mermaid_cache.dart` — full file; new `NetworkImageCache` mirrors its disk-cache shape and provider plumbing.
- [ ] `lib/ui/screens/annotation_canvas/main_content.dart:38-46, 152-231` — canonical width / padding / RepaintBoundary chain that constrains how the resolver's output must size itself.
- [ ] `pub.dev/flutter_markdown-0.7.7+1/lib/src/builder.dart:659-700` — confirms `sizedImageBuilder` is the single seam.
- [ ] `docs/Issues.md:7-13` (MermaidView duplicate-WebView pattern) — same memoize-by-SHA mistake to avoid.

Re-read each AC; understand which are unit / widget / on-device.

## 7. Acceptance Criteria

- **AC-1 — Relative file image renders in spec reader.** Open a `.md` whose body is `![local](diagram.png)` with `diagram.png` next to the file. The spec-reader view (`SpecReaderMdScreen` preview mode) renders the PNG at intrinsic size, clamped to `maxWidth: 880` logical px.
- **AC-2 — Relative file image renders in annotation canvas.** Same `.md` opened via Annotate from the spec reader. The PNG appears at the same canonical-coord position (no stroke-anchor drift); the user can draw a stylus stroke over the image and the stroke paints visibly on top.
- **AC-3 — Relative file image renders in review pane.** Same `.md` reached via Review panel. The PNG appears at the same position; previously committed strokes (if any) replay over the top of the image without offset.
- **AC-4 — Relative SVG image renders in all three views.** Replace `diagram.png` with a `shape.svg` next to the spec; all three surfaces render the SVG via `flutter_svg`.
- **AC-5 — HTTPS image renders after first fetch (online).** A spec containing `![remote](https://<public-png-url>)` renders the image in all three views within ~3 s on the wired tablet. Bytes are persisted under `<appDocs>/image-cache/<sha>.png` (or `.bin` if no extension).
- **AC-6 — HTTPS image renders from cache (offline).** Toggle airplane mode ON, force-quit, re-open the same job. The HTTPS image renders from cache without a network call.
- **AC-7 — HTTPS image with no cache + no network surfaces a loud error card.** Toggle airplane mode ON, delete `<appDocs>/image-cache/`, re-open. The "fetch failed" card appears with the URL host visible; the spec text + relative-path images still render; no crash; no UI freeze.
- **AC-8 — Concurrent fetches for the same URL share one in-flight future.** Mount two `_NetworkImage` widgets for the same URL in a widget test with a counting fake fetcher; assert the fetcher was invoked exactly once.
- **AC-9 — Annotation PDF raster captures rendered images.** Submit Review on a job whose spec contains rendered images; the resulting `03-annotations.pdf` (captured from `markdownRasterBoundaryKeyProvider`'s RepaintBoundary) embeds the image bytes in the page raster.
- **AC-10 — Existing spec-002 image resolver tests still pass.** `fvm flutter test test/ui/screens/spec_reader_md/md_image_resolver_test.dart` reports 9/9 (or 9 + N new) green.
- **AC-11 — vibesec: no auth headers, no URL token leakage in UI.** `dio.get(url, options: Options(responseType: ResponseType.bytes, headers: const {}, followRedirects: true, maxRedirects: 3))`. Error UI shows `uri.host` only, never the full URL with query string (which could carry an access token in a redirect-token URL).

## 8. Implementation Guardrails

### 8a. Hard NO list

- **Do not wrap resolver outputs in `GestureDetector` / `InkWell` / any pointer-listener.** The annotation canvas places `Positioned.fill InkOverlay` over the markdown subtree with `HitTestBehavior.opaque`. A gesture detector inside the resolver would steal stylus events from the overlay — the user would be unable to draw over an image. Verify with `git diff lib/ui/screens/spec_reader_md/md_image_resolver.dart | grep -E '(GestureDetector|InkWell|Listener)'` returning empty.
- **Do not change `kAnnotatedContentWidth` (`= 900`)** at `lib/ui/screens/annotation_canvas/main_content.dart:38`. Stroke-coordinate-space invariant; existing `03-annotations.svg` files captured at the old width would replay at a visually scaled offset.
- **Do not add a network call into the synchronous markdown render path.** The `Markdown` build must complete without awaiting a Future; the only async work happens inside the resolver's stateful widgets (`_NetworkImage`, mirroring `_MmdReference`).
- **Do not break `test/ui/screens/spec_reader_md/md_image_resolver_test.dart`.** Existing 9 tests are the contract for the file/svg/mmd/unsupported branches. Extend, don't replace.
- **Do not log image bytes, full URL with query string, or response headers.** vibesec: any debug `print` / log line in `NetworkImageCache` or `DioImageFetcher` shows `uri.scheme + uri.host + uri.path` only — never `uri.toString()` (would leak query params).
- **Do not couple the resolver to Riverpod via a top-level `ProviderScope.containerOf(context)`** lookup. The resolver is invoked from `flutter_markdown`'s builder which has a normal `BuildContext`; the existing pattern is `ConsumerStatefulWidget` with `ref.read(...)` inside `initState`. Mirror it.

### 8b. Coding / quality principles

- **`clean-code`** — short methods (≤ 50 LOC each); domain-named widgets/services (`NetworkImageCache`, `_NetworkImage`, `ImageFetcher`); no `utils/`, `helpers/`, or `common/` folders or class names. Early-return on cache hit / on `uri.scheme == 'http'/'https'` rather than nesting.
- **`prod-safety-gate`** — the spec-rendering path ships in every build. Production miswiring would silently break image rendering for every spec on every device. Mitigations: AC-10 (existing tests stay green); §10 risk row (resolver crash short-circuits markdown render); §11 step 4 (rollback verification curl).
- **`vibesec`** — surfaces are the HTTPS fetcher (outbound network), the cache file write (path traversal? no — SHA is hex, no slashes), and the error UI (URL leakage). Mitigations: explicit `headers: const {}`, `maxRedirects: 3`, `responseType: bytes`, fixed cache filename `<sha-hex>.<sanitized-ext>` where ext is `[a-zA-Z0-9]{1,5}` from the URL path or `bin`. URL host-only in error UI per AC-11.
- **`test-driven-development`** — write `test/domain/services/network_image_cache_test.dart` with all 5 cases (first call fetches, second hits cache, concurrent share, fetch error, missing extension) **before** implementing `NetworkImageCache`. Verify red, then green. Same red-then-green for the layout test (§7 AC-2 / AC-3) before adding `frameBuilder` to the resolver.
- **Mirror existing patterns by `path:line`:**
  - Async-load-then-render: `lib/ui/screens/spec_reader_md/md_image_resolver.dart:117-166` (`_MmdReference`).
  - Domain disk-cache: `lib/domain/services/mermaid_cache.dart` (whole file).
  - Composition-root provider wiring: `lib/bootstrap.dart` real-mode overrides (search for `mermaidCacheProvider`).

## 9. Behavior Spec (per file)

### `lib/ui/screens/spec_reader_md/md_image_resolver.dart`

- **Current state (lines 27-69, 117-166, 200-233):** dispatches by extension; file branches return naked `Image.file` / `SvgPicture.file` with no width clamp and no skeleton placeholder; HTTPS rejected at line 36/75; `_MmdReference` is the existing async-pattern reference.
- **Required edit:**
  - Replace HTTPS-rejection (line 75 `if (uri.scheme == 'http' || uri.scheme == 'https') return null;`) with a path that returns a new `_NetworkImage(url: uri, alt: alt)` widget.
  - Wrap `Image.file` (line 46) in a `ConstrainedBox(maxWidth: 880)` and pass `frameBuilder: (ctx, child, frame, _) => frame == null ? _skeletonCard(ctx, alt: alt) : child`.
  - Wrap `SvgPicture.file` (line 52) in the same `ConstrainedBox(maxWidth: 880)`; replace its existing `placeholderBuilder` (24px LinearProgressIndicator) with `_skeletonCard(ctx, alt: alt)`.
  - Replace `_unsupportedCard` content for `errorBuilder` (line 48) with a louder variant that includes `Icons.broken_image_outlined` + alt + the resolved abs path.
  - Add `class _NetworkImage extends ConsumerStatefulWidget` mirroring `_MmdReference`: `initState` calls `ref.read(networkImageCacheProvider).resolve(widget.url)` returning `Future<String>`; build returns `FutureBuilder<String>` → skeleton while pending → `Image.file(File(path), frameBuilder: …)` on done → loud error card on error.
- **Estimated diff:** ~80 LOC (40 added for `_NetworkImage`, 20 for skeleton/loud-error cards, 20 for frame/clamp wraps).
- **Subtleties:** the resolver is invoked from `flutter_markdown`'s `_buildImage` once per image; do not memoize widgets inside the resolver (Flutter rebuilds at the parent level). Memoization belongs in `NetworkImageCache`. Skeleton-card height must be tall enough (≥ 120 px) that `MarkdownBody`'s shrink-wrap doesn't collapse the row; tested in §7 AC-1/AC-2/AC-3.

### `lib/domain/services/network_image_cache.dart` (new)

- **Required edit:** new file. `class NetworkImageCache { NetworkImageCache({required FileSystemPort fs, required ImageFetcher fetch, required String cacheDir}); Future<String> resolve(Uri url); }` — SHA-256 of `url.toString()` is the cache key. Cache hit → return path immediately. Cache miss → check in-flight `Map<String, Future<String>>` keyed by SHA; if present, return the same future; else, kick off fetch + write + clean up the map entry on completion. Concurrent slot count via a 4-permit semaphore (`Queue<Completer<void>>` pattern). Errors throw typed `NetworkImageFetchFailed(uri, cause)`.
- **Estimated diff:** ~120 LOC.
- **Subtleties:** filename extension comes from `url.path`'s last `.` segment, sanitized to `[a-zA-Z0-9]{1,5}` or `bin`. SHA from `crypto: ^3.0.5`'s `sha256.convert(utf8.encode(url.toString()))`. The semaphore prevents OkHttp pool saturation on image-heavy specs (`docs/Issues.md` already calls this pattern out as deferred for MermaidView; do it right here so that follow-up gets a free pattern).

### `lib/domain/ports/image_fetcher_port.dart` (new)

- **Required edit:** new file. `abstract class ImageFetcher { Future<Uint8List> fetch(Uri url); }`.
- **Estimated diff:** ~10 LOC.
- **Subtleties:** none. Single-method port; implementations live in `lib/infra/net/` (real) and inline in tests (fake).

### `lib/infra/net/dio_image_fetcher.dart` (new)

- **Required edit:** new file. `class DioImageFetcher implements ImageFetcher { DioImageFetcher(this._dio); Future<Uint8List> fetch(Uri url) => _dio.get<Uint8List>(url.toString(), options: Options(responseType: ResponseType.bytes, headers: const {}, followRedirects: true, maxRedirects: 3, sendTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15))).then((r) => Uint8List.fromList(r.data!)); }`. Wraps `DioException` into `NetworkImageFetchFailed`.
- **Estimated diff:** ~40 LOC (incl. exception mapping).
- **Subtleties:** dio is already a dep at `pubspec.yaml:37`; no new package. CA bundle: dio uses Dart's `HttpClient` → Android system trust store; unrelated to the libgit2/mbedTLS asset path.

### `lib/domain/ports/file_system_port.dart`

- **Current state:** unknown until implementer reads it (`<INPUT_REQUIRED>` per §5).
- **Required edit:** if `writeBytes(String path, Uint8List bytes)` exists, no change; else add it. Mirror in `lib/domain/fakes/fake_file_system.dart` and `lib/infra/fs/dart_io_file_system.dart`.
- **Estimated diff:** 0 if exists, ~30 LOC across port + 2 implementations if not.
- **Subtleties:** Spec-001 already added `commit(removals: …)` via the same port-extend pattern; mirror that.

### `lib/app/providers/image_cache_providers.dart` (new)

- **Required edit:** new file. `final imageFetcherProvider = Provider<ImageFetcher>((ref) => throw UnimplementedError());` (overridden in `bootstrap.dart`); `final networkImageCacheProvider = Provider<NetworkImageCache>((ref) => NetworkImageCache(fs: ref.read(fileSystemProvider), fetch: ref.read(imageFetcherProvider), cacheDir: ref.read(_imageCacheDirProvider)));` plus a `_imageCacheDirProvider` that resolves to `'${getApplicationDocumentsDirectory()}/image-cache'` synchronously via a startup-cached path (mirror MermaidCache's pattern).
- **Estimated diff:** ~40 LOC.
- **Subtleties:** non-autoDispose Provider so the in-flight memoization map survives screen re-mount. Overrides happen in `bootstrap.dart`.

### `lib/bootstrap.dart`

- **Current state (around the existing `mermaidCacheProvider` override):** wires real adapters in `APP_MODE=real`, fakes in mockup mode.
- **Required edit:** add `imageFetcherProvider.overrideWithValue(DioImageFetcher(Dio()))` to real overrides; add a `FakeImageFetcher` (returns 1×1 transparent PNG bytes by default; tests override per-fixture) to mockup overrides.
- **Estimated diff:** ~20 LOC.
- **Subtleties:** the `Dio()` instance is short-lived and unscoped; if other parts of the app already share a Dio (auth?), reuse that instance. Search for `Dio()` constructions in `lib/` first.

## 10. Risk / Failure Modes

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| `frameBuilder` skeleton card height (180 px) feels too tall on small images | Med | Low | AC-1/AC-2/AC-3 visual check on tablet; per-surface QA finding goes to `docs/Issues.md` Medium with a tighter clamp suggestion |
| Stylus event arena change accidentally absorbs strokes over images | Low | High | Hard NO #1 (no GestureDetector); AC-2 manual stroke-over-image test; integration regression in `docs/MANUAL_TESTCASES.md` |
| HTTPS fetcher blocks on slow/dead URL → markdown render hangs | Low | High | 10 s send / 15 s receive timeouts in DioImageFetcher; render path is sync, only the FutureBuilder waits — markdown text is visible immediately |
| Cache directory grows unbounded → device storage pressure | Med | Med | §4 calls out as out-of-scope follow-up; AC-7 path leaves cache intact even on failure (no thrash); document in Issues.md if QA shows >100 MB after typical use |
| `flutter_markdown` upgrade swaps `sizedImageBuilder` deprecation → silent no-image | Low | High | AC-10 keeps the resolver test green; pin `flutter_markdown ^0.7.4` in pubspec until a deliberate upgrade spec |
| URL with query string leaked into error UI / logs | Low | Med | vibesec guardrail: error card uses `uri.host` only; no `print(uri.toString())` anywhere; verified by grep in §12a |
| Concurrent in-flight fetches saturate Android OkHttp pool | Low | Med | 4-permit semaphore in `NetworkImageCache`; AC-8 covers in-flight share; defer adaptive concurrency to a follow-up |
| `MarkdownBody.shrinkWrap` collapses on a transient skeleton-card height-zero state | Med | Med | Pin skeleton height ≥ 120 px; AC-1/AC-2/AC-3 widget tests assert non-zero height |
| `writeBytes` missing on FileSystemPort → port-shape change ripples to other adapters | Low | Low | §5 open question; pre-flight (§6) reads the port; implementer extends with `Future<void> writeBytes(...)` if absent (mirroring spec-001's pattern) |
| Submit-review PDF raster doesn't capture network images that fetched after the boundary read | Low | Med | AC-9 explicit on-device; if regression, pre-load images by triggering a 1-frame settle before `RepaintBoundary.toImage` (deferred to a fix-up) |

## 11. Rollback / Revert Plan

1. Identify the merge commit: `git log --oneline --grep="spec-004" -- docs/todos/spec-004-md-images-render-everywhere.md`.
2. Revert: `git revert -m 1 <sha>` (or for a series of commits, `git revert <first>..<last>`).
3. Rebuild: `fvm flutter clean && fvm flutter pub get && fvm flutter build apk --flavor dev`.
4. Verify revert took: `fvm flutter test test/ui/screens/spec_reader_md/md_image_resolver_test.dart` — should still be 9/9 green (the original assertion set). Open a `.md` with an HTTPS image on the tablet; confirm the "remote URL" placeholder reappears (i.e. pre-spec-004 behavior restored).
5. Optional cleanup: `adb -s NBB6BMB6QGQWLFV4 shell rm -rf /data/data/<app-id>/files/image-cache` to drop the now-orphaned cache directory. Skip if disk space isn't tight; the next install will overwrite.
6. Notify: drop a one-line note in `feedback_milestone_qa_loop` log / Issues.md with the revert SHA and the failure reason that triggered it.

If the revert fork is state-dependent (e.g., `writeBytes` was added to `FileSystemPort` and other code already consumes it), rebase the revert: keep the port surface, drop only the resolver/cache/fetcher additions. Spell out the kept-vs-dropped paths in the revert commit message.

## 12. Verification + Definition of Done

### 12a. Automated verification

```sh
# Lint clean
fvm flutter analyze

# Full test suite green
fvm flutter test

# Targeted: existing image resolver tests stay green (AC-10)
fvm flutter test test/ui/screens/spec_reader_md/md_image_resolver_test.dart

# Targeted: new domain test (AC-8 + cache mechanics)
fvm flutter test test/domain/services/network_image_cache_test.dart

# Targeted: new layout tests across all three surfaces (AC-1/AC-2/AC-3)
fvm flutter test test/ui/screens/spec_reader_md/md_image_layout_test.dart
fvm flutter test test/ui/screens/annotation_canvas/markdown_stub_image_render_test.dart

# Hard NO #1 — no GestureDetector / InkWell / Listener in the resolver
git diff lib/ui/screens/spec_reader_md/md_image_resolver.dart \
  | grep -E '\+(GestureDetector|InkWell|^\+\s*Listener\()' && exit 1 || true

# vibesec — no `uri.toString()` in the resolver / cache / fetcher
grep -rn 'uri.toString()' lib/ui/screens/spec_reader_md/md_image_resolver.dart \
  lib/domain/services/network_image_cache.dart \
  lib/infra/net/dio_image_fetcher.dart && exit 1 || true
```

### 12b. Manual QA cases (MANDATORY)

Per `feedback_milestone_qa_loop`: BE/domain first, then UI surfaces. This project has no web frontend, so Chrome DevTools is `N/A`; no third-party operator config either, so Operator is `N/A`.

#### Backend / Domain
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| BE-1 | Cache hit short-circuits fetcher | Run `fvm flutter test test/domain/services/network_image_cache_test.dart --name 'second call hits cache'` | Test green; counting fake fetcher invoked exactly once across two `resolve()` calls | Not Run |
| BE-2 | Concurrent fetches share future | Run `--name 'concurrent calls share in-flight future'` | Test green; fetcher invoked exactly once for two simultaneous `resolve()` calls | Not Run |
| BE-3 | Fetcher failure surfaces typed exception | Run `--name 'fetcher throws -> NetworkImageFetchFailed'` | Test green; nothing written to disk on failure | Not Run |
| BE-4 | URL without extension cached as `.bin` | Run `--name 'url without extension'` | Test green; cache file is `<sha>.bin`; `Image.file` decodes by magic bytes anyway | Not Run |
| BE-5 | Resolver tests still green | `fvm flutter test test/ui/screens/spec_reader_md/md_image_resolver_test.dart` | All 9 pre-existing + N new tests pass | Not Run |

#### Frontend / UI (on-device, OnePlus Pad Go 2 / device `NBB6BMB6QGQWLFV4`, landscape)
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| FE-1 | Spec reader renders relative PNG (AC-1) | Open job whose `02-spec.md` has `![local](diagram.png)` with the file alongside | PNG visible at intrinsic size, clamped to ≤ 880 px wide; no placeholder card visible after decode | Not Run |
| FE-2 | Annotation canvas renders the same PNG (AC-2) | From FE-1, tap **Annotate** | PNG appears at the same canonical position as the spec reader; pen-stroke over the image draws on top, not behind | Not Run |
| FE-3 | Review pane renders the same PNG (AC-3) | From FE-1, tap **Review panel** | PNG appears at the same position; any prior strokes replay over it without offset | Not Run |
| FE-4 | Relative SVG renders in all three views (AC-4) | Replace `diagram.png` with `shape.svg` next to spec; repeat FE-1–FE-3 | SVG renders identically across spec reader, canvas, review pane | Not Run |
| FE-5 | HTTPS image fetches + renders online (AC-5) | Spec contains `![remote](https://<public-png-url>)`; tablet on Wi-Fi | Image renders within ~3 s; `<appDocs>/image-cache/<sha>.png` exists after | Not Run |
| FE-6 | HTTPS image renders from cache offline (AC-6) | After FE-5, airplane mode ON, force-quit, re-open job | Image renders from cache without network; no spinner persists | Not Run |
| FE-7 | HTTPS no-cache + no-network shows loud error (AC-7) | Airplane mode ON, `adb shell rm -rf .../image-cache`, re-open | Loud error card with broken-image icon + URL host; spec text + relative-path images still render; no crash; no freeze | Not Run |
| FE-8 | Submit Review PDF embeds rendered images (AC-9) | After FE-1, draw 1 stroke, Submit Review; pull `03-annotations.pdf` from the job folder | Open the PDF on host: image bytes embedded in the page raster (visually verifiable; no separate file) | Not Run |
| FE-9 | Stroke alignment unchanged | Open an existing job with prior strokes (no images); annotate / review | Strokes replay at the exact same canonical positions as before spec-004 | Not Run |
| FE-10 | Mermaid render path still works | Open a job with a ` ```mermaid ` fence | Mermaid diagram renders (regression check on the M2c path) | Not Run |

#### Chrome DevTools / extension verification
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| CHROME-1 | N/A — no web frontend | — | N/A — Flutter Android app; no DevTools surface. If a future spec adds a web build, fail and add cases. | N/A |

#### Operator-executed (post-cutover)
| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| OP-1 | N/A — no third-party / external operator step | — | N/A — no API keys, no partner config, no scheduled migration. If a future spec gates HTTPS image fetch on a config flag, fail and add cases. | N/A |

### 12c. Definition of Done

- [ ] AC-1 through AC-11 satisfied.
- [ ] §12a all commands pass locally.
- [ ] BE-1 through BE-5 in §12b have Status `Pass`.
- [ ] FE-1 through FE-10 in §12b have Status `Pass` on OnePlus Pad Go 2 (device `NBB6BMB6QGQWLFV4`).
- [ ] No `<INPUT_REQUIRED>` remains in §5 (all five resolved by implementer or user during pre-flight / QA).
- [ ] §8a Hard NO list respected — `git diff` greps in §12a return empty.
- [ ] §11 Rollback plan rehearsed mentally; revert SHA verifiable with `git revert -m 1`.
- [ ] Mediums/Lows surfaced during QA filed under `docs/Issues.md` with severity + screen/area + proposed fix.
- [ ] Per `feedback_git_workflow`: every logical chunk committed on the current branch; user handles all pushes.

---

End of spec — `spec-004-md-images-render-everywhere`
