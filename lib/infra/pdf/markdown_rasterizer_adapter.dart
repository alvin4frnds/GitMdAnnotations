import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/ports/markdown_rasterizer_port.dart';

/// GPU max texture size on the devices this app targets. When
/// `scene.toImage` is asked for a larger output, Flutter/Skia silently
/// produces a *cropped* image (content in the first 16384 px, rest
/// dropped) — `ro.size` continues to report the full render-box size,
/// so downstream code has no idea the raster was truncated. Drifts
/// strokes relative to the markdown in the composite PDF.
///
/// 16384 is the common lower bound across OpenGL ES 3.x and Vulkan
/// drivers on mobile tablets; higher-end GPUs allow more but we clamp
/// conservatively to guarantee no surprise truncation in the field.
const double _kGpuMaxTexture = 16384;

/// Signature for "give me the currently-mounted RepaintBoundary key".
/// Usually reads a Riverpod `StateProvider<GlobalKey?>` that the
/// annotate screen sets on mount and clears on dispose.
typedef MarkdownBoundaryKeyLookup = GlobalKey? Function();

/// Production [MarkdownRasterizerPort] — captures the markdown
/// [RepaintBoundary] that [CanonicalPage] hosts in the annotate screen
/// and returns it as PNG bytes at canonical logical size.
///
/// ## How it locates the boundary
///
/// The annotate screen registers a [GlobalKey] via Riverpod when it
/// mounts and clears it on dispose. The adapter reads that key through
/// the injected [MarkdownBoundaryKeyLookup]; this keeps the Riverpod
/// coupling at composition-root (in `bootstrap.dart`) instead of
/// threading providers through the infra layer.
///
/// ## Canonical size, not physical
///
/// The `RepaintBoundary` lives INSIDE `Transform.scale`, so its
/// `RenderBox.size` is in unscaled canonical pixels — `toImage` at
/// `pixelRatio` produces an image of `canonicalSize * pixelRatio`
/// physical pixels. `MarkdownRaster.canonicalWidth` /
/// `canonicalHeight` expose the unscaled logical size so downstream
/// math (page tiling, stroke overlay) can line up without knowing the
/// sampling ratio.
///
/// Determinism: same widget state + same pixelRatio → byte-identical
/// PNG, matching the IMPLEMENTATION.md §3.7 commit-determinism
/// invariant.
class MarkdownRasterizerAdapter implements MarkdownRasterizerPort {
  MarkdownRasterizerAdapter({required MarkdownBoundaryKeyLookup boundaryKey})
      : _boundaryKey = boundaryKey;

  final MarkdownBoundaryKeyLookup _boundaryKey;

  @override
  Future<MarkdownRaster> rasterize({double pixelRatio = 2.0}) async {
    final key = _boundaryKey();
    if (key == null) {
      throw const MarkdownRasterizeBoundaryMissing(
        'no RepaintBoundary key registered — is the annotate screen mounted?',
      );
    }
    final ctx = key.currentContext;
    if (ctx == null) {
      throw const MarkdownRasterizeBoundaryMissing(
        'boundary key has no currentContext — widget unmounted',
      );
    }
    final ro = ctx.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw MarkdownRasterizeBoundaryMissing(
        'expected RenderRepaintBoundary, got ${ro.runtimeType}',
      );
    }
    final size = ro.size;
    // Clamp `pixelRatio` so neither image dimension exceeds the GPU
    // max texture. See [_kGpuMaxTexture] doc — raising this at caller
    // request and letting the engine truncate silently drifts strokes
    // relative to the raster in the downstream composite PDF.
    final longest = math.max(size.width, size.height);
    final safeRatio = longest <= 0
        ? pixelRatio
        : math.min(pixelRatio, _kGpuMaxTexture / longest);
    final ui.Image image;
    try {
      image = await ro.toImage(pixelRatio: safeRatio);
    } on Object catch (e) {
      throw MarkdownRasterizeRenderError('RepaintBoundary.toImage failed: $e');
    }
    try {
      final ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } on Object catch (e) {
        throw MarkdownRasterizeEncodeError('Image.toByteData failed: $e');
      }
      if (bytes == null) {
        throw const MarkdownRasterizeEncodeError(
          'Image.toByteData returned null',
        );
      }
      return MarkdownRaster(
        canonicalWidth: size.width,
        canonicalHeight: size.height,
        pngBytes: Uint8List.fromList(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      );
    } finally {
      image.dispose();
    }
  }
}
