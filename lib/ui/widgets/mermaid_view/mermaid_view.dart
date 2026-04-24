import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, Factory, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/providers/spec_providers.dart';
import '../../../domain/services/mermaid_cache.dart';
import '../../theme/tokens.dart';

/// Renders a Mermaid diagram inline via a sized [WebViewWidget]
/// (spec-002 Milestone C).
///
/// Why WebView over flutter_svg: Mermaid emits `<foreignObject>` (HTML
/// labels inside SVG), `<marker>` (arrowheads), and embedded `<style>`
/// CSS — none of which flutter_svg supports. Rendering via the same
/// browser engine the mermaid.js library was written for is the only
/// way to get pixel-perfect fidelity with desktop tools.
///
/// Flow:
///   1. Build an HTML page with the bundled mermaid.min.js + the
///      source (or the pre-rendered SVG from cache).
///   2. Load into a WebView.
///   3. After render, JS measures the SVG bbox and posts `{w, h}` back
///      via [MermaidBridge].
///   4. Flutter sets the WebView's height to match the natural
///      aspect ratio at parent width. Parent scroll is preserved by
///      swallowing vertical drags before the WebView sees them.
class MermaidView extends ConsumerStatefulWidget {
  const MermaidView({required this.source, super.key});

  /// The raw Mermaid source. Used both as the cache key and the
  /// payload rendered into the HTML page.
  final String source;

