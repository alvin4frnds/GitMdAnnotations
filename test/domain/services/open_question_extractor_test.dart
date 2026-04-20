import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/services/open_question_extractor.dart';

void main() {
  final extractor = OpenQuestionExtractor();

  group('OpenQuestionExtractor — section detection', () {
    test('returns empty when "## Open questions" section is missing', () {
      const md = '# Spec\n\nBody.\n';
      expect(extractor.extract(md), isEmpty);
    });

    test('matches header case-insensitively (## Open Questions)', () {
      const md = '## Open Questions\n\n### Q1: Redis?\n';
      final out = extractor.extract(md);
      expect(out, hasLength(1));
      expect(out.first.id, 'Q1');
      expect(out.first.body, 'Redis?');
    });

    test('ignores Q-like lines above the section', () {
      const md = '''
Some preamble.

### Q9: ignored question before section

## Open questions

### Q1: Real one
''';
      final out = extractor.extract(md);
      expect(out.map((q) => q.id).toList(), ['Q1']);
    });

    test('stops at next level-2 heading', () {
      const md = '''
## Open questions

### Q1: First
### Q2: Second

## Other section

### Q3: Should be ignored
''';
      final out = extractor.extract(md);
      expect(out.map((q) => q.id).toList(), ['Q1', 'Q2']);
    });

    test('section exists but no recognised questions -> empty list', () {
      const md = '''
## Open questions

Just prose, nothing in the Q<n> form.
''';
      expect(extractor.extract(md), isEmpty);
    });
  });

  group('OpenQuestionExtractor — heading form (### Qn: body)', () {
    test('parses a §3.5-style list of 4 questions', () {
      const md = '''
# Spec — auth

## Open questions

### Q1: Should we support magic links?
### Q2: Is TOTP required on first login?
### Q3a: What about backup codes?
### Q4: Session lifetime?
''';
      final out = extractor.extract(md);
      expect(out, hasLength(4));
      expect(out[0], const OpenQuestion(
        id: 'Q1',
        body: 'Should we support magic links?',
      ));
      expect(out[1],
          const OpenQuestion(id: 'Q2', body: 'Is TOTP required on first login?'));
      expect(out[2],
          const OpenQuestion(id: 'Q3a', body: 'What about backup codes?'));
      expect(out[3], const OpenQuestion(id: 'Q4', body: 'Session lifetime?'));
    });

    test('concatenates multi-line body up to blank line, separated by space',
        () {
      const md = '''
## Open questions

### Q1: First part of body
second part still same question
third part too

### Q2: Short one
''';
      final out = extractor.extract(md);
      expect(out, hasLength(2));
      expect(out[0].body,
          'First part of body second part still same question third part too');
      expect(out[1].body, 'Short one');
    });
  });

  group('OpenQuestionExtractor — numbered list form', () {
    test('parses 1. Q1: … and 2. Q2: …', () {
      const md = '''
## Open questions

1. Q1: Do we cache results?
2. Q2: Which TTL?
''';
      final out = extractor.extract(md);
      expect(out.map((q) => q.id).toList(), ['Q1', 'Q2']);
      expect(out[0].body, 'Do we cache results?');
      expect(out[1].body, 'Which TTL?');
    });
  });

  group('OpenQuestionExtractor — bullet list form', () {
    test('parses - Q1: …', () {
      const md = '''
## Open questions

- Q1: Use Redis?
- Q2a: Or memcached?
''';
      final out = extractor.extract(md);
      expect(out, hasLength(2));
      expect(out[0].id, 'Q1');
      expect(out[0].body, 'Use Redis?');
      expect(out[1].id, 'Q2a');
      expect(out[1].body, 'Or memcached?');
    });
  });

  group('OpenQuestion — value semantics', () {
    test('equality and hashCode compare id + body', () {
      const a = OpenQuestion(id: 'Q1', body: 'x');
      const b = OpenQuestion(id: 'Q1', body: 'x');
      const c = OpenQuestion(id: 'Q1', body: 'y');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
