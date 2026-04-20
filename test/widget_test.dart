import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/bootstrap.dart';
import 'package:gitmdannotations_tablet/ui/mockup_browser/mockup_browser_app.dart';

void main() {
  testWidgets('MockupBrowserApp builds under the mockup-mode scope',
      (tester) async {
    await tester.pumpWidget(
      buildAppScope(mode: AppMode.mockup, child: const MockupBrowserApp()),
    );
    await tester.pump();
    expect(find.text('GitMdAnnotations'), findsWidgets);
  });
}