  @override
  ConsumerState<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends ConsumerState<MermaidView> {
  WebViewController? _controller;
  double? _naturalWidth;
  double? _naturalHeight;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      setState(() {
        _controller = null;
        _naturalWidth = null;
        _naturalHeight = null;
        _error = null;
        _ready = false;
      });
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final cache = MermaidCache(fs: ref.read(fileSystemProvider));
    final cached = await cache.read(widget.source);
    if (!mounted) return;

    final html = cached != null
        ? await _buildSvgOnlyHtml(cached)
        : await _buildRenderHtml(widget.source);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'MermaidBridge',
        onMessageReceived: (msg) => _onBridgeMessage(msg, cache, cached != null),
      )
      ..loadHtmlString(html);

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  void _onBridgeMessage(
    JavaScriptMessage msg,
    MermaidCache cache,
    bool wasCacheHit,
  ) {
    if (!mounted) return;
    final payload = msg.message;
    if (payload.startsWith('ERR:')) {
      setState(() => _error = payload.substring(4));
      return;
    }
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final svg = (decoded['svg'] as String?) ?? '';
      final w = (decoded['w'] as num?)?.toDouble() ?? 0.0;
      final h = (decoded['h'] as num?)?.toDouble() ?? 0.0;
      if (w <= 0 || h <= 0) {
        setState(() => _error = 'Mermaid returned zero-sized output');
        return;
      }
      // On a cold render, persist the SVG so the next open is a hit.
      if (!wasCacheHit && svg.isNotEmpty) {
        // Fire-and-forget; best-effort cache.
        // ignore: unawaited_futures
        cache.write(widget.source, svg);
      }
      setState(() {
        _naturalWidth = w;
        _naturalHeight = h;
        _ready = true;
      });
    } on FormatException {
      setState(() => _error = 'Mermaid bridge payload malformed: $payload');
    }
  }

  /// Full-fat renderer: loads mermaid.min.js, renders the source, then
  /// measures the SVG bbox and reports {svg, w, h} back to Flutter.
  Future<String> _buildRenderHtml(String source) async {
    final js = await rootBundle.loadString('assets/js/mermaid.min.js');
    final literal = jsonEncode(source).replaceAll('</', r'<\/');
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>$_pageCss</style>
  <script>$js</script>
</head>
<body>
<div id="out"></div>
<script>
  (function () {
    try {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'dark' });
      mermaid.render('m', $literal).then(function (result) {
        var host = document.getElementById('out');
        host.innerHTML = result.svg;
        ${_measureAndReportJs(reportSvg: true)}
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

  /// Cache-hit renderer: no mermaid.min.js load, just injects the
  /// already-rendered SVG and measures/reports its natural size.
  Future<String> _buildSvgOnlyHtml(String svg) async {
    // The cached SVG might itself contain `</script>` inside CDATA; the
    // JSON-encode + `</\/` swap handles it.
    final literal = jsonEncode(svg).replaceAll('</', r'<\/');
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>$_pageCss</style>
</head>
<body>
<div id="out"></div>
<script>
  (function () {
    try {
      var host = document.getElementById('out');
      host.innerHTML = $literal;
      ${_measureAndReportJs(reportSvg: false)}
    } catch (err) {
      MermaidBridge.postMessage('ERR:' + (err && err.message ? err.message : String(err)));
    }
  })();
</script>
</body>
</html>
''';
  }

  /// CSS shared by both render-HTML variants. Keeps the page flush to
  /// the WebView bounds, sets a transparent background (so the Flutter
  /// surface color shows through), and stretches the SVG to full width.
  static const String _pageCss = '''
html, body { margin: 0; padding: 0; background: transparent; }
body { color: #E5E7EB; font-family: -apple-system, Segoe UI, Roboto, sans-serif; }
#out { width: 100%; }
#out svg { width: 100% !important; height: auto !important; display: block; }
''';

  /// JS that measures the SVG bbox in the document and posts back to
  /// Flutter. When [reportSvg] is true, the SVG's outerHTML is also
  /// included so Flutter can persist it to the cache.
  static String _measureAndReportJs({required bool reportSvg}) {
    return '''
        var svgEl = document.querySelector('#out svg');
        if (!svgEl) {
          MermaidBridge.postMessage('ERR:no svg produced');
          return;
        }
        // Prefer the intrinsic viewBox — width/height attrs may be
        // percentages after the CSS rule above stretches the svg.
        var vb = svgEl.viewBox && svgEl.viewBox.baseVal;
        var w = (vb && vb.width) || svgEl.getBoundingClientRect().width;
        var h = (vb && vb.height) || svgEl.getBoundingClientRect().height;
        var payload = { w: w, h: h ${reportSvg ? ", svg: svgEl.outerHTML" : ""} };
        MermaidBridge.postMessage(JSON.stringify(payload));
''';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (_error != null) {
      return _ErrorCard(message: _error!);
    }
    final controller = _controller;
    if (controller == null) {
      return _PlaceholderCard(title: 'Rendering Mermaid diagram…');
    }
    // Build on LayoutBuilder to know the parent's available width, so
    // we can hand the WebView a height that preserves the diagram's
    // natural aspect ratio at that width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final nw = _naturalWidth;
        final nh = _naturalHeight;
        // Fallback height until the JS bbox bounces back.
        final computedHeight = (nw != null && nh != null && nw > 0)
            ? constraints.maxWidth * (nh / nw)
            : 160.0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: t.borderSubtle),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            height: computedHeight,
            child: Stack(
              children: [
                // Swallow vertical drag gestures before the WebView sees
                // them, so the outer Markdown ListView can scroll freely
                // across the diagram. Taps still reach the WebView for
                // future interactivity (panning/zooming handled inside
                // the diagram can be wired up as needed).
                WebViewWidget(
                  controller: controller,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<VerticalDragGestureRecognizer>(
                      VerticalDragGestureRecognizer.new,
                    ),
                  },
                ),
                if (!_ready)
                  Positioned.fill(
                    child: Container(
                      color: t.surfaceSunken.withValues(alpha: 0.8),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Silence unused-on-non-android analyzer in case webview_flutter
  // pulls in platform-specific types.
  // ignore: unused_element
  static TargetPlatform get _platform => defaultTargetPlatform;
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.title});
  final String title;

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
              title,
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
  const _ErrorCard({required this.message});
  final String message;

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
