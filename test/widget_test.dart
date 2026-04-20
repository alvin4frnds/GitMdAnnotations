import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/ui/mockup_browser/mockup_browser_app.dart';

void main() {
  testWidgets('MockupBrowserApp builds', (tester) async {
    await tester.pumpWidget(const MockupBrowserApp());
    await tester.pump();
    expect(find.text('GitMdAnnotations'), findsWidgets);
  });
}
