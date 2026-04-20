import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';

void main() {
  group('AppTokens.light — PRD §5.11.1 hex values', () {
    const tokens = AppTokens.light;

    test('surfaceBackground is #FAFAF9', () {
      expect(tokens.surfaceBackground, const Color(0xFFFAFAF9));
    });

    test('surfaceElevated is #FFFFFF', () {
      expect(tokens.surfaceElevated, const Color(0xFFFFFFFF));
    });

    test('surfaceSunken is #F3F4F6', () {
      expect(tokens.surfaceSunken, const Color(0xFFF3F4F6));
    });

    test('borderSubtle is #E5E7EB', () {
      expect(tokens.borderSubtle, const Color(0xFFE5E7EB));
    });

    test('textPrimary is #111827', () {
      expect(tokens.textPrimary, const Color(0xFF111827));
    });

    test('textMuted is #6B7280', () {
      expect(tokens.textMuted, const Color(0xFF6B7280));
    });

    test('accentPrimary is #4F46E5', () {
      expect(tokens.accentPrimary, const Color(0xFF4F46E5));
    });

    test('accentSoftBg is #EEF2FF', () {
      expect(tokens.accentSoftBg, const Color(0xFFEEF2FF));
    });

    test('statusSuccess is #059669', () {
      expect(tokens.statusSuccess, const Color(0xFF059669));
    });

    test('statusWarning is #B45309', () {
      expect(tokens.statusWarning, const Color(0xFFB45309));
    });

    test('statusDanger is #DC2626', () {
      expect(tokens.statusDanger, const Color(0xFFDC2626));
    });

    test('inkRed is #DC2626', () {
      expect(tokens.inkRed, const Color(0xFFDC2626));
    });

    test('inkBlue is #2563EB', () {
      expect(tokens.inkBlue, const Color(0xFF2563EB));
    });

    test('inkGreen is #059669', () {
      expect(tokens.inkGreen, const Color(0xFF059669));
    });

    test('inkYellowHighlight is #FEF9C3', () {
      expect(tokens.inkYellowHighlight, const Color(0xFFFEF9C3));
    });
  });

  group('AppTokens.dark — PRD §5.11.1 hex values', () {
    const tokens = AppTokens.dark;

    test('surfaceBackground is #0A0A0B', () {
      expect(tokens.surfaceBackground, const Color(0xFF0A0A0B));
    });

    test('surfaceElevated is #18181B', () {
      expect(tokens.surfaceElevated, const Color(0xFF18181B));
    });

    test('surfaceSunken is #0F0F10', () {
      expect(tokens.surfaceSunken, const Color(0xFF0F0F10));
    });

    test('borderSubtle is #27272A', () {
      expect(tokens.borderSubtle, const Color(0xFF27272A));
    });

    test('textPrimary is #F3F4F6', () {
      expect(tokens.textPrimary, const Color(0xFFF3F4F6));
    });

    test('textMuted is #A1A1AA', () {
      expect(tokens.textMuted, const Color(0xFFA1A1AA));
    });

    test('accentPrimary is #6366F1', () {
      expect(tokens.accentPrimary, const Color(0xFF6366F1));
    });

    test('accentSoftBg is rgba(99,102,241,0.15) = 0x266366F1', () {
      expect(tokens.accentSoftBg, const Color(0x266366F1));
    });

    test('statusSuccess is #6EE7B7', () {
      expect(tokens.statusSuccess, const Color(0xFF6EE7B7));
    });

    test('statusWarning is #FCD34D', () {
      expect(tokens.statusWarning, const Color(0xFFFCD34D));
    });

    test('statusDanger is #F87171', () {
      expect(tokens.statusDanger, const Color(0xFFF87171));
    });

    test('inkRed is #F87171', () {
      expect(tokens.inkRed, const Color(0xFFF87171));
    });

    test('inkBlue is #60A5FA', () {
      expect(tokens.inkBlue, const Color(0xFF60A5FA));
    });

    test('inkGreen is #34D399', () {
      expect(tokens.inkGreen, const Color(0xFF34D399));
    });

    test('inkYellowHighlight is rgba(250,204,21,0.25) = 0x40FACC15', () {
      expect(tokens.inkYellowHighlight, const Color(0x40FACC15));
    });
  });

  group('AppTokens.brightness field', () {
    test('light palette reports Brightness.light', () {
      expect(AppTokens.light.brightness, Brightness.light);
    });

    test('dark palette reports Brightness.dark', () {
      expect(AppTokens.dark.brightness, Brightness.dark);
    });
  });

  group('context.tokens extension', () {
    testWidgets(
      'returns AppTokens.light under MaterialApp with ThemeData.light()',
      (tester) async {
        late AppTokens resolved;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Builder(
              builder: (context) {
                resolved = context.tokens;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(identical(resolved, AppTokens.light), isTrue);
      },
    );

    testWidgets(
      'returns AppTokens.dark under MaterialApp with ThemeData.dark()',
      (tester) async {
        late AppTokens resolved;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) {
                resolved = context.tokens;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(identical(resolved, AppTokens.dark), isTrue);
      },
    );
  });
}
