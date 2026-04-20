import 'package:flutter/material.dart';

import '../_placeholder.dart';

class AnnotationCanvasScreen extends StatelessWidget {
  const AnnotationCanvasScreen({super.key});

  @override
  Widget build(BuildContext context) => const MockupPlaceholder(
    title: 'Annotation canvas',
    note: 'Stylus-only ink; palm rejection; SVG + PNG on stroke end.',
  );
}
