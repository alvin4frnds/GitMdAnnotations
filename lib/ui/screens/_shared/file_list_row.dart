import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Row used by submit / approve confirmation dialogs to preview a single
/// planned file write. [prefix] is `+` for new files and `~` for
/// modified files; styling matches the mockup.
class FileListRow extends StatelessWidget {
  final String prefix;
  final String name;
  final String meta;
  final bool first;

  const FileListRow({
    required this.prefix,
    required this.name,
    required this.meta,
    this.first = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isAdd = prefix == '+';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: first
              ? BorderSide.none
              : BorderSide(color: t.borderSubtle.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              prefix,
              style: appMono(
                context,
                size: 12,
                weight: FontWeight.w700,
                color: isAdd ? t.statusSuccess : t.statusWarning,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: appMono(context, size: 12, color: t.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            meta,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
