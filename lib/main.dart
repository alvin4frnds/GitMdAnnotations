import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/controllers/auth_controller.dart';
import 'app/dev_seed.dart';
import 'app/providers/auth_providers.dart';
import 'app/providers/spec_providers.dart';
import 'app/ssl_trust_store.dart';
import 'bootstrap.dart';
import 'ui/screens/job_list/job_list_screen.dart';
import 'ui/screens/repo_picker/repo_picker_screen.dart';
import 'ui/screens/sign_in/sign_in_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Must run before any HTTPS git op. Cheap — skips rewrite on warm
  // starts because the cached .pem survives in the cache dir.
  await installBundledTrustStore();
  final devSeed = await prepareDevSeed();
  runApp(buildAppScope(devSeed: devSeed, child: const _App()));
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

/// Routes between SignIn → RepoPicker → JobList based on auth + repo
/// selection state. Wrapped in [SafeArea] so no screen paints under the
/// system status bar / nav bar / display cutout. (Flutter renders
/// edge-to-edge by default on Android 15+.)
///
/// A router-driven shell replaces this when routing grows beyond three
/// states.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(authControllerProvider).value;
    final repo = ref.watch(currentRepoProvider);
    final Widget screen;
    if (data is! AuthSignedIn) {
      screen = const SignInScreen();
    } else if (repo == null) {
      screen = const RepoPickerScreen();
    } else {
      screen = const JobListScreen();
    }
    // Scaffold is required so ScaffoldMessenger.showSnackBar has a
    // descendant to render into — without it, any sync-result toast
    // throws `_scaffolds.isNotEmpty` and crashes the listener callback.
    return Scaffold(body: SafeArea(child: screen));
  }
}
