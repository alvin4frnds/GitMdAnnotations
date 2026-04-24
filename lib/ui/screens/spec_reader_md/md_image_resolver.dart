import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/tokens.dart';

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
///   * anything else → a muted "unsupported" card with the alt text.
///
/// Relative URIs resolve against [path.dirname(specPath)]; absolute
/// `file://` and filesystem paths are taken verbatim. Remote schemes
/// (`http`, `https`) are not supported (offline-first invariant) — they
/// fall through to the "unsupported" card.
Widget resolveInlineImage({
  required Uri uri,
  required String specPath,
  required BuildContext context,
  String? title,
  String? alt,
}) {
  final absPath = _resolveAbsolute(uri, specPath);
  if (absPath == null) {
    return _unsupportedCard(context, alt: alt, reason: 'remote URL');
  }
  final ext = _extension(absPath);
  switch (ext) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.gif':
    case '.webp':
    case '.bmp':
      return Image.file(
        File(absPath),
        errorBuilder: (c, _, _) =>
            _unsupportedCard(c, alt: alt, reason: 'file not found'),
      );
    case '.svg':
      return SvgPicture.file(
        File(absPath),
        placeholderBuilder: (_) =>
            const SizedBox(height: 24, child: LinearProgressIndicator()),
      );
    case '.mmd':
      // Milestone C replaces this with a MermaidView that reads the file
      // and runs the renderer. Until then, a stable-height placeholder so
      // scroll position doesn't jump when C lands.
      return _placeholderCard(
        context,
        title: 'Mermaid preview pending',
        body: alt ?? _basename(absPath),
      );
    default:
      return _unsupportedCard(
        context,
        alt: alt,
        reason: 'unsupported extension: ${ext.isEmpty ? "(none)" : ext}',
      );
  }
}

/// Resolves [uri] to an absolute filesystem path using [specPath] as the
/// anchor for relative references. Returns null for remote URIs
/// (http/https) — those are not supported.
String? _resolveAbsolute(Uri uri, String specPath) {
  if (uri.scheme == 'http' || uri.scheme == 'https') return null;
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
