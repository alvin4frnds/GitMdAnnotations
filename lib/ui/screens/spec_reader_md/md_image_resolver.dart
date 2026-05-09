import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/providers/image_cache_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/services/network_image_cache.dart';
import '../../theme/tokens.dart';
import '../../widgets/mermaid_view/mermaid_view.dart';

/// Maximum logical width an inline image renders at. Picked as
/// `kAnnotatedContentWidth (900) - 2 * 10` so a giant intrinsic-size
/// image cannot blow out the canonical 900-px content box on the
/// annotation canvas / review pane (which would push line wraps off the
/// stored stroke anchors). The same clamp applies on the spec reader so
/// all three surfaces render identically.
const double _kImageMaxWidth = 880;

/// Pinned skeleton-card height while bytes are decoding. Tall enough
/// (≥ 120 px per spec-004 §10) that `MarkdownBody(shrinkWrap: true)`
/// doesn't collapse the row to zero during the async decode — without
/// this the user sees nothing for the first frame on the annotation
/// canvas / review pane and reads it as "no image."
const double _kSkeletonHeight = 180;

/// Resolves a markdown `![alt](uri)` reference to a widget, used as
/// `flutter_markdown`'s `imageBuilder` callback. Pure: takes the URI +
/// the spec's on-disk path, returns a widget — no I/O unless the widget
/// itself reads (e.g. [Image.file] lazy-loads on first paint).
///
/// Dispatch:
///   * `.png` / `.jpg` / `.jpeg` / `.gif` → [Image.file]
///   * `.svg` → [SvgPicture.file] (flutter_svg)
///   * `.mmd` → placeholder card until Milestone C wires the Mermaid
///     renderer.
///   * `http` / `https` URI → fetched + cached via [NetworkImageCache],
///     rendered as a local [Image.file] once bytes land on disk.
///   * anything else → a muted "unsupported" card with the alt text.
///
/// Relative URIs resolve against [path.dirname(specPath)]; absolute
/// `file://` and filesystem paths are taken verbatim.
Widget resolveInlineImage({
  required Uri uri,
  required String specPath,
  required BuildContext context,
  String? title,
  String? alt,
}) {
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return _NetworkImage(url: uri, alt: alt);
  }
  final absPath = _resolveAbsolute(uri, specPath);
  if (absPath == null) {
    return _unsupportedCard(context, alt: alt, reason: 'unsupported scheme');
  }
  final ext = _extension(absPath);
  switch (ext) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.gif':
    case '.webp':
    case '.bmp':
      return _ClampedImageFile(absPath: absPath, alt: alt);
    case '.svg':
      return _ClampedSvgFile(absPath: absPath, alt: alt);
    case '.mmd':
      // Milestone C: read the referenced `.mmd` file and hand its source
      // to MermaidView. Stable-height placeholder during the async read
      // so scroll position doesn't jump.
      return _MmdReference(absPath: absPath, alt: alt);
    default:
      return _unsupportedCard(
        context,
        alt: alt,
        reason: 'unsupported extension: ${ext.isEmpty ? "(none)" : ext}',
      );
  }
}

/// Resolves [uri] to an absolute filesystem path using [specPath] as the
/// anchor for relative references. Callers must pre-route `http` / `https`
/// schemes through [_NetworkImage] before invoking this helper — only
/// local-filesystem URIs are handled here.
String? _resolveAbsolute(Uri uri, String specPath) {
  if (uri.scheme == 'file') return uri.toFilePath();
  if (uri.hasAbsolutePath && uri.scheme.isEmpty) {
    // URIs like '/absolute/path.png' with no scheme — treat as filesystem.
    return uri.path;
  }
  // Relative reference: join against specPath's parent directory.
  final parent = _dirname(specPath);
  final relative = uri.toString();
  // Normalize Windows path separators to forward slashes then re-split.
  return _joinPosix(parent, relative);
}

String _dirname(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash <= 0 ? normalized : normalized.substring(0, slash);
}

String _joinPosix(String parent, String child) {
  if (child.startsWith('/')) return child;
  final cleanParent = parent.endsWith('/')
      ? parent.substring(0, parent.length - 1)
      : parent;
  return '$cleanParent/$child';
}

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  if (dot <= slash || dot < 0) return '';
  return path.substring(dot).toLowerCase();
}

String _basename(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Consumes `FileSystemPort.readString(absPath)` and hands the contents
/// to [MermaidView]. Stateful wrapper so the async read happens exactly
/// once per mount and scroll-position stays stable.
class _MmdReference extends ConsumerStatefulWidget {
  const _MmdReference({required this.absPath, required this.alt});
  final String absPath;
  final String? alt;

  @override
  ConsumerState<_MmdReference> createState() => _MmdReferenceState();
}

class _MmdReferenceState extends ConsumerState<_MmdReference> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(fileSystemProvider).readString(widget.absPath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _placeholderCard(
            context,
            title: 'Reading Mermaid source…',
            body: widget.alt ?? _basename(widget.absPath),
          );
        }
        if (snap.hasError) {
          return _unsupportedCard(
            context,
            alt: widget.alt,
            reason: 'Mermaid read failed: ${snap.error}',
          );
        }
        final source = snap.data ?? '';
        if (source.trim().isEmpty) {
          return _unsupportedCard(
            context,
            alt: widget.alt,
            reason: 'Mermaid source is empty',
          );
        }
        return MermaidView(source: source);
      },
    );
  }
}

