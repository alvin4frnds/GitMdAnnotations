import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
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
DeviceCodeChallenge _challenge() => DeviceCodeChallenge(
      deviceCode: 'dev_abc',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: const Duration(milliseconds: 5),
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
}
