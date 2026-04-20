import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bootstrap.dart';
import 'ui/mockup_browser/mockup_browser_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Default is `mockup` so `flutter run` keeps working as the visual-QA
  // harness. Opt into real adapters with `--dart-define=APP_MODE=real`.
  const modeString =
      String.fromEnvironment('APP_MODE', defaultValue: 'mockup');
  final mode = modeString == 'real' ? AppMode.real : AppMode.mockup;
  runApp(buildAppScope(mode: mode, child: const _AppRoot()));
}

/// Root widget shared by both modes. M1a intentionally reuses the mockup
/// browser as the nav tree so the team can still flip through the 12
/// screens; SignIn + JobList are now driven by real controllers regardless
/// of mode, so `real` mode yields real OAuth + libgit2 against whatever
/// workdir / repo the picker (M1c) sets. A router-driven shell replaces
/// this in M1b.
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    return const MockupBrowserApp();
  }
}
