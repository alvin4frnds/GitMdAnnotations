import 'package:flutter/material.dart';

import '../_placeholder.dart';

class NewSpecAuthorScreen extends StatelessWidget {
  const NewSpecAuthorScreen({super.key});

  @override
  Widget build(BuildContext context) => const MockupPlaceholder(
    title: 'New spec (Phase 2)',
    note: 'Template + linter; out of Phase 1 scope but included for QA.',
  );
}
