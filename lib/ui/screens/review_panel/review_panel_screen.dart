import 'package:flutter/material.dart';

import '../_placeholder.dart';

class ReviewPanelScreen extends StatelessWidget {
  const ReviewPanelScreen({super.key});

  @override
  Widget build(BuildContext context) => const MockupPlaceholder(
    title: 'Review panel',
    note: 'Typed answers auto-saved every 3s; draft → 03-review.md on submit.',
  );
}
