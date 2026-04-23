import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_id_generator.dart';

/// Contract test for [IdGenerator] implemented by [FakeIdGenerator].
/// See IMPLEMENTATION.md §4.5 — stroke-group ids are domain-allocated and
/// opaque; determinism is what tests need.
void main() {
  group('FakeIdGenerator', () {
    test('returns stroke-group-A first, stroke-group-B second by default', () {
      final gen = FakeIdGenerator();
      expect(gen.next(), 'stroke-group-A');
      expect(gen.next(), 'stroke-group-B');
    });

    test('continues through the alphabet up to Z', () {
      final gen = FakeIdGenerator();
      final ids = List.generate(26, (_) => gen.next());
      expect(ids.first, 'stroke-group-A');
      expect(ids.last, 'stroke-group-Z');
    });

    test('after Z, rolls to AA, AB, … (deterministic)', () {
      final gen = FakeIdGenerator();
      for (var i = 0; i < 26; i++) {
        gen.next();
      }
      expect(gen.next(), 'stroke-group-AA');
      expect(gen.next(), 'stroke-group-AB');
    });

    test('accepts a custom prefix', () {
      final gen = FakeIdGenerator(prefix: 'g-');
      expect(gen.next(), 'g-A');
      expect(gen.next(), 'g-B');
    });
  });
}
