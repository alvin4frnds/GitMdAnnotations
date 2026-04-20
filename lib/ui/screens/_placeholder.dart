import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shared placeholder for screens not yet implemented in the UI spike.
class MockupPlaceholder extends StatelessWidget {
  final String title;
  final String? note;
  const MockupPlaceholder({super.key, required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceBackground,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pending_outlined, size: 32, color: t.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            note ?? 'Placeholder — wiring in progress.',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
