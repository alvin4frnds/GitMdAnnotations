import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_controller.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/auth_session.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/auth_port.dart';
import 'package:gitmdannotations_tablet/ui/screens/sign_in/sign_in_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';

/// Short poll interval: we want the AwaitingUser state to surface (the
/// fake emits the initial challenge synchronously via a microtask) but we
/// still need the pending Future.delayed in `pollForToken` to resolve
/// before the test tears down — flutter_test rejects pending timers.
DeviceCodeChallenge _challenge({
  Duration pollInterval = const Duration(milliseconds: 5),
}) =>
    DeviceCodeChallenge(
      deviceCode: 'dev_abc',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: pollInterval,
      expiresAt: DateTime.utc(2099, 1, 1),
    );

Widget _host({
  required FakeAuthPort auth,
  required FakeSecureStorage storage,
}) {
  return ProviderScope(
    overrides: [
      authPortProvider.overrideWithValue(auth),
      secureStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: const Scaffold(body: SignInScreen()),
    ),
  );
}

void main() {
  testWidgets(
      'signed-out state shows "Continue with GitHub"; tapping it starts '
      'the device flow and the userCode is rendered', (tester) async {
    final auth = FakeAuthPort()
      ..nextChallenge = _challenge()
      // Terminate the flow with a user-denied response so every pending
      // timer resolves before the test finishes. The AwaitingUser state
      // still surfaces between the initial challenge arriving and the
      // poll throwing.
      ..pollScript.add(const PollAccessDenied());
    addTearDown(auth.dispose);
    final storage = FakeSecureStorage();

    await tester.pumpWidget(_host(auth: auth, storage: storage));
    // One pump to let the initial AsyncNotifier.build settle.
    await tester.pump();
    await tester.pump();

    expect(find.text('Continue with GitHub'), findsOneWidget);

    await tester.tap(find.text('Continue with GitHub'));
    // Pump once so the controller receives the first challenge from the
    // fake's scheduleMicrotask and flips state to AwaitingUser before the
    // poll runs and terminates the flow.
    await tester.pump();

    expect(find.text('WDJB-MJHT'), findsOneWidget);
    expect(
      find.textContaining('github.com/login/device'),
      findsOneWidget,
    );

    // Drain the remaining timers (AccessDenied poll). Without this the
    // flutter_test harness complains about pending Future.delayed handles.
    await tester.pumpAndSettle();
  });

  // ---------------------------------------------------------------------
  // Fix 2 — device-code panel renders the seeded userCode, then poll
  // script walks the controller to AuthSignedIn.
  // ---------------------------------------------------------------------
  testWidgets(
      'seeded device flow renders userCode and auto-completes to '
      'AuthSignedIn after the poll script resolves', (tester) async {
    final session = AuthSession(
      token: 'mock-token',
      identity: const GitIdentity(name: 'demo', email: 'demo@example.com'),
    );
    final auth = FakeAuthPort()
      ..nextChallenge = _challenge(pollInterval: const Duration(milliseconds: 5))
      ..pollScript.addAll([
        const PollAuthorizationPending(),
        const PollAuthorizationPending(),
        PollSuccess(session),
      ]);
    addTearDown(auth.dispose);
    final storage = FakeSecureStorage();

    await tester.pumpWidget(_host(auth: auth, storage: storage));
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SignInScreen)),
    );

    // Kick off the device flow from the controller directly. Using
    // tester.runAsync keeps the FakeAuthPort's Future.delayed against
    // real wall-clock time — the widget test's fake clock doesn't
    // advance deep async chains even with tester.pump(duration).
    await tester.runAsync(() async {
      // ignore: unawaited_futures
      container.read(authControllerProvider.notifier).startDeviceFlow();
      // Let the stream deliver its first challenge.
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump();

    // Awaiting-user panel must render the seeded code plus the verification
    // caption so the demo reviewer can act on it.
    expect(find.text('WDJB-MJHT'), findsOneWidget);
    expect(
      find.text('Open github.com/login/device and enter this code.'),
      findsOneWidget,
    );

    // Wait (real time) for the 3-step poll script to resolve.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.pump();

    final state = container.read(authControllerProvider).value;
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).session.identity.name, 'demo');
    expect(find.text('Signed in as @demo'), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // Fix 1 — PAT dialog renders a real AlertDialog with a visible title,
  // a TextField, Cancel + Sign in buttons, and an explicit barrier
  // colour so the dialog never drops onto an opaque black surface.
  // ---------------------------------------------------------------------
  testWidgets(
      'tapping "Sign in with a token instead" opens a PAT AlertDialog with '
      'a visible title, TextField, Cancel, and Sign in', (tester) async {
    final auth = FakeAuthPort();
    addTearDown(auth.dispose);
    final storage = FakeSecureStorage();

    await tester.pumpWidget(_host(auth: auth, storage: storage));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Sign in with a token instead'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Paste personal access token'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);

    // Sign in must be disabled while the PAT field is empty so the
    // dialog can't submit an empty token against the auth port.
    final signInBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Sign in'),
    );
    expect(signInBtn.onPressed, isNull);

    // The dialog's ModalBarrier must use a non-opaque scrim so the PAT
    // card doesn't render on a full-black surface. We look for any
    // ModalBarrier with a non-black (or translucent) colour — the scrim
    // ModalBarrier is inserted by showDialog and lives beneath the card.
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    final scrim = barriers.firstWhere(
      (b) => b.color != null && b.color != const Color(0xFF000000),
      orElse: () => barriers.first,
    );
    expect(scrim.color, isNotNull);
    // Scrim must be translucent (alpha < 1.0) so the background remains
    // partially visible — rules out the default opaque black that caused
    // the QA "fully black surface" report.
    expect(scrim.color!.a, lessThan(1.0));
  });

  testWidgets(
      'PAT dialog: submitting the seeded mockup PAT transitions to '
      'AuthSignedIn', (tester) async {
    final session = AuthSession(
      token: 'mock-token',
      identity: const GitIdentity(name: 'demo', email: 'demo@example.com'),
    );
    final auth = FakeAuthPort()
      ..patScript['ghp_mockup_demo_token'] = PatResponse.success(session);
    addTearDown(auth.dispose);
    final storage = FakeSecureStorage();

    await tester.pumpWidget(_host(auth: auth, storage: storage));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Sign in with a token instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ghp_mockup_demo_token');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SignInScreen)),
    );
    final state = container.read(authControllerProvider).value;
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).session.identity.name, 'demo');
  });

  testWidgets(
      'PAT dialog: an unknown PAT surfaces AuthInvalidToken on the '
      'controller', (tester) async {
    final auth = FakeAuthPort()
      ..patScript['ghp_mockup_demo_token'] = PatResponse.error(
        const AuthInvalidToken(),
      );
    addTearDown(auth.dispose);
    final storage = FakeSecureStorage();

    await tester.pumpWidget(_host(auth: auth, storage: storage));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Sign in with a token instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ghp_not_in_script');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SignInScreen)),
    );
    final async = container.read(authControllerProvider);
    expect(async.hasError, isTrue);
    expect(async.error, isA<AuthInvalidToken>());
  });
}
