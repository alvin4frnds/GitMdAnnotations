import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/annotation_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/anchor.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';

/// Left rail for the annotation canvas.
///
/// - **On this page**: H1/H2 headings extracted from the actual spec
///   markdown loaded via `specFileProvider(jobRef)`. Matches the
///   Spec Reader's outline logic so the two screens stay consistent.
/// - **Ink layers**: one entry per committed `StrokeGroup`, keyed on
///   anchor line number. The color dot is the first stroke's color.
///
/// Both sections fall back to a muted placeholder while the spec is
/// loading or when there's no job in scope (mockup shell surface).
class AnnotationLeftRail extends ConsumerWidget {
  const AnnotationLeftRail({this.jobRef, super.key});

  final JobRef? jobRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final headings = _headings(ref);
    final groups = _groups(ref);
    return Container(
      width: 200,
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(label: 'On this page'),
          const SizedBox(height: 8),
          if (headings.isEmpty)
            _RailPlaceholder(
              text: jobRef == null ? 'No job selected' : 'No headings',
            )
          else
            for (var i = 0; i < headings.length; i++)
              _RailItem(label: headings[i], active: i == 0),
          const SizedBox(height: 20),
          Container(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          const _RailHeader(label: 'Ink layers'),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            const _RailPlaceholder(text: 'No strokes yet')
          else
            for (var i = 0; i < groups.length; i++)
              _InkLayerItem(
                color: _colorFor(groups[i], t),
                label: _labelFor(groups[i], i + 1),
              ),
        ],
      ),
    );
  }

  List<String> _headings(WidgetRef ref) {
    final job = jobRef;
    if (job == null) return const <String>[];
    final spec = ref.watch(specFileProvider(job)).value;
    if (spec == null) return const <String>[];
    return _extractHeadings(spec.contents);
  }

  List<StrokeGroup> _groups(WidgetRef ref) {
    final job = jobRef;
    if (job == null) return const <StrokeGroup>[];
    return ref.watch(annotationControllerProvider(job)).groups;
  }

  static Color _colorFor(StrokeGroup group, AppTokens t) {
    if (group.strokes.isEmpty) return t.textMuted;
    final hex = group.strokes.first.color;
    if (hex.length != 7 || !hex.startsWith('#')) return t.textMuted;
    final v = int.tryParse(hex.substring(1), radix: 16);
    if (v == null) return t.textMuted;
    return Color(0xFF000000 | v);
  }

  static String _labelFor(StrokeGroup group, int index) {
    final tag = String.fromCharCode(0x40 + index.clamp(1, 26));
    final anchor = group.anchor;
    if (anchor is MarkdownAnchor) {
      return 'Group $tag — line ${anchor.lineNumber}';
    }
    if (anchor is PdfAnchor) {
      return 'Group $tag — p${anchor.page}';
    }
    return 'Group $tag';
  }
}

/// Parses `# ` and `## ` headings from [markdown] in document order.
/// Lines inside fenced code blocks are skipped so a `#` shell comment
/// doesn't leak into the outline. Mirrors `spec_reader_md_screen.dart`'s
/// helper — if one needs changing, the other probably does too.
List<String> _extractHeadings(String markdown) {
  final out = <String>[];
  var inFence = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = _headingPattern.firstMatch(line);
    if (m != null) {
      final text = m.group(2)?.trim() ?? '';
      if (text.isNotEmpty) out.add(text);
    }
  }
  return out;
}

final _headingPattern = RegExp(r'^(#{1,2})\s+(.+?)\s*$');

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
  const _RailItem({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          color: active ? t.accentPrimary : t.textPrimary,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _RailPlaceholder extends StatelessWidget {
  final String text;
  const _RailPlaceholder({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        text,
        style: TextStyle(
          color: t.textMuted.withValues(alpha: 0.7),
          fontSize: 12,
          fontStyle: FontStyle.italic,
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
