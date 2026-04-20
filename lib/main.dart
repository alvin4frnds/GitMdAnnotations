import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/mockup_browser/mockup_browser_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MockupBrowserApp());
}
