import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pdf_document_handle.dart';

/// Unit tests for [PdfDocumentHandle]. The handle is a pure-Dart value
/// object: any two handles with the same [PdfDocumentHandle.id] compare
/// equal regardless of [PdfDocumentHandle.pageCount]. Adapters are free to
/// map ids back to native document references internally, but the domain
/// only sees the opaque id. See IMPLEMENTATION.md §4.4.
void main() {
  group('PdfDocumentHandle', () {
    test('exposes id and pageCount via constructor', () {
      final h = PdfDocumentHandle(id: 'doc-1', pageCount: 3);
      expect(h.id, 'doc-1');
      expect(h.pageCount, 3);
    });

    test('two handles with the same id compare equal', () {
      final a = PdfDocumentHandle(id: 'doc-1', pageCount: 3);
      final b = PdfDocumentHandle(id: 'doc-1', pageCount: 3);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality is keyed by id only (pageCount ignored)', () {
      final a = PdfDocumentHandle(id: 'doc-1', pageCount: 3);
      final b = PdfDocumentHandle(id: 'doc-1', pageCount: 99);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('handles with different ids are not equal', () {
      final a = PdfDocumentHandle(id: 'doc-1', pageCount: 3);
      final b = PdfDocumentHandle(id: 'doc-2', pageCount: 3);
      expect(a, isNot(equals(b)));
    });

    test('toString includes both id and pageCount', () {
      final h = PdfDocumentHandle(id: 'doc-xyz', pageCount: 7);
      expect(h.toString(), contains('doc-xyz'));
      expect(h.toString(), contains('7'));
    });

    test('pageCount must be non-negative', () {
      expect(
        () => PdfDocumentHandle(id: 'doc', pageCount: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('id must be non-empty', () {
      expect(
        () => PdfDocumentHandle(id: '', pageCount: 1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
