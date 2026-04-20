import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/ui/screens/job_list/job_list_screen.dart';
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
}
