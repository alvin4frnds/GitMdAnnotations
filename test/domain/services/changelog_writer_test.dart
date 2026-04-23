import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/changelog_entry.dart';
import 'package:gitmdscribe/domain/services/changelog_writer.dart';

void main() {
  const writer = ChangelogWriter();

  group('ChangelogWriter.formatLine', () {
    test('produces canonical YYYY-MM-DD HH:mm bullet', () {
      final entry = ChangelogEntry(
        timestamp: DateTime(2026, 4, 20, 14, 32),
        author: 'tablet',
        description: 'Example description.',
      );
      expect(
        writer.formatLine(entry),
        '- 2026-04-20 14:32 tablet: Example description.',
      );
    });

    test('zero-pads single-digit month/day/hour/minute', () {
      final entry = ChangelogEntry(
        timestamp: DateTime(2026, 1, 2, 3, 4),
        author: 'tablet',
        description: 'Edge-case padding.',
      );
      expect(
        writer.formatLine(entry),
        '- 2026-01-02 03:04 tablet: Edge-case padding.',
      );
    });

    test('rejects empty author', () {
      final entry = ChangelogEntry(
        timestamp: DateTime(2026, 4, 20, 14, 32),
        author: '',
        description: 'Non-empty.',
      );
      expect(() => writer.formatLine(entry), throwsArgumentError);
    });

    test('rejects empty description', () {
      final entry = ChangelogEntry(
        timestamp: DateTime(2026, 4, 20, 14, 32),
        author: 'tablet',
        description: '',
      );
      expect(() => writer.formatLine(entry), throwsArgumentError);
    });
  });

  group('ChangelogWriter.append', () {
    final entry = ChangelogEntry(
      timestamp: DateTime(2026, 4, 20, 14, 32),
      author: 'tablet',
      description: 'Hi.',
    );

    test('to empty file creates section', () {
      expect(
        writer.append('', entry),
        '## Changelog\n\n- 2026-04-20 14:32 tablet: Hi.\n',
      );
    });

    test('to file with no ## Changelog section appends section at end', () {
      const input = '# Title\n\nbody\n';
      expect(
        writer.append(input, entry),
        '# Title\n\nbody\n\n## Changelog\n\n- 2026-04-20 14:32 tablet: Hi.\n',
      );
    });

    test('to file with existing changelog adds bullet at end of section', () {
      const input = '# Title\n\n'
          '## Changelog\n\n'
          '- 2026-04-18 09:00 desktop: First.\n'
          '- 2026-04-19 10:00 desktop: Second.\n\n'
          '## Other section\n\n'
          'trailing body\n';
      const expected = '# Title\n\n'
          '## Changelog\n\n'
          '- 2026-04-18 09:00 desktop: First.\n'
          '- 2026-04-19 10:00 desktop: Second.\n'
          '- 2026-04-20 14:32 tablet: Hi.\n\n'
          '## Other section\n\n'
          'trailing body\n';
      expect(writer.append(input, entry), expected);
    });

    test('idempotent on exact duplicate line', () {
      const input = '## Changelog\n\n- 2026-04-20 14:32 tablet: Hi.\n';
      expect(writer.append(input, entry), input);
    });

    test('with two different entries same timestamp emits both', () {
      final other = ChangelogEntry(
        timestamp: DateTime(2026, 4, 20, 14, 32),
        author: 'desktop',
        description: 'Other description.',
      );
      final afterFirst = writer.append('', entry);
      final afterSecond = writer.append(afterFirst, other);
      expect(
        afterSecond,
        '## Changelog\n\n'
        '- 2026-04-20 14:32 tablet: Hi.\n'
        '- 2026-04-20 14:32 desktop: Other description.\n',
      );
    });

    test('preserves line order of existing entries', () {
      const input = '## Changelog\n\n'
          '- 2026-04-10 08:00 desktop: Oldest.\n'
          '- 2026-04-11 09:00 desktop: Middle.\n'
          '- 2026-04-12 10:00 desktop: Newest existing.\n';
      final out = writer.append(input, entry);
      final idxOldest = out.indexOf('Oldest.');
      final idxMiddle = out.indexOf('Middle.');
      final idxNewestExisting = out.indexOf('Newest existing.');
      final idxAppended = out.indexOf('Hi.');
      expect(
        [idxOldest, idxMiddle, idxNewestExisting, idxAppended],
        everyElement(greaterThanOrEqualTo(0)),
      );
      expect(idxOldest < idxMiddle, isTrue);
      expect(idxMiddle < idxNewestExisting, isTrue);
      expect(idxNewestExisting < idxAppended, isTrue);
    });

    test('normalizes CRLF input to LF in output', () {
      const crlf = '# Title\r\n\r\n## Changelog\r\n\r\n'
          '- 2026-04-18 09:00 desktop: First.\r\n';
      final out = writer.append(crlf, entry);
      expect(out.contains('\r'), isFalse);
    });

    test('emits LF-only output and trailing newline', () {
      const input = '# Title\n\nbody\n';
      final out = writer.append(input, entry);
      expect(out.contains('\r'), isFalse);
      expect(out.endsWith('\n'), isTrue);
    });

    test('ignores duplicate-looking line in a non-Changelog section', () {
      // The formatted bullet for `entry` is:
      // `- 2026-04-20 14:32 tablet: Hi.`
      // That exact byte-equal string appears as a plain bullet inside an
      // `## Answers` block (e.g. a user quoted/pasted a previous changelog
      // bullet into their answer), but is NOT present in the `## Changelog`
      // section. The duplicate-detection scan must be scoped to the
      // Changelog section only, otherwise the entry would be silently
      // dropped.
      const input = '# Title\n\n'
          '## Answers\n\n'
          '- 2026-04-20 14:32 tablet: Hi.\n\n'
          '## Changelog\n\n'
          '- 2026-04-18 09:00 desktop: First.\n';
      final out = writer.append(input, entry);
      // The new bullet must be present in the changelog section, and the
      // outer (unrelated) occurrence must not short-circuit append.
      const expected = '# Title\n\n'
          '## Answers\n\n'
          '- 2026-04-20 14:32 tablet: Hi.\n\n'
          '## Changelog\n\n'
          '- 2026-04-18 09:00 desktop: First.\n'
          '- 2026-04-20 14:32 tablet: Hi.\n';
      expect(out, expected);
    });

    test('on header-only section inserts blank line before first bullet', () {
      const input = '# Title\n\n## Changelog\n';
      expect(
        writer.append(input, entry),
        '# Title\n\n## Changelog\n\n- 2026-04-20 14:32 tablet: Hi.\n',
      );
    });
  });
}
