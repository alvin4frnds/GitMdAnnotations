import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/phase.dart';

void main() {
  group('Phase', () {
    test('enum has four values in declared order', () {
      expect(Phase.values, [
        Phase.spec,
        Phase.review,
        Phase.revised,
        Phase.approved,
      ]);
    });
  });

  group('Phase.resolve truth table (IMPLEMENTATION.md §4.3)', () {
    test('{02-spec.md} -> spec', () {
      expect(Phase.resolve({'02-spec.md'}), Phase.spec);
    });

    test('{02-spec.md, 03-review.md} -> review', () {
      expect(Phase.resolve({'02-spec.md', '03-review.md'}), Phase.review);
    });

    test('{02-spec.md, 03-review.md, 04-spec-v2.md} -> revised', () {
      expect(
        Phase.resolve({'02-spec.md', '03-review.md', '04-spec-v2.md'}),
        Phase.revised,
      );
    });

    test('later 04-spec-v* versions still resolve to revised', () {
      expect(
        Phase.resolve({'02-spec.md', '03-review.md', '04-spec-v7.md'}),
        Phase.revised,
      );
    });

    test('{02-spec.md, 03-review.md, 04-spec-v2.md, 05-approved} -> approved',
        () {
      expect(
        Phase.resolve({
          '02-spec.md',
          '03-review.md',
          '04-spec-v2.md',
          '05-approved',
        }),
        Phase.approved,
      );
    });

    test('empty set throws ArgumentError', () {
      expect(() => Phase.resolve(<String>{}), throwsArgumentError);
    });

    test('unrecognised file names throw ArgumentError', () {
      expect(
        () => Phase.resolve({'README.md', 'notes.txt'}),
        throwsArgumentError,
      );
    });
  });
}
