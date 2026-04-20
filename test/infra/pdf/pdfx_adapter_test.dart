import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pdf_document_handle.dart';
import 'package:gitmdannotations_tablet/domain/ports/pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/infra/pdf/pdfx_adapter.dart';

/// Host-side smoke coverage of [PdfxAdapter] — review follow-up to T8.
///
/// `pdfx` is a platform-channel plugin backed by PDFium; under
/// `flutter test` on the VM it reports
/// `MissingPluginException(No implementation found for method
/// open.document.file on channel io.scer.pdf_renderer)` because no
/// Flutter engine is running. The tests that cross that native
/// boundary therefore cannot run on the host and are deferred to M1b
/// close-out on the OPD2504 tablet (see docs/Issues.md).
///
/// What this file CAN pin without hitting the native lib:
///   - `open` of a bad path: `PdfDocument.openFile` throws synchronously
///     in the plugin stub (MissingPluginException) before any native
///     work; the adapter wraps every `Object` in `PdfOpenError`, so the
///     wrapper contract holds regardless of which `Object` was thrown.
///   - `close` of a handle that was never registered in `_docs`: the
///     adapter short-circuits with `if (doc == null) return` and never
///     touches the platform channel. This pins the idempotent-close
///     contract (PdfRasterPort doc comment: "Idempotent — subsequent
///     calls for the same handle are no-ops and MUST NOT throw").
///
/// The remaining cases (pageCount / id shape on a successful open,
/// PNG-signature on a rendered page, range errors, after-close render
/// behaviour) all require a live pdfx engine and are deferred — the
/// existing `integration_test/infra/pdf/pdfx_adapter_test.dart`
/// skeleton continues to carry them, still `skip:`ped.
void main() {
  late PdfxAdapter adapter;

  setUp(() {
    adapter = PdfxAdapter();
  });

  group('PdfxAdapter.open (pre-native)', () {
    test('wraps openFile failures in PdfOpenError with path + message',
        () async {
      // MissingPluginException fires inside pdfx.PdfDocument.openFile
      // before any native lib is consulted. The adapter's on Object
      // catch-all must still rewrite it into a typed PdfOpenError with
      // the caller's path preserved for log correlation.
      try {
        await adapter.open('/does/not/exist.pdf');
        fail('expected PdfOpenError');
      } on PdfOpenError catch (e) {
        expect(e.path, equals('/does/not/exist.pdf'));
        expect(e.message, isNotEmpty);
      }
    });

    test('rethrows as PdfOpenError rather than leaking raw plugin error',
        () async {
      // Regression pin: if the adapter lost its try/catch, the caller
      // would see a raw MissingPluginException (host) or PlatformException
      // (device) instead of the typed sealed PdfError hierarchy that
      // domain code pattern-matches on.
      await expectLater(
        adapter.open('/another/bad/path.pdf'),
        throwsA(isA<PdfOpenError>()),
      );
    });
  });

  group('PdfxAdapter.close (pre-native)', () {
    test('unknown handle is a no-op (never touches native lib)', () async {
      // PdfRasterPort contract: close MUST NOT throw for a handle the
      // adapter has never seen. This path short-circuits at the
      // `_docs.remove` lookup so it runs cleanly under `flutter test`
      // even though pdfx is unavailable.
      final unknown = PdfDocumentHandle(
        id: 'pdf-doc-never-opened-0',
        pageCount: 0,
      );
      await adapter.close(unknown); // must not throw.
    });

    test('same unknown handle closed twice is still a no-op (idempotent)',
        () async {
      // After the first remove the entry is gone; the second call hits
      // the same `doc == null` branch. Pins the explicit idempotency
      // contract called out in PdfRasterPort.close's doc comment.
      final unknown = PdfDocumentHandle(
        id: 'pdf-doc-never-opened-1',
        pageCount: 0,
      );
      await adapter.close(unknown);
      await adapter.close(unknown);
    });
  });
}
