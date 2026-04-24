import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../widgets/mermaid_view/mermaid_view.dart';

/// flutter_markdown element builder that substitutes a [MermaidView]
/// for fenced code blocks whose language is `mermaid`. All other fenced
/// code blocks are left untouched by returning null — flutter_markdown
/// then falls back to its default `pre/code` styling.
///
/// Registered against `pre` (the block wrapper flutter_markdown emits
/// for ` ``` ` fences — it wraps a `<code class="language-X">` child).
/// We deliberately do NOT register against `code` itself because that
/// tag also appears inline (`` `foo` ``) and promoting it to
/// [isBlockElement] there corrupts flutter_markdown's inline stack —
/// it trips a `_inlines.single` assert with "Bad state: Too many
/// elements" as soon as the document contains any inline code.
///
/// Wire via `Markdown(builders: {'pre': MdMermaidBuilder()})`.
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
    // `pre` children are the single `<code>` element emitted by the
    // fenced-code parser. Bail out if the shape is anything else —
    // flutter_markdown's default <pre> rendering takes over.
    final children = element.children;
    if (children == null || children.length != 1) return null;
    final code = children.first;
    if (code is! md.Element || code.tag != 'code') return null;
    final cls = code.attributes['class'];
    if (cls == null || !cls.contains('language-mermaid')) return null;
    final source = code.textContent.trim();
    if (source.isEmpty) return null;
    return MermaidView(source: source);
  }
}
