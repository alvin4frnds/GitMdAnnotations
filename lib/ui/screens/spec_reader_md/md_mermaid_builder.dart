import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../widgets/mermaid_view/mermaid_view.dart';

/// flutter_markdown element builder that substitutes a [MermaidView]
/// for fenced code blocks whose language is `mermaid`. All other fenced
/// code blocks are left untouched by returning null — flutter_markdown
/// then falls back to its default `pre/code` styling.
///
/// Wire via `Markdown(builders: {'code': MdMermaidBuilder()})` (spec-002
/// Milestone C).
class MdMermaidBuilder extends MarkdownElementBuilder {
  MdMermaidBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final cls = element.attributes['class'];
    if (cls == null || !cls.contains('language-mermaid')) return null;
    final source = element.textContent.trim();
    if (source.isEmpty) return null;
    return MermaidView(source: source);
  }
}
