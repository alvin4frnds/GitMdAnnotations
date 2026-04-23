import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/ui/theme/app_theme.dart';
import 'package:gitmdscribe/ui/theme/tokens.dart';

/// Pins the bundled-font resolution introduced when Issues.md:21-26 closed.
/// Body text resolves to Inter; monospace call-sites resolve to
/// JetBrainsMono. Regressing either sends the app back to Roboto fallback
/// and the squiggly-underline artifacts on every JobList / SpecReader
/// header return.
void main() {
  test('AppTheme.build wires Inter into textTheme.bodyMedium', () {
    final theme = AppTheme.build(AppTokens.light);
    expect(theme.textTheme.bodyMedium?.fontFamily, equals('Inter'));
    expect(theme.textTheme.titleLarge?.fontFamily, equals('Inter'));
  });

  test('AppTheme.build (dark) also wires Inter', () {
    final theme = AppTheme.build(AppTokens.dark);
    expect(theme.textTheme.bodyMedium?.fontFamily, equals('Inter'));
  });

  testWidgets('appMono returns a TextStyle with JetBrainsMono family',
      (tester) async {
    late TextStyle captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppTokens.light),
        home: Builder(
          builder: (context) {
            captured = appMono(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.fontFamily, equals('JetBrainsMono'));
  });

  testWidgets('appMono respects size + weight overrides', (tester) async {
    late TextStyle captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppTokens.light),
        home: Builder(
          builder: (context) {
            captured = appMono(context, size: 14, weight: FontWeight.w600);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.fontFamily, equals('JetBrainsMono'));
    expect(captured.fontSize, equals(14));
    expect(captured.fontWeight, equals(FontWeight.w600));
  });
}
