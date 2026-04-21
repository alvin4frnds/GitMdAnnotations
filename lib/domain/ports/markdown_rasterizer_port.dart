import 'dart:typed_data';

/// Rasterized PNG of the canonical markdown background at its full
/// scroll height. Size is in **canonical logical pixels**, not device
/// pixels — the PNG may have been captured at a `pixelRatio > 1` for
/// sharpness, but downstream layout / stroke overlay math uses the
/// canonical dimensions.
class MarkdownRaster {
  const MarkdownRaster({
    required this.canonicalWidth,
    required this.canonicalHeight,
    required this.pngBytes,
  });

  final double canonicalWidth;
  final double canonicalHeight;
  final Uint8List pngBytes;
}

/// Captures the currently-mounted markdown widget subtree (the
/// `RepaintBoundary` inside [CanonicalPage]) as a PNG at canonical
/// width. The domain layer talks to this port; the Flutter
/// implementation lives in `lib/infra/pdf/markdown_rasterizer_adapter.dart`
/// and reads the boundary via a Riverpod-scoped [GlobalKey].
///
/// Implementations throw [MarkdownRasterizeError] (sealed) on failure;
/// callers catch at the submit boundary and surface via the existing
/// error-presenter pipeline.
abstract class MarkdownRasterizerPort {
  /// Rasterize at [pixelRatio] physical-to-canonical sampling. Default
  /// 2.0 keeps text crisp at typical reader zoom levels without blowing
  /// up file size.
  Future<MarkdownRaster> rasterize({double pixelRatio = 2.0});
}

/// Sealed failure type for [MarkdownRasterizerPort].
sealed class MarkdownRasterizeError implements Exception {
  const MarkdownRasterizeError(this.message);

  final String message;

  @override
  String toString() => 'MarkdownRasterizeError($message)';
}

/// No mounted `RepaintBoundary` to capture — the annotate screen hasn't
/// registered its key yet, or was torn down before submit reached the
/// adapter.
class MarkdownRasterizeBoundaryMissing extends MarkdownRasterizeError {
  const MarkdownRasterizeBoundaryMissing(super.message);
}

/// `RenderRepaintBoundary.toImage` failed — typically engine allocation
/// or a GPU-side issue.
class MarkdownRasterizeRenderError extends MarkdownRasterizeError {
  const MarkdownRasterizeRenderError(super.message);
}

/// PNG encoding failed (`Image.toByteData` returned null or threw).
class MarkdownRasterizeEncodeError extends MarkdownRasterizeError {
  const MarkdownRasterizeEncodeError(super.message);
}
