import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/bootstrap.dart';
import 'package:gitmdannotations_tablet/ui/mockup_browser/mockup_browser_app.dart';
import 'package:gitmdannotations_tablet/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart';
import 'package:gitmdannotations_tablet/ui/widgets/pdf_page_view/pdf_page_view.dart';

void main() {
  testWidgets('MockupBrowserApp builds under the mockup-mode scope',
      (tester) async {
    await tester.pumpWidget(
      buildAppScope(mode: AppMode.mockup, child: const MockupBrowserApp()),
    );
    await tester.pump();
    expect(find.text('GitMdAnnotations'), findsWidgets);
  });

  testWidgets(
      'Spec reader (PDF) mockup entry renders with the seeded fake port',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildAppScope(mode: AppMode.mockup, child: const MockupBrowserApp()),
    );
    await tester.pump();

    await tester.tap(find.text('4b. Spec reader (PDF)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SpecReaderPdfScreen), findsOneWidget);
    expect(find.byType(PdfPageView), findsOneWidget);
  });
}
