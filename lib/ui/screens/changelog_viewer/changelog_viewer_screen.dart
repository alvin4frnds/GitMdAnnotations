import 'package:flutter/material.dart';

import '../_placeholder.dart';

class ChangelogViewerScreen extends StatelessWidget {
  const ChangelogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) => const MockupPlaceholder(
    title: 'Changelog viewer',
    note: 'Rendered spec + parsed ## Changelog timeline.',
  );
}
