import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/providers/annotation_providers.dart';
import '../../../app/providers/review_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/ports/clock_port.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Top chrome of the review screen — mono file-name breadcrumb, live
/// "auto-saved Ns ago" caption computed from
/// [ReviewState.lastAutoSaveAt] vs the injected [Clock], and the
/// Submit Review primary action.
class ReviewChromeBar extends ConsumerWidget {
  const ReviewChromeBar({
    required this.jobRef,
    required this.onSubmit,
    super.key,
  });

  final JobRef jobRef;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(reviewControllerProvider(jobRef));
    final clock = ref.read(clockProvider);
    final caption = async.when(
      data: (s) => _autoSavedCaption(s.lastAutoSaveAt, clock.now()),
      error: (_, _) => 'auto-save: error',
      loading: () => 'loading draft...',
    );
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            '03-review.md - draft',
            style: appMono(
              context,
              size: 13,
              weight: FontWeight.w500,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            caption,
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: onSubmit,
            child: const Text('Submit review'),
          ),
        ],
      ),
    );
  }

  static String _autoSavedCaption(DateTime? lastAt, DateTime now) {
    if (lastAt == null) return 'draft not yet saved';
    final diff = now.difference(lastAt);
    if (diff.inSeconds < 1) return 'auto-saved just now';
    if (diff.inSeconds < 60) return 'auto-saved ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'auto-saved ${diff.inMinutes}m ago';
    return 'auto-saved ${diff.inHours}h ago';
  }
}
