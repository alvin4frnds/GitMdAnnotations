import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/providers/image_cache_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/ports/image_fetcher_port.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/md_image_resolver.dart';

class _NeverFetcher implements ImageFetcher {
  // Never completes — keeps the resolver in its skeleton state so the
  // test can read the pinned-height layout contract.
  final Completer<Uint8List> _never = Completer<Uint8List>();

  @override
  Future<Uint8List> fetch(Uri url) => _never.future;
}

/// Spec-004 regression coverage: a `MarkdownBody(shrinkWrap: true)`
/// containing an inline image must render to non-zero height on the
/// first frame, even before the image bytes decode. Without the
/// stable-height skeleton card the row collapses to zero on the
/// annotation canvas / review pane and reads as "no image."
void main() {
  testWidgets(
    'MarkdownBody with an inline file image renders non-zero height on '
    'the first frame (skeleton card holds the layout)',
    (tester) async {
      final fs = FakeFileSystem();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemProvider.overrideWithValue(fs),
            imageFetcherProvider.overrideWithValue(_NeverFetcher()),
            imageCacheDirOverrideProvider
                .overrideWithValue('/tmp/image-cache'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                child: SingleChildScrollView(
                  child: Builder(
                    builder: (ctx) => MarkdownBody(
                      data: '![alt](foo.png)\n',
                      shrinkWrap: true,
                      sizedImageBuilder: (config) => resolveInlineImage(
                        uri: config.uri,
                        specPath: '/repo/jobs/pending/spec-x/02-spec.md',
                        context: ctx,
                        title: config.title,
                        alt: config.alt,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Loading image…'), findsOneWidget);
      final markdownSize = tester.getSize(find.byType(MarkdownBody));
      expect(markdownSize.height, greaterThan(120),
          reason: 'shrink-wrapped MarkdownBody must keep image-row height '
              'while bytes decode (spec-004 §1 Gap A regression)');
    },
  );

  testWidgets(
    'MarkdownBody with an inline https image renders non-zero height on '
    'the first frame (network skeleton holds the layout)',
    (tester) async {
      final fs = FakeFileSystem();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemProvider.overrideWithValue(fs),
            imageFetcherProvider.overrideWithValue(_NeverFetcher()),
            imageCacheDirOverrideProvider
                .overrideWithValue('/tmp/image-cache'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                child: SingleChildScrollView(
                  child: Builder(
                    builder: (ctx) => MarkdownBody(
                      data: '![remote](https://example.com/y.png)\n',
                      shrinkWrap: true,
                      sizedImageBuilder: (config) => resolveInlineImage(
                        uri: config.uri,
                        specPath: '/repo/jobs/pending/spec-x/02-spec.md',
                        context: ctx,
                        title: config.title,
                        alt: config.alt,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Loading image…'), findsOneWidget);
      final markdownSize = tester.getSize(find.byType(MarkdownBody));
      expect(markdownSize.height, greaterThan(120));
    },
  );
}
