import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/changelog_entry.dart';

void main() {
  group('ChangelogEntry', () {
    final ts = DateTime(2026, 4, 20, 14, 32);

    test('constructs with timestamp, author, description', () {
      final e = ChangelogEntry(
        timestamp: ts,
        author: 'tablet',
        description: 'User clarified auth flow — TOTP required.',
      );
      expect(e.timestamp, ts);
      expect(e.author, 'tablet');
      expect(
        e.description,
        'User clarified auth flow — TOTP required.',
      );
    });

    test('equal fields produce equal entries', () {
      final a = ChangelogEntry(
        timestamp: ts,
        author: 'tablet',
        description: 'd',
      );
      final b = ChangelogEntry(
        timestamp: ts,
        author: 'tablet',
        description: 'd',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different author is unequal', () {
      final a = ChangelogEntry(
        timestamp: ts,
        author: 'tablet',
        description: 'd',
      );
      final b = ChangelogEntry(
        timestamp: ts,
        author: 'desktop',
        description: 'd',
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes author and description', () {
      final e = ChangelogEntry(
        timestamp: ts,
        author: 'tablet',
        description: 'fixed it',
      );
      final s = e.toString();
      expect(s, contains('tablet'));
      expect(s, contains('fixed it'));
    });
  });
}
