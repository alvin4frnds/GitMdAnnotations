import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_controller.dart';
import 'package:gitmdscribe/app/providers/auth_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/app/providers/sync_providers.dart';
import 'package:gitmdscribe/domain/entities/auth_session.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/spec_reader_md_screen.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

final _session = AuthSession(
  token: 'fake',
  identity: const GitIdentity(
    name: 'Test User',
    email: 'test@example.com',
  ),
);

Widget _wrap({
  required FakeFileSystem fs,
  required FakeGitPort git,
  required String workdir,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      fileSystemProvider.overrideWithValue(fs),
      gitPortProvider.overrideWithValue(git),
      currentWorkdirProvider.overrideWith((_) => workdir),
      authControllerProvider.overrideWith(
        () => _StubAuthController(AuthSignedIn(_session)),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  // The real screen is designed for tablet landscape; use a wide surface
  // in tests so the top chrome doesn't overflow into yellow-stripes.
  testWidgets(
    'tapping Edit reveals a TextField; typing enables the Save button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(2000, 1400));
      final fs = FakeFileSystem()
        ..seedFile('/repo/docs/spec.md', '# original\n\nhello\n');
      final git = FakeGitPort()..activeBranch = 'main';
      await tester.pumpWidget(_wrap(
        fs: fs,
        git: git,
        workdir: '/repo',
        child: const SpecReaderMdScreen.fromPath(
          filePath: '/repo/docs/spec.md',
        ),
      ));
      await tester.pumpAndSettle();

      // Preview mode is the default; the Save button isn't visible yet.
      expect(find.text('Save'), findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final saveFinder = find.ancestor(
        of: find.text('Save'),
        matching: find.byType(ElevatedButton),
      );
      expect(saveFinder, findsOneWidget);
      final disabledOnPressed =
          tester.widget<ElevatedButton>(saveFinder).onPressed;
      expect(disabledOnPressed, isNull,
          reason: 'Save should be disabled while the editor is unchanged');

      await tester.enterText(find.byType(TextField), 'edited text');
      await tester.pump();

      final enabledOnPressed =
          tester.widget<ElevatedButton>(saveFinder).onPressed;
      expect(enabledOnPressed, isNotNull,
          reason: 'Save should enable once the editor is dirty');
    },
  );

  testWidgets(
    'popping while dirty triggers the discard confirmation sheet',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(2000, 1400));
      final fs = FakeFileSystem()
        ..seedFile('/repo/docs/spec.md', '# original\n');
      final git = FakeGitPort()..activeBranch = 'main';

      // Wrap the screen under a parent route so we can simulate a real
      // pop attempt via Navigator.maybePop — PopScope's intercept runs
      // when a non-root pop is attempted.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemProvider.overrideWithValue(fs),
            gitPortProvider.overrideWithValue(git),
            currentWorkdirProvider.overrideWith((_) => '/repo'),
            authControllerProvider.overrideWith(
              () => _StubAuthController(AuthSignedIn(_session)),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: SpecReaderMdScreen.fromPath(
                          filePath: '/repo/docs/spec.md',
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open-reader'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-reader'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'edited');
      await tester.pump();

      // Simulate the user hitting the system back button on the pushed
      // route. PopScope's onPopInvokedWithResult fires with didPop=false
      // (canPop is false while dirty).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved edits?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    },
  );
}
