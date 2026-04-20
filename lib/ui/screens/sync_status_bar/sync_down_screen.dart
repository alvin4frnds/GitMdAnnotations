import 'package:flutter/material.dart';

import '../_placeholder.dart';

class SyncDownScreen extends StatelessWidget {
  const SyncDownScreen({super.key});

  @override
  Widget build(BuildContext context) => const MockupPlaceholder(
    title: 'Sync Down',
    note: 'Fetch + rebase main + merge into claude-jobs (§4.6).',
  );
}
