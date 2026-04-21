import 'dart:convert';
import 'dart:typed_data';

import '../ports/markdown_rasterizer_port.dart';

/// In-memory [MarkdownRasterizerPort] for domain + app tests. Returns a
/// preset [MarkdownRaster] without touching widgets — the real adapter
/// needs a mounted `RepaintBoundary`, which isn't available in a bare
/// `ProviderContainer` test.
///
/// The default PNG is a 1×1 fully-valid grayscale+alpha image so the
/// `pdf` package's `MemoryImage` parser can actually decode it when
/// `AnnotationPdfComposer` embeds it as a background. An 8-byte
/// signature-only stub would trip the parser and surface as a
/// `ReviewSubmissionFailure` in ReviewController tests that care about
/// the happy path — irritating to diagnose and unrelated to the
/// scenarios the tests actually care about.
class FakeMarkdownRasterizer implements MarkdownRasterizerPort {
  FakeMarkdownRasterizer({
    MarkdownRaster? output,
  }) : _output = output ??
            MarkdownRaster(
              canonicalWidth: 900,
              canonicalHeight: 1200,
              pngBytes: _minimalValidPng,
            );

  /// 68-byte fully-valid 1×1 transparent PNG (grayscale + alpha). Fits
  /// the pdf package's parser requirements without bloating the fake.
  static final Uint8List _minimalValidPng = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AA'
    'AAASUVORK5CYII=',
  ));

  final MarkdownRaster _output;
  final List<FakeRasterizeCall> _calls = [];

  List<FakeRasterizeCall> get calls => List.unmodifiable(_calls);

  void clear() => _calls.clear();

  @override
  Future<MarkdownRaster> rasterize({double pixelRatio = 2.0}) {
    _calls.add(FakeRasterizeCall(pixelRatio: pixelRatio));
    return Future.value(_output);
  }
}

class FakeRasterizeCall {
  const FakeRasterizeCall({required this.pixelRatio});
  final double pixelRatio;
}
