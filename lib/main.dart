import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/controllers/auth_controller.dart';
import 'app/providers/auth_providers.dart';
import 'bootstrap.dart';
import 'ui/screens/job_list/job_list_screen.dart';
import 'ui/screens/sign_in/sign_in_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(buildAppScope(child: const _App()));
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitMdScribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTokens.light),
      darkTheme: AppTheme.build(AppTokens.dark),
      home: const _AuthGate(),
    );
  }
}

/// Shows [SignInScreen] until auth settles into [AuthSignedIn], then the
/// [JobListScreen]. A router-driven shell replaces this in M1b.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(authControllerProvider).value;
    if (data is AuthSignedIn) return const JobListScreen();
    return const SignInScreen();
  }
}
