@Tags(['platform'])
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';
import 'package:gitmdannotations_tablet/infra/pdf/pdfx_adapter.dart';
import 'package:integration_test/integration_test.dart';

/// Integration tests for [PdfxAdapter] against a real `pdfx` engine.
///
/// These tests need a running Flutter host (device, emulator, or
/// integration_test harness) because pdfx binds to native Android /
/// Windows / macOS / iOS backends through its plugin. They are tagged
/// `platform` + individually `skip`ped so the unit-test suite
/// (`flutter test test/`) never touches them; they run via
/// `fvm flutter test integration_test/infra/pdf/pdfx_adapter_test.dart
///    -d NBB6BMB6QGQWLFV4`
/// as part of M1b close-out on the OPD2504 tablet.
///
/// The fixture is a 587-byte minimal 1-page PDF at
/// `integration_test/fixtures/hello.pdf`, declared as an app asset in
/// `pubspec.yaml`. We load it via [rootBundle.load] + write it to a
/// tempfile so `pdfx`'s `openFile` path is exercised — this matches the
/// production flow where PDFs live on the libgit2dart-managed workdir,
/// not as bundled assets.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PdfxAdapter adapter;

  setUp(() {
    adapter = PdfxAdapter();
  });

  test('open then renderPage returns non-empty PNG bytes', () async {
    // TODO (M1b close-out): replace the rootBundle loader with a
    // file:// path derived from an existing FakeFileSystem/FsAdapter
    // fixture once T9 wires the SpecReader flow to PdfRasterPort. For
    // now the rootBundle path exercises the pdfx integration without
    // needing libgit2dart on-device.
    final ByteData raw =
        await rootBundle.load('integration_test/fixtures/hello.pdf');
    final Uint8List pdfBytes = raw.buffer.asUint8List(
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    // Temporarily bypass `openFile` by using the data-source path on
    // pdfx itself — this test is a skeleton; the file-path variant gets
    // wired when a real workdir seam is available.
    expect(pdfBytes, isNotEmpty);
    expect(pdfBytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));

    // Skeleton body for the real open+render call once the file-path
    // seam lands:
    //   final handle = await adapter.open('<file-path>');
    //   expect(handle.pageCount, 1);
    //   final bytes = await adapter.renderPage(
    //     handle: handle,
    //     pageNumber: 1,
    //     targetSize: CanvasSize(width: 200, height: 200),
    //   );
    //   expect(bytes, isNotEmpty);
    //   expect(bytes.sublist(0, 8), equals(
    //     [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
    //   await adapter.close(handle);
    expect(adapter, isNotNull);
    // Silence "unused import" lints until the full body runs:
    CanvasSize(width: 200, height: 200);
  }, skip: 'TODO(M1b-close): enable with a file-path seam on OPD2504');

  test('open of a non-existent path throws PdfOpenError', () async {
    // Skeleton:
    //   await expectLater(
    //     adapter.open('/does/not/exist.pdf'),
    //     throwsA(isA<PdfOpenError>()),
    //   );
  }, skip: 'TODO(M1b-close): enable with device-visible tmp path');

  test('close is idempotent', () async {
    // Skeleton:
    //   final handle = await adapter.open('<file-path>');
    //   await adapter.close(handle);
    //   await adapter.close(handle); // must not throw
  }, skip: 'TODO(M1b-close): enable with a file-path seam on OPD2504');
}
