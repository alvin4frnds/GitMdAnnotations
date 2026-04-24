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

void main() {
  group('MdMermaidBuilder.visitElementAfterWithContext', () {
    testWidgets(
      'returns a MermaidView for class="language-mermaid" code',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = md.Element.text('code', 'graph TD\nA-->B')
          ..attributes['class'] = 'language-mermaid';
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isA<MermaidView>());
        expect((widget! as MermaidView).source, 'graph TD\nA-->B');
      },
    );

    testWidgets(
      'returns null for non-mermaid code so flutter_markdown falls back '
      'to the default pre/code renderer',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = md.Element.text('code', 'print("hi")')
          ..attributes['class'] = 'language-dart';
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    testWidgets(
      'returns null for a code block with no class attribute',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = md.Element.text('code', 'plain text');
        final widget = MdMermaidBuilder()
            .visitElementAfterWithContext(ctx, element, null, null);
        expect(widget, isNull);
      },
    );

    testWidgets(
      'returns null for an empty mermaid code block',
      (tester) async {
        final ctx = await _aContext(tester);
        final element = md.Element.text('code', '   \n  ')
          ..attributes['class'] = 'language-mermaid';
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