Widget _placeholderCard(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final t = context.tokens;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.surfaceSunken,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: t.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: TextStyle(color: t.textMuted, fontSize: 13)),
      ],
    ),
  );
}

Widget _unsupportedCard(
  BuildContext context, {
  String? alt,
  required String reason,
}) {
  final t = context.tokens;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: t.surfaceSunken,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: t.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          alt?.isNotEmpty == true ? alt! : '(no alt text)',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          reason,
          style: TextStyle(color: t.textMuted, fontSize: 11),
        ),
      ],
    ),
  );
}

/// Stable-height skeleton shown while [Image.file] / [SvgPicture.file] /
/// [_NetworkImage] await their bytes. Pinned to [_kSkeletonHeight] so
/// `MarkdownBody(shrinkWrap: true)` (annotation canvas + review pane)
/// doesn't collapse the row to zero during the async decode.
Widget _imageSkeletonCard(BuildContext context, {String? alt}) {
  final t = context.tokens;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    height: _kSkeletonHeight,
    decoration: BoxDecoration(
      color: t.surfaceSunken,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: t.borderSubtle),
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 28, color: t.textMuted),
        const SizedBox(height: 8),
        Text(
          'Loading image…',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (alt != null && alt.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            alt,
            style: TextStyle(color: t.textMuted, fontSize: 11),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ],
    ),
  );
}

/// Loud failure card for "image expected here but it didn't load" — the
/// resolver returned a real image branch (file path / network URL) but
/// the bytes never arrived. Visually distinguishable from
/// [_unsupportedCard] so a missing-on-disk image isn't read as
/// "deliberately omitted." [diagnostic] is a short safe-to-show string
/// (file path or `uri.host`); never the full URL with query string per
/// vibesec.
Widget _imageFailureCard(
  BuildContext context, {
  String? alt,
  required String reason,
  required String diagnostic,
}) {
  final t = context.tokens;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.surfaceSunken,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: t.statusWarning, width: 1.5),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.broken_image_outlined, size: 22, color: t.statusWarning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alt?.isNotEmpty == true ? alt! : '(no alt text)',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reason,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                diagnostic,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// File-backed raster image clamped to [_kImageMaxWidth] with a
/// stable-height skeleton placeholder while the async decode is in
/// flight. Routes loud-error path through [_imageFailureCard] so a
/// missing file is visually distinguishable from a deliberate
/// "unsupported" omission.
class _ClampedImageFile extends StatelessWidget {
  const _ClampedImageFile({required this.absPath, required this.alt});
  final String absPath;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kImageMaxWidth),
      child: Image.file(
        File(absPath),
        frameBuilder: (ctx, child, frame, _) {
          if (frame == null) return _imageSkeletonCard(ctx, alt: alt);
          return child;
        },
        errorBuilder: (ctx, _, _) => _imageFailureCard(
          ctx,
          alt: alt,
          reason: 'image not found',
          diagnostic: absPath,
        ),
      ),
    );
  }
}

/// SVG-backed image clamped to [_kImageMaxWidth] with the same
/// stable-height skeleton as [_ClampedImageFile]. flutter_svg has no
/// `errorBuilder`; the stack-trace path inside [SvgPicture.file] would
/// surface as a thrown exception during paint, which `flutter_markdown`
/// would propagate. We accept that risk for v1 — the prior code had no
/// error path either; if QA shows breakage on a malformed SVG we can
/// pull the read into a `FutureBuilder<String>` like [_MmdReference].
class _ClampedSvgFile extends StatelessWidget {
  const _ClampedSvgFile({required this.absPath, required this.alt});
  final String absPath;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kImageMaxWidth),
      child: SvgPicture.file(
        File(absPath),
        placeholderBuilder: (ctx) => _imageSkeletonCard(ctx, alt: alt),
      ),
    );
  }
}

/// HTTPS-backed image. Mirrors [_MmdReference]: stateful so the cache
/// resolve happens once per mount; stable-height skeleton while the
/// fetch is in flight; loud failure card on fetch error. The error UI
/// surfaces only [Uri.host] per vibesec — never the full URL (which
/// could carry an auth token in a redirect query string).
class _NetworkImage extends ConsumerStatefulWidget {
  const _NetworkImage({required this.url, required this.alt});
  final Uri url;
  final String? alt;

  @override
  ConsumerState<_NetworkImage> createState() => _NetworkImageState();
}

class _NetworkImageState extends ConsumerState<_NetworkImage> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(networkImageCacheProvider).resolve(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _imageSkeletonCard(context, alt: widget.alt);
        }
        if (snap.hasError) {
          final err = snap.error;
          final reason = err is NetworkImageFetchFailed
              ? 'fetch failed'
              : 'cache resolve failed';
          return _imageFailureCard(
            context,
            alt: widget.alt,
            reason: reason,
            diagnostic: widget.url.host,
          );
        }
        final path = snap.data;
        if (path == null) {
          return _imageFailureCard(
            context,
            alt: widget.alt,
            reason: 'cache returned no path',
            diagnostic: widget.url.host,
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kImageMaxWidth),
          child: Image.file(
            File(path),
            frameBuilder: (ctx, child, frame, _) {
              if (frame == null) {
                return _imageSkeletonCard(ctx, alt: widget.alt);
              }
              return child;
            },
            errorBuilder: (ctx, _, _) => _imageFailureCard(
              ctx,
              alt: widget.alt,
              reason: 'cached bytes failed to decode',
              diagnostic: widget.url.host,
            ),
          ),
        );
      },
    );
  }
}
