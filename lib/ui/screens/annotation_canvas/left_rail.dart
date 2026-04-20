import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Left rail for the annotation canvas — section jumper (mockup chrome) +
/// ink-layer list (display-only, seeded with the three mockup groups).
///
/// Extracted alongside `annotation_canvas_screen.dart` per IMPLEMENTATION.md
/// §2.6. Behavior unchanged from the pre-split screen; T7 wiring does not
/// touch this file.
class AnnotationLeftRail extends StatelessWidget {
  const AnnotationLeftRail({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 200,
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(label: 'On this page'),
          const SizedBox(height: 8),
          const _RailItem(label: 'Goals'),
          const _RailItem(label: 'Non-goals'),
          const _RailItem(label: 'Open questions', active: true),
          const _RailItem(label: 'File-level change plan'),
          const _RailItem(label: 'Assumptions'),
          const _RailItem(label: 'Changelog', muted: true),
          const SizedBox(height: 20),
          Container(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          const _RailHeader(label: 'Ink layers'),
          const SizedBox(height: 8),
          _InkLayerItem(color: t.inkRed, label: 'Group A \u2014 line 47'),
          _InkLayerItem(color: t.inkBlue, label: 'Group B \u2014 line 23'),
          _InkLayerItem(color: t.inkGreen, label: 'Group C \u2014 line 89'),
        ],
      ),
    );
  }
}

class _RailHeader extends StatelessWidget {
  final String label;
  const _RailHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final bool active;
  final bool muted;
  const _RailItem({
    required this.label,
    this.active = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active
        ? t.accentPrimary
        : muted
            ? t.textMuted.withValues(alpha: 0.7)
            : t.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _InkLayerItem extends StatelessWidget {
  final Color color;
  final String label;
  const _InkLayerItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
