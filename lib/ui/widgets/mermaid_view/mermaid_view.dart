import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/providers/spec_providers.dart';
import '../../../domain/services/mermaid_cache.dart';
import '../../theme/tokens.dart';

/// Renders a Mermaid diagram (spec-002 Milestone C).
///
/// On first render of a given source, spins up a headless
/// [WebViewController] that loads a small HTML shell referencing the
/// bundled `assets/js/mermaid.min.js`, invokes `mermaid.render()`, and
/// hands the resulting SVG back via a JS channel. The SVG is cached in
/// app-docs (see [MermaidCache]) so cold re-opens of the same document
/// render from disk in one frame.
///
/// Cache-hit path skips the WebView entirely — [SvgPicture.string] is
/// used directly. Cache-miss shows a stable-height "Rendering…"
/// placeholder so scrolling doesn't jump when the SVG lands.
class MermaidView extends ConsumerStatefulWidget {
  const MermaidView({required this.source, super.key});

  /// The raw Mermaid source (e.g. `graph TD; A-->B`). Used both as the
  /// cache key (verbatim) and the payload passed to `mermaid.render()`.
  final String source;

  @override
  ConsumerState<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends ConsumerState<MermaidView> {
  String? _svg;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _svg = null;
      _error = null;
      _start();
    }
  }

  Future<void> _start() async {
    final cache = MermaidCache(fs: ref.read(fileSystemProvider));
    final cached = await cache.read(widget.source);
    if (!mounted) return;
    if (cached != null) {
      setState(() => _svg = cached);
      return;
    }
    await _renderViaWebView(cache);
  }

  Future<void> _renderViaWebView(MermaidCache cache) async {
    final completer = Completer<String>();
    final html = await _buildHtml(widget.source);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'MermaidBridge',
        onMessageReceived: (msg) {
          if (completer.isCompleted) return;
          if (msg.message.startsWith('ERR:')) {
            completer.completeError(
              StateError(msg.message.substring(4)),
            );
            return;
          }
          completer.complete(msg.message);
        },
      )
      ..loadHtmlString(html);
    // Keep a local reference so the WebView isn't GC'd while it runs
    // the render. The controller is released once the completer
    // settles.
    // ignore: unused_local_variable
    final _ = controller;
    try {
      final svg = await completer.future
          .timeout(const Duration(seconds: 15));
      await cache.write(widget.source, svg);
      if (!mounted) return;
      setState(() => _svg = svg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<String> _buildHtml(String source) async {
    final js = await rootBundle.loadString('assets/js/mermaid.min.js');
    // Pass the source as a JSON string literal so all Unicode, quotes,
    // backticks, backslashes, and `$`-expansions are handled by the
    // spec-compliant JSON encoder. Then stop the HTML parser from
    // treating a literal `</script>` inside the source as the end of
    // the surrounding <script> tag — `<\/` is the same string for JS
    // but invisible to the HTML tokenizer.
    final literal = jsonEncode(source).replaceAll('</', r'<\/');
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>body{margin:0;padding:0;background:transparent;}</style>
  <script>$js</script>
</head>
<body>
<div id="out"></div>
<script>
  (function () {
    try {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
      mermaid.render('m', $literal).then(function (result) {
        MermaidBridge.postMessage(result.svg);
      }).catch(function (err) {
        MermaidBridge.postMessage('ERR:' + (err && err.message ? err.message : String(err)));
      });
    } catch (err) {
      MermaidBridge.postMessage('ERR:' + (err && err.message ? err.message : String(err)));
    }
  })();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final svg = _svg;
    final error = _error;
    if (svg != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: t.borderSubtle),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SvgPicture.string(svg),
      );
    }
    if (error != null) {
      return _ErrorCard(message: error, source: widget.source);
    }
    return _PlaceholderCard(source: widget.source);
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      height: 120,
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Row(
        children: [
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rendering Mermaid diagram…',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.source});
  final String message;
  final String source;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.statusDanger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mermaid render failed',
            style: TextStyle(
              color: t.statusDanger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
