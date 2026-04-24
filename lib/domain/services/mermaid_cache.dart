import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../ports/file_system_port.dart';

/// Persistent, on-device cache of rendered Mermaid SVGs (spec-002
/// Milestone C). Keyed by the SHA-256 of the exact source text — a typo
/// fix that changes the source string invalidates intentionally because
/// users expect re-rendering.
///
/// Cache layout: `<appDocs>/mermaid-cache/<sha256>.svg`. The SVG string
/// is the raw output from `mermaid.render()`, stored as UTF-8 text.
///
/// The cache is best-effort: all read/write failures are swallowed and
/// treated as a miss. The WebView fallback will simply re-render.
class MermaidCache {
  MermaidCache({required FileSystemPort fs}) : _fs = fs;

  final FileSystemPort _fs;

  static const _subdir = 'mermaid-cache';

  /// Returns the cached SVG for [source], or null when the cache
  /// doesn't have an entry or the read fails. Never throws.
  Future<String?> read(String source) async {
    try {
      final path = await _pathFor(source);
      if (!await _fs.exists(path)) return null;
      return await _fs.readString(path);
    } on FsError {
      return null;
    }
  }

  /// Persists [svg] under the key derived from [source]. Silently
  /// no-ops on I/O failure — a missed write means the next render
  /// re-spins the WebView, which is the same fallback as a cache miss.
  Future<void> write(String source, String svg) async {
    try {
      final path = await _pathFor(source);
      await _fs.writeString(path, svg);
    } on FsError {
      // Best-effort cache.
    }
  }

  /// Deterministic SHA-256 key for [source]. Public so tests can
  /// assert the caching contract without reading the filesystem.
  ///
  /// CRLF normalization: Windows editors emit `\r\n` line endings,
  /// Linux/Mac emit `\n`. Users editing the same diagram across
  /// platforms should land on the same cache entry — otherwise every
  /// cross-platform open is a miss even when the visible content is
  /// identical.
  static String keyFor(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    final digest = sha256.convert(utf8.encode(normalized));
    return digest.toString();
  }

  Future<String> _pathFor(String source) async {
    final dir = await _fs.appDocsPath(_subdir);
    return '$dir/${keyFor(source)}.svg';
  }
}
