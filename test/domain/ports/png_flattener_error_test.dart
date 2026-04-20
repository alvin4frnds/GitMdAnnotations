import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/ports/png_flattener_port.dart';

/// Contract test for the sealed [PngFlattenError] hierarchy that the T10
/// infra adapter throws. The domain fake never throws, but downstream
/// callers (review submission in M1c) rely on matching against the sealed
/// subtypes — so the shape of the hierarchy is part of the port contract.
void main() {
  group('PngFlattenError', () {
    test('PngFlattenRenderError construction + message', () {
      const e = PngFlattenRenderError('boom');
      expect(e.message, 'boom');
    });

    test('PngFlattenEncodeError construction + message', () {
      const e = PngFlattenEncodeError('nope');
      expect(e.message, 'nope');
    });

    test('toString includes the subclass name and message', () {
      const e = PngFlattenRenderError('boom');
      final s = e.toString();
      expect(s, contains('boom'));
      expect(s, contains('PngFlattenError'));
    });

    test('PngFlattenError is assignable to Exception', () {
      const Exception e = PngFlattenRenderError('x');
      expect(e, isA<Exception>());
    });

    test('is-discrimination: render vs encode are distinguishable', () {
      const PngFlattenError render = PngFlattenRenderError('r');
      const PngFlattenError encode = PngFlattenEncodeError('e');
      expect(render, isA<PngFlattenRenderError>());
      expect(render, isNot(isA<PngFlattenEncodeError>()));
      expect(encode, isA<PngFlattenEncodeError>());
      expect(encode, isNot(isA<PngFlattenRenderError>()));
    });

    test('exhaustive switch over the sealed type compiles', () {
      String classify(PngFlattenError e) {
        return switch (e) {
          PngFlattenRenderError() => 'render',
          PngFlattenEncodeError() => 'encode',
        };
      }

      expect(classify(const PngFlattenRenderError('a')), 'render');
      expect(classify(const PngFlattenEncodeError('b')), 'encode');
    });
  });
}
