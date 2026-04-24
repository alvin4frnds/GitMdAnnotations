import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../domain/entities/job_ref.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Screen 4c — standalone SVG viewer (spec-002 Milestone A). Read-only:
/// no Annotate, no Submit, no stroke overlay. SVG is declared
/// non-annotatable in [SourceKind]; [CommitPlanner] refuses any strokes
/// with an SVG source.
///
/// Two entry points:
///   * Job flow: repo has `spec.svg` under `jobs/pending/<jobId>/`; the
///     job list dispatches here with [jobRef] set.
///   * Browser flow: user tapped a standalone `.svg` in the repo browser;
///     [jobRef] is null.
class SpecReaderSvgScreen extends ConsumerWidget {
  const SpecReaderSvgScreen({
    required this.filePath,
    this.jobRef,
    super.key,
  });

  final String filePath;
  final JobRef? jobRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Container(
      color: t.surfaceBackground,
      child: Column(
        children: [
          _SvgReaderChrome(filePath: filePath, jobRef: jobRef),
          Container(height: 1, color: t.borderSubtle),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 8,
              child: Center(
                child: SvgPicture.file(
                  File(filePath),
                  placeholderBuilder: (_) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SvgReaderChrome extends StatelessWidget {
  const _SvgReaderChrome({required this.filePath, required this.jobRef});

  final String filePath;
  final JobRef? jobRef;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final basename = _basename(filePath);
    return Container(
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                jobRef == null ? '← back' : '← jobs',
                style: TextStyle(color: t.textMuted, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            jobRef?.jobId ?? basename,
            style: appMono(context, size: 13, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
