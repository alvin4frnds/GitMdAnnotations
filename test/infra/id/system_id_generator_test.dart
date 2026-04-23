import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/ports/id_generator_port.dart';
import 'package:gitmdscribe/infra/id/system_id_generator.dart';

void main() {
  group('SystemIdGenerator', () {
    test('implements IdGenerator port', () {
      expect(SystemIdGenerator(), isA<IdGenerator>());
    });

    test('next() emits the documented stroke-group- prefix', () {
      final gen = SystemIdGenerator();
      expect(gen.next(), startsWith('stroke-group-'));
    });

    test('three consecutive next() calls produce distinct ids', () {
      final gen = SystemIdGenerator();
      final a = gen.next();
      final b = gen.next();
      final c = gen.next();
      expect({a, b, c}, hasLength(3));
    });
  });
}
