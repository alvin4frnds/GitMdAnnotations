import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_identity_codec.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/sync_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/secure_storage_port.dart';
import 'package:gitmdannotations_tablet/ui/screens/job_list/job_list_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
final _fixedNow = DateTime.utc(2026, 4, 21, 10, 30);

Widget _host({
  required FakeFileSystem fs,
  required FakeGitPort git,
}) {
  final storage = FakeSecureStorage()
    ..writeString(SecureStorageKeys.authToken, 'gho_test')
    ..writeString(
      SecureStorageKeys.gitIdentity,
      AuthIdentityCodec.encode(_identity),
    );
  return ProviderScope(
    overrides: [
      fileSystemProvider.overrideWithValue(fs),
      gitPortProvider.overrideWithValue(git),
      authPortProvider.overrideWithValue(FakeAuthPort()),
      secureStorageProvider.overrideWithValue(storage),
      clockProvider.overrideWithValue(FakeClock(_fixedNow)),
      currentWorkdirProvider.overrideWith((_) => '/repo'),
      currentRepoProvider.overrideWith((_) => _repo),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: const Scaffold(body: JobListScreen()),
    ),
  );
}

const Size _landscape = Size(1280, 800);

Future<void> _resize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_landscape);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('"New spec" opens repo browser; converting a .md commits to '
      'claude-jobs and the list refreshes', (tester) async {
    await _resize(tester);
    final fs = FakeFileSystem()
      ..seedFile('/repo/docs/feature.md', '# Feature\n\nbody\n');
    final git = FakeGitPort();

    await tester.pumpWidget(_host(fs: fs, git: git));
    await tester.pumpAndSettle();

    // List is empty before import.
    expect(find.text('No jobs'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'New spec'));
    await tester.pumpAndSettle();

    // Browser chrome visible; docs/ folder surfaces at root.
    expect(find.text('pick a .md or .pdf to convert'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);

    // Navigate into docs/ and trigger Convert.
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(find.text('feature.md'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Convert to spec'));
    await tester.pumpAndSettle();

    // Commit landed on claude-jobs at the expected path with the
    // expected message, carrying the signed-in identity.
    expect(
      git.branches['claude-jobs']!.keys,
      contains('jobs/pending/spec-feature/02-spec.md'),
    );
    expect(
      git.commitLog('claude-jobs').single.message,
      'Import docs/feature.md as spec-feature',
    );
    expect(git.commitLog('claude-jobs').single.identity, _identity);

    // Browser popped; a success SnackBar fired on the underlying JobList.
    expect(find.text('pick a .md or .pdf to convert'), findsNothing);
    expect(find.text('Imported spec-feature'), findsOneWidget);
  });

  testWidgets('"New spec" is disabled when no repo is picked', (tester) async {
    await _resize(tester);
    final storage = FakeSecureStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileSystemProvider.overrideWithValue(FakeFileSystem()),
          gitPortProvider.overrideWithValue(FakeGitPort()),
          authPortProvider.overrideWithValue(FakeAuthPort()),
          secureStorageProvider.overrideWithValue(storage),
          clockProvider.overrideWithValue(FakeClock(_fixedNow)),
        ],
        child: MaterialApp(
          theme: AppTheme.build(AppTokens.light),
          home: const Scaffold(body: JobListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'New spec'),
    );
    expect(btn.onPressed, isNull);
  });
}
