import 'dart:typed_data';

import '../entities/canvas_size.dart';
import '../entities/stroke_group.dart';
import '../ports/png_flattener_port.dart';

/// In-memory [PngFlattener] for domain tests. Records every call and
/// returns either the constructor-supplied [output] or a deterministic
/// 8-byte PNG signature stand-in so downstream "is this a PNG?" checks
/// pass while the real rasterizer (T10) is still a fake.
class FakePngFlattener implements PngFlattener {
  FakePngFlattener({Uint8List? output}) : _output = output;

  /// 8-byte PNG signature (`\x89PNG\r\n\x1a\n`) — the default bytes returned
  /// when no constructor override is supplied, so downstream "is this a
  /// PNG?" checks succeed.
  static final Uint8List defaultPngSignature = Uint8List.fromList(
    const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  );

  final Uint8List? _output;
  final List<FakeFlattenCall> _calls = [];

  /// Every call to [flatten], in order. Returned as an unmodifiable view so
  /// tests iterating the log cannot corrupt the fake's internal state.
  List<FakeFlattenCall> get calls => List.unmodifiable(_calls);

  /// Reset the recorded call log. Useful for tests that reuse a single
  /// fake instance across scenarios.
  void clear() {
    _calls.clear();
  }

  @override
  Future<Uint8List> flatten({
    required List<StrokeGroup> groups,
    required CanvasSize canvas,
  }) {
    _calls.add(
      FakeFlattenCall(
        groups: List<StrokeGroup>.unmodifiable(groups),
        canvas: canvas,
      ),
    );
    return Future.value(_output ?? defaultPngSignature);
  }
}

/// One recorded invocation of [FakePngFlattener.flatten].
class FakeFlattenCall {
  const FakeFlattenCall({required this.groups, required this.canvas});

  final List<StrokeGroup> groups;
  final CanvasSize canvas;
}
