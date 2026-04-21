import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/ui/screens/changelog_viewer/changelog_viewer_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';

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
      home: const Scaffold(body: ChangelogViewerScreen()),
    ),
  );
}

/// Match the tablet-landscape surface size JobList widget tests use so
/// layout doesn't hit overflow clamps.
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
    // AsyncNotifier.build lands in the empty state synchronously (no
    // disk read); two pumps drain the initial-loading frame.
    await tester.pump();
    await tester.pump();
    expect(find.text('No repo selected'), findsOneWidget);
  });

  testWidgets(
      'no-entries state: seeded jobs but no changelogs → renders the '
      '"No changelog entries yet" muted text', (tester) async {
    await _resize(tester);
    final fs = FakeFileSystem()
      ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', '# foo\n');
    await tester
        .pumpWidget(_host(fs: fs, workdir: '/repo', repo: _repo));
    await tester.pumpAndSettle();
    expect(find.text('No changelog entries yet'), findsOneWidget);
  });

  testWidgets(
      'loaded state: aggregator entries render with description + jobId',
      (tester) async {
    await _resize(tester);
    final fs = FakeFileSystem()
      ..seedFile(
        '/repo/jobs/pending/spec-alpha/02-spec.md',
        '# alpha\n\n## Changelog\n\n'
            '- 2026-04-20 10:00 desktop: alpha first entry\n',
      )
      ..seedFile(
        '/repo/jobs/pending/spec-beta/02-spec.md',
        '# beta\n\n## Changelog\n\n'
            '- 2026-04-21 08:15 tablet: beta newer entry\n',
      );

    await tester
        .pumpWidget(_host(fs: fs, workdir: '/repo', repo: _repo));
    await tester.pumpAndSettle();

    // Both entries' descriptions + the jobIds are visible.
    expect(find.text('alpha first entry'), findsOneWidget);
    expect(find.text('beta newer entry'), findsOneWidget);
    expect(find.text('spec-alpha'), findsOneWidget);
    expect(find.text('spec-beta'), findsOneWidget);

    // Header chrome reports 2 entries.
    expect(find.text('2 entries'), findsOneWidget);

    // Author tags render.
    expect(find.text('tablet'), findsOneWidget);
    expect(find.text('desktop'), findsOneWidget);
  });
}
