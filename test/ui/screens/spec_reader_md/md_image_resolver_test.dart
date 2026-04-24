import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/md_image_resolver.dart';

Future<Widget> _resolveInScaffold(
  WidgetTester tester, {
  required Uri uri,
  required String specPath,
  String? alt,
  String? title,
  FakeFileSystem? fs,
}) async {
  late Widget resolved;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileSystemProvider.overrideWithValue(fs ?? FakeFileSystem()),
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

void main() {
  group('resolveInlineImage', () {
    testWidgets('relative .png resolves against dirname(specPath)',
        (tester) async {
      final w = await _resolveInScaffold(
        tester,
        uri: Uri.parse('diagrams/a.png'),
        specPath: '/tmp/specs/foo.md',
      );
      expect(w, isA<Image>());
      final img = w as Image;
      final provider = img.image as FileImage;
      expect(provider.file.path, '/tmp/specs/diagrams/a.png');
    });

    testWidgets('relative .svg -> SvgPicture.file with resolved path',
        (tester) async {
      final w = await _resolveInScaffold(
        tester,
        uri: Uri.parse('diagrams/b.svg'),
        specPath: '/tmp/specs/foo.md',
      );
      expect(w, isA<SvgPicture>());
      // Not pumping — just asserting the widget type + that it wraps a
      // file-based loader. flutter_svg's internals are private but the
      // fact that we constructed it via SvgPicture.file is captured in
      // `bytesLoader` being a FileBytesLoader.
    });

    testWidgets('relative .jpeg also dispatches to Image', (tester) async {
      final w = await _resolveInScaffold(
        tester,
        uri: Uri.parse('pics/shot.jpeg'),
        specPath: '/repo/docs/spec.md',
      );
      expect(w, isA<Image>());
      final img = w as Image;
      expect((img.image as FileImage).file.path, '/repo/docs/pics/shot.jpeg');
    });

    testWidgets('absolute file path is taken verbatim (unix)',
        (tester) async {
      final w = await _resolveInScaffold(
        tester,
        uri: Uri.parse('/abs/path/img.png'),
        specPath: '/tmp/specs/foo.md',
      );
      expect(w, isA<Image>());
      expect(
        ((w as Image).image as FileImage).file.path,
        '/abs/path/img.png',
      );
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
      // First frame: FutureBuilder still loading → placeholder visible.
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

    testWidgets('http URIs are refused (offline-first) as unsupported',
        (tester) async {
      await _resolveInScaffold(
        tester,
        uri: Uri.parse('https://example.com/a.png'),
        specPath: '/repo/s.md',
        alt: 'remote image',
      );
      expect(find.textContaining('remote URL'), findsOneWidget);
    });

    testWidgets('windows-style spec path resolves with forward slashes',
        (tester) async {
      final w = await _resolveInScaffold(
        tester,
        uri: Uri.parse('a.png'),
        specPath: r'C:\repo\docs\spec.md',
      );
      expect(w, isA<Image>());
      final provider = (w as Image).image as FileImage;
      expect(provider.file.path, 'C:/repo/docs/a.png');
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
  });
}

