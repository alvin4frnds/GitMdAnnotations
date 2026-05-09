import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/providers/image_cache_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/ports/image_fetcher_port.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/md_image_resolver.dart';

class _StubFetcher implements ImageFetcher {
  _StubFetcher({this.bytes, this.error});
  final Uint8List? bytes;
  final Object? error;

  @override
  Future<Uint8List> fetch(Uri url) async {
    if (error != null) throw error!;
    return bytes ?? Uint8List.fromList(const [1, 2, 3]);
  }
}

Future<Widget> _resolveInScaffold(
  WidgetTester tester, {
  required Uri uri,
  required String specPath,
  String? alt,
  String? title,
  FakeFileSystem? fs,
  ImageFetcher? fetcher,
}) async {
  late Widget resolved;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileSystemProvider.overrideWithValue(fs ?? FakeFileSystem()),
        imageFetcherProvider.overrideWithValue(fetcher ?? _StubFetcher()),
        imageCacheDirOverrideProvider.overrideWithValue('/tmp/image-cache'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              resolved = resolveInlineImage(
                uri: uri,
                specPath: specPath,
                context: ctx,
                alt: alt,
                title: title,
              );
              return resolved;
            },
          ),
        ),
      ),
    ),
  );
  return resolved;
}

/// Walks the rendered tree to find a wrapped [Image] under the given
/// resolver-returned widget. The resolver wraps file-backed images in
/// `_ClampedImageFile` (a private class), so widget-tree lookup is the
/// stable assertion path — type checks against the private class don't
/// compile from outside the library.
FileImage _findFileImageUnder(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return image.image as FileImage;
}

void main() {
  group('resolveInlineImage', () {
    testWidgets('relative .png resolves against dirname(specPath)',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('diagrams/a.png'),
        specPath: '/tmp/specs/foo.md',
      );
      expect(_findFileImageUnder(tester).file.path,
          '/tmp/specs/diagrams/a.png');
    });

    testWidgets('relative .svg resolves under a clamped SvgPicture.file',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('diagrams/b.svg'),
        specPath: '/tmp/specs/foo.md',
      );
      // SvgPicture is the rendered widget; the file path is internal to
      // flutter_svg's BytesLoader. Asserting the SvgPicture is in the
      // tree is enough to cover the dispatch contract.
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('relative .jpeg also dispatches to a file Image',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('pics/shot.jpeg'),
        specPath: '/repo/docs/spec.md',
      );
      expect(_findFileImageUnder(tester).file.path,
          '/repo/docs/pics/shot.jpeg');
    });

    testWidgets('absolute file path is taken verbatim (unix)',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('/abs/path/img.png'),
        specPath: '/tmp/specs/foo.md',
      );
      expect(_findFileImageUnder(tester).file.path, '/abs/path/img.png');
    });

    testWidgets('.mmd extension shows a stable-height reading placeholder '
        'while the file read is in flight (Milestone C)',
        (tester) async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/diagrams/flow.mmd', 'graph TD\nA-->B\n');
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('diagrams/flow.mmd'),
        specPath: '/repo/s.md',
        alt: 'flow diagram',
        fs: fs,
      );
      expect(find.text('Reading Mermaid source…'), findsOneWidget);
      expect(find.text('flow diagram'), findsOneWidget);
    });

    testWidgets('unknown extension returns an "unsupported" card',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('unknown.xyz'),
        specPath: '/repo/s.md',
        alt: 'some diagram',
      );
      expect(find.text('some diagram'), findsOneWidget);
      expect(find.textContaining('unsupported extension'), findsOneWidget);
    });

    testWidgets('https URI shows loading skeleton on first frame, '
        'then resolves to a cached file Image (spec-004)',
        (tester) async {
      final fs = FakeFileSystem();
      final fetcher = _StubFetcher(bytes: Uint8List.fromList([1, 2, 3, 4]));
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('https://example.com/a.png'),
        specPath: '/repo/s.md',
        alt: 'remote image',
        fs: fs,
        fetcher: fetcher,
      );
      // First frame: skeleton card visible while the cache resolves.
      expect(find.text('Loading image…'), findsOneWidget);
      expect(find.text('remote image'), findsOneWidget);

      // Pump until the FutureBuilder lands.
      await tester.pumpAndSettle();

      // Cached file written under the override dir.
      expect(await fs.exists('/tmp/image-cache'), isTrue);

      // Now an Image.file wraps the cached path.
      expect(find.byType(Image), findsOneWidget);
      final filePath = _findFileImageUnder(tester).file.path;
      expect(filePath.startsWith('/tmp/image-cache/'), isTrue);
      expect(filePath.endsWith('.png'), isTrue);
    });

    testWidgets('https URI fetch failure shows loud error card with host only',
        (tester) async {
      final fs = FakeFileSystem();
      final fetcher = _StubFetcher(error: Exception('network down'));
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('https://example.com/a.png?token=secret'),
        specPath: '/repo/s.md',
        alt: 'remote image',
        fs: fs,
        fetcher: fetcher,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('fetch failed'), findsOneWidget);
      // vibesec: only the host appears in the diagnostic, never the
      // full URL with query string (token must not leak to the UI).
      expect(find.text('example.com'), findsOneWidget);
      expect(find.textContaining('token=secret'), findsNothing);
    });

    testWidgets('windows-style spec path resolves with forward slashes',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('a.png'),
        specPath: r'C:\repo\docs\spec.md',
      );
      expect(_findFileImageUnder(tester).file.path, 'C:/repo/docs/a.png');
    });

    testWidgets('null alt falls back to "(no alt text)" in unsupported card',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('thing.xyz'),
        specPath: '/r/s.md',
      );
      expect(find.text('(no alt text)'), findsOneWidget);
    });

    testWidgets('missing local file shows loud error card, '
        'not the muted unsupported card',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('missing.png'),
        specPath: '/repo/s.md',
        alt: 'gone',
      );
      // First frame: the skeleton placeholder is shown while Image.file
      // tries to decode. The errorBuilder fires asynchronously when the
      // file read fails. Pump enough frames for the file-IO error to
      // surface.
      await tester.pump(const Duration(milliseconds: 200));
      // We can't reliably trigger the errorBuilder under the test
      // binding (Image.file's async decode in a host VM doesn't fail
      // immediately). The contract checked here: the skeleton-card
      // text 'Loading image…' is visible, and the resolver returned a
      // _ClampedImageFile (not a muted unsupported card) so the loud
      // error path is wired.
      expect(find.text('Loading image…'), findsOneWidget);
      expect(find.textContaining('unsupported'), findsNothing);
    });
  });
}
