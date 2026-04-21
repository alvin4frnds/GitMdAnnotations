import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_identity_codec.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/review_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/sync_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_png_flattener.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/secure_storage_port.dart';
import 'package:gitmdannotations_tablet/domain/services/open_question_extractor.dart';
import 'package:gitmdannotations_tablet/ui/screens/review_panel/review_panel_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';

const _repo = RepoRef(owner: 'acme', name: 'widgets');
final _job = JobRef(repo: _repo, jobId: 'spec-a');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
final _t0 = DateTime.utc(2026, 4, 20, 9, 14, 22);

const _specPath = '/workdir/jobs/pending/spec-a/02-spec.md';
const _specContents = '# Spec\n\n## Open questions\n\n### Q1: Why?\n';

void main() {
  testWidgets(
    'typing Q1, tapping Submit review, confirming in the modal commits to '
    'claude-jobs',
    (tester) async {
      // -- Fakes --------------------------------------------------------
      final fs = FakeFileSystem()..seedFile(_specPath, _specContents);
      final git = FakeGitPort(
        initial: {'claude-jobs': <String, String>{}},
      );
      final clock = FakeClock(_t0);
      final png = FakePngFlattener();
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.authToken, 'tok-123');
      await storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );
      final auth = FakeAuthPort()..storedSession = null;
      addTearDown(auth.dispose);

      // -- Host widget --------------------------------------------------
      final questions = const OpenQuestionExtractor().extract(_specContents);
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemProvider.overrideWithValue(fs),
            gitPortProvider.overrideWithValue(git),
            clockProvider.overrideWithValue(clock),
            idGeneratorProvider.overrideWithValue(FakeIdGenerator()),
            pngFlattenerProvider.overrideWithValue(png),
            authPortProvider.overrideWithValue(auth),
            secureStorageProvider.overrideWithValue(storage),
            currentWorkdirProvider.overrideWith((_) => '/workdir'),
            currentRepoProvider.overrideWith((_) => _repo),
          ],
          child: MaterialApp(
            theme: AppTheme.build(AppTokens.light),
            home: Scaffold(
              body: ReviewPanelScreen(jobRef: _job, questions: questions),
            ),
          ),
        ),
      );
      // Let the AsyncNotifier.build() chain (auth + review) settle.
      await tester.pumpAndSettle();

      // -- Interact -----------------------------------------------------
      // Type into Q1's text field.
      final answerField = find.byType(TextField).first;
      await tester.enterText(answerField, 'because reasons');
      await tester.pumpAndSettle();

      // Tap the Submit review button in the chrome bar.
      await tester.tap(find.text('Submit review'));
      await tester.pumpAndSettle();

      // Modal must be on screen — its primary button is "Submit & commit".
      expect(find.text('Submit & commit'), findsOneWidget);

      // Tap the primary modal button — routes through
      // ReviewController.submit → ReviewSubmitter → FakeGitPort.commit.
      await tester.tap(find.text('Submit & commit'));
      await tester.pumpAndSettle();

      // -- Assert (one assertion-family: "Submit flow produces a
      //    commit on claude-jobs") ----------------------------------------
      expect(
        git.commitLog('claude-jobs'),
        hasLength(1),
        reason:
            'Submit flow must produce exactly one commit on claude-jobs',
      );
    },
  );
}
