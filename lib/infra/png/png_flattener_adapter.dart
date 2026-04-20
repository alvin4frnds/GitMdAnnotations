import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/entities/canvas_size.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/ports/png_flattener_port.dart';
import '../../ui/widgets/ink_overlay/ink_painting.dart';

/// Rasterizes a [ui.Picture] to a [ui.Image] of the given logical size.
///
/// Seam for [PngFlattenerAdapter]: the default delegates to
/// [ui.Picture.toImage], but tests can inject a throwing version to
/// exercise the [PngFlattenRenderError] branch without needing a GPU.
typedef PictureToImage = Future<ui.Image> Function(
  ui.Picture picture,
  int width,
  int height,
);

/// Encodes a [ui.Image] to PNG [ByteData].
///
/// Seam for [PngFlattenerAdapter]: the default delegates to
/// [ui.Image.toByteData] with [ui.ImageByteFormat.png], but tests can
/// inject a version that returns `null` or throws to exercise the
/// [PngFlattenEncodeError] branch without needing a GPU.
typedef ImageToPngBytes = Future<ByteData?> Function(ui.Image image);

Future<ui.Image> _defaultToImage(ui.Picture picture, int width, int height) =>
    picture.toImage(width, height);

Future<ByteData?> _defaultToPngBytes(ui.Image image) =>
    image.toByteData(format: ui.ImageByteFormat.png);

/// Production [PngFlattener] — rasterizes committed [StrokeGroup]s to a PNG
/// byte stream via an offscreen `PictureRecorder` + `Picture.toImage`
/// (IMPLEMENTATION.md §4.5).
///
/// Design invariants:
/// * **Transparent background.** Matches §3.4 SVG's transparent canvas.
/// * **Device pixel ratio = 1.0.** The PNG is a fidelity aid; SVG is the
///   vector truth. DPR scaling can be added later as a parameter without
///   breaking the port contract.
/// * **Active stroke is never painted.** Active-stroke is a UI concept and
///   is not part of the committed review. The adapter passes sentinel
///   `Colors.transparent` + width `0.0` to [paintStrokeGroups] with an
///   empty active-stroke list.
/// * **Same visual as on screen.** Renders via the shared
///   [paintStrokeGroups] so the PNG is byte-consistent with what the user
///   saw — important for the review audit trail.
/// * **Caller-owned isolate.** The flatten call is cheap enough per
///   review to run on the UI isolate in tests, but per §2.4 the review
///   module dispatches it via `compute()` at submit time. The adapter
///   itself does not spawn an isolate.
/// * **Determinism (§3.7).** Same inputs → byte-identical outputs.
///
/// Testing seams: [toImage] and [toPngBytes] let tests inject throwing or
/// null-returning versions of the two `dart:ui` calls that can fail, so
/// the [PngFlattenRenderError] / [PngFlattenEncodeError] branches get
/// behavior-level coverage without a GPU. Production callers pass
/// neither and get the real `dart:ui` implementations.
class PngFlattenerAdapter implements PngFlattener {
  PngFlattenerAdapter({
    PictureToImage? toImage,
    ImageToPngBytes? toPngBytes,
  })  : _toImage = toImage ?? _defaultToImage,
        _toPngBytes = toPngBytes ?? _defaultToPngBytes;

  final PictureToImage _toImage;
  final ImageToPngBytes _toPngBytes;

  @override
  Future<Uint8List> flatten({
    required List<StrokeGroup> groups,
    required CanvasSize canvas,
  }) async {
    final image = await _recordAndRasterize(groups: groups, canvas: canvas);
    try {
      return await _encodeToPng(image);
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image> _recordAndRasterize({
    required List<StrokeGroup> groups,
    required CanvasSize canvas,
  }) async {
    final recorder = ui.PictureRecorder();
    final paintCanvas = Canvas(recorder);
    paintStrokeGroups(
      paintCanvas,
      groups: groups,
      activeStrokePoints: const [],
      activeStrokeColor: const Color(0x00000000),
      activeStrokeWidth: 0.0,
    );
    final picture = recorder.endRecording();
    try {
      return await _toImage(
        picture,
        canvas.width.round(),
        canvas.height.round(),
      );
    } on Object catch (e) {
      throw PngFlattenRenderError('Picture.toImage failed: $e');
    } finally {
      picture.dispose();
    }
  }

  Future<Uint8List> _encodeToPng(ui.Image image) async {
    final ByteData? data;
    try {
      data = await _toPngBytes(image);
    } on Object catch (e) {
      throw PngFlattenEncodeError('Image.toByteData failed: $e');
    }
    if (data == null) {
      throw const PngFlattenEncodeError('Image.toByteData returned null');
    }
    return Uint8List.fromList(data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ));
  }
}
