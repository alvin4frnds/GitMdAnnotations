import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/md_mermaid_builder.dart';
import 'package:gitmdscribe/ui/widgets/mermaid_view/mermaid_view.dart';
import 'package:markdown/markdown.dart' as md;

Future<BuildContext> _aContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ),
  );
  return ctx;
}

md.Element _preWithCode({
  required String source,
  required String? languageClass,
}) {
  final code = md.Element.text('code', source);
  if (languageClass != null) {
    code.attributes['class'] = languageClass;
  }
  return md.Element('pre', [code]);
}

void main() {
  group('MdMermaidBuilder.visitElementAfterWithContext', () {
    testWidgets(
      'returns a MermaidView for pre > code.language-mermaid',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = _preWithCode(
          source: 'graph TD\nA-->B',
          languageClass: 'language-mermaid',
        );
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isA<MermaidView>());
        expect((widget! as MermaidView).source, 'graph TD\nA-->B');
      },
    );

    testWidgets(
      'returns null for non-mermaid fenced code so flutter_markdown '
      'falls back to the default pre/code renderer',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = _preWithCode(
          source: 'print("hi")',
          languageClass: 'language-dart',
        );
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    testWidgets(
      'returns null for a fenced code block with no language class',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = _preWithCode(source: 'plain text', languageClass: null);
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    testWidgets(
      'returns null for an empty mermaid fence',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = _preWithCode(
          source: '   \n  ',
          languageClass: 'language-mermaid',
        );
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    testWidgets(
      'returns null when pre wraps something other than a single code child',
      (tester) async {
        final ctx = await _aContext(tester);
        // Unusual shape — pre with two code children. Shouldn't crash
        // and should fall back to default rendering.
        final element = md.Element('pre', [
          md.Element.text('code', 'first'),
          md.Element.text('code', 'second'),
        ]);
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    test('isBlockElement() is true (fenced mermaid is block-level)', () {
      expect(MdMermaidBuilder().isBlockElement(), isTrue);
    });
  });
}
