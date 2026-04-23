import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/ui/screens/job_list/job_list_screen.dart';
import 'package:gitmdscribe/ui/theme/app_theme.dart';
import 'package:gitmdscribe/ui/theme/tokens.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');

Widget _host({
  required FakeFileSystem fs,
  String? workdir,
  RepoRef? repo,
}) {
  return ProviderScope(
    overrides: [
      fileSystemProvider.overrideWithValue(fs),
      if (workdir != null) currentWorkdirProvider.overrideWith((_) => workdir),
      if (repo != null) currentRepoProvider.overrideWith((_) => repo),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: const Scaffold(body: JobListScreen()),
    ),
  );
}

/// The production layout targets a 10" tablet in landscape; the default
/// flutter_test surface (800×600) is narrow enough to overflow the top
/// chrome row. Widen the surface so layout matches the real device.
const Size _landscape = Size(1280, 800);

Future<void> _resize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_landscape);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets(
      'empty state: no workdir/repo → renders "No repo selected" muted text',
      (tester) async {
    await _resize(tester);
    await tester.pumpWidget(_host(fs: FakeFileSystem()));
    // Let the AsyncNotifier.build resolve synchronously — the empty path
    // returns before any await on the filesystem.
    await tester.pump();
    await tester.pump();
    expect(find.text('No repo selected'), findsOneWidget);
  });

  testWidgets(
      'loaded state: seeded FakeFileSystem surfaces the jobId in the '
      'rendered tree', (tester) async {
    await _resize(tester);
    final fs = FakeFileSystem()
      ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', '# foo');

    await tester.pumpWidget(
      _host(fs: fs, workdir: '/repo', repo: _repo),
    );
    // listOpenJobs is async; pump until settled so the controller lands
    // in JobListLoaded.
    await tester.pumpAndSettle();

    expect(find.text('spec-foo'), findsOneWidget);
  });

  testWidgets(
      'left-rail "Changelog" button pushes the cross-job timeline',
      (tester) async {
    await _resize(tester);
    final fs = FakeFileSystem()
      ..seedFile(
        '/repo/jobs/pending/spec-foo/02-spec.md',
        '# foo\n\n## Changelog\n\n'
            '- 2026-04-20 10:00 desktop: first entry\n',
      );

    await tester.pumpWidget(
      _host(fs: fs, workdir: '/repo', repo: _repo),
    );
    await tester.pumpAndSettle();

    // Tap the new left-rail button.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Changelog'));
    await tester.pumpAndSettle();

    // ChangelogViewer renders its chrome + the seeded entry.
    expect(find.text('changelog'), findsOneWidget);
    expect(find.text('first entry'), findsOneWidget);
  });
}
