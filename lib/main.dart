import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/controllers/auth_controller.dart';
import 'app/controllers/job_list_controller.dart';
import 'app/dev_seed.dart';
import 'app/last_session.dart';
import 'app/providers/auth_providers.dart';
import 'app/providers/spec_providers.dart';
import 'app/ssl_trust_store.dart';
import 'bootstrap.dart';
import 'infra/storage/keystore_adapter.dart';
import 'ui/screens/job_list/job_list_screen.dart';
import 'ui/screens/repo_picker/repo_picker_screen.dart';
import 'ui/screens/sign_in/sign_in_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  final tracker = ColdStartTracker();
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Must run before any HTTPS git op. Cheap — skips rewrite on warm
  // starts because the cached .pem survives in the cache dir.
  await installBundledTrustStore();
  final devSeed = await prepareDevSeed();
  // NFR-2 cold-start preload: rehydrate the last picked repo/workdir
  // from SecureStoragePort so `_AuthGate` skips RepoPicker and lands
  // directly on JobList. Failures are logged and downgraded to `null`
  // so the RepoPicker still works as a fallback.
  final lastSession = await loadLastSession(KeystoreAdapter());
  tracker.markPreload();
  runApp(buildAppScope(
    devSeed: devSeed,
    lastSession: lastSession,
    child: _App(tracker: tracker),
  ));
}

class _App extends StatelessWidget {
  const _App({required this.tracker});

  final ColdStartTracker tracker;

  @override
  Widget build(BuildContext context) {
    // First-frame timestamp for the NFR-2 budget. addPostFrameCallback
    // fires after the initial layout+paint completes — closest proxy we
    // have without a custom Window callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tracker.markFirstFrame();
    });
    return MaterialApp(
      title: 'GitMdScribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTokens.light),
      darkTheme: AppTheme.build(AppTokens.dark),
      home: _AuthGate(tracker: tracker),
    );
  }
}

/// Routes between SignIn → RepoPicker → JobList based on auth + repo
/// selection state. Wrapped in [SafeArea] so no screen paints under the
/// system status bar / nav bar / display cutout. (Flutter renders
/// edge-to-edge by default on Android 15+.)
///
/// Also owns two cross-cutting listeners tied to NFR-2 cold-start:
///
/// - clears all three `session.last_*` keys when auth flips to
///   [AuthSignedOut] so a revoked-token launch lands on SignIn →
///   RepoPicker rather than restoring a stale session;
/// - fires [ColdStartTracker.markJobListVisible] the first time the
///   JobList reaches a Loaded state.
///
/// (The *write* half of the preload — persisting the picked
/// repo+workdir — lives in `RepoPickerController.pick` so the
/// controller is the single authority for "session advanced past
/// RepoPicker".)
///
/// A router-driven shell replaces this when routing grows beyond three
/// states.
class _AuthGate extends ConsumerWidget {
  const _AuthGate({required this.tracker});

  final ColdStartTracker tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Clear all session keys on sign-out so the next cold start lands
    // on SignIn → RepoPicker, not on a stale JobList backed by a
    // revoked token.
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (prev, next) {
      final wasSignedIn = prev?.value is AuthSignedIn;
      final nowSignedOut = next.value is AuthSignedOut;
      if (wasSignedIn && nowSignedOut) {
        clearLastSession(ref.read(secureStorageProvider));
      }
    });
    // Record JobList-visible for NFR-2 telemetry the first time the
    // controller lands in a Loaded state.
    ref.listen<AsyncValue<JobListState>>(jobListControllerProvider,
        (prev, next) {
      if (next.value is JobListLoaded) {
        tracker.markJobListVisible();
      }
    });

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
