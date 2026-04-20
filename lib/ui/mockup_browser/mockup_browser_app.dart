import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'mockup_browser_shell.dart';

class MockupBrowserApp extends StatefulWidget {
  const MockupBrowserApp({super.key});

  @override
  State<MockupBrowserApp> createState() => _MockupBrowserAppState();
}

class _MockupBrowserAppState extends State<MockupBrowserApp> {
  final _themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'GitMdAnnotations — Mockup browser',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: AppTheme.build(AppTokens.light),
          darkTheme: AppTheme.build(AppTokens.dark),
          home: MockupBrowserShell(themeMode: _themeMode),
        );
      },
    );
  }
}
