import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_controller.dart';
import 'package:gitmdscribe/app/providers/annotation_providers.dart';
import 'package:gitmdscribe/app/providers/auth_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/app/providers/sync_providers.dart';
import 'package:gitmdscribe/domain/entities/auth_session.dart';
import 'package:gitmdscribe/domain/entities/commit.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_clock.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/ports/git_port.dart';
import 'package:gitmdscribe/ui/screens/repo_browser/repo_browser_screen.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');
final _session = AuthSession(
  token: 'fake',
  identity: const GitIdentity(name: 'Alice', email: 'alice@example.com'),
);

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

/// Gates every commit on a completer so a test can freeze the batch
/// mid-flight and assert the determinate progress bar (AC-5/AC-11).
class _GatedGitPort extends FakeGitPort {
  final _gate = Completer<void>();
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
    List<String> removals = const <String>[],
  }) async {
    await _gate.future;
    return super.commit(
      files: files,
      message: message,
      id: id,
      branch: branch,
      removals: removals,
    );
  }
}

FakeFileSystem _seededFs() {
  return FakeFileSystem()
    ..seedFile('/repo/notes.md', '# notes')
    ..seedFile('/repo/deck.pdf', '%PDF-1.4')
    ..seedFile('/repo/diagram.svg', '<svg/>')
    ..seedFile('/repo/subdir/inner.md', '# inner');
}

List<Override> _overrides(FakeFileSystem fs, FakeGitPort git) => [
      fileSystemProvider.overrideWithValue(fs),
      gitPortProvider.overrideWithValue(git),
      clockProvider.overrideWithValue(FakeClock(DateTime.utc(2026, 4, 21))),
      currentWorkdirProvider.overrideWith((_) => '/repo'),
      currentRepoProvider.overrideWith((_) => _repo),
      authControllerProvider
          .overrideWith(() => _StubAuthController(AuthSignedIn(_session))),
    ];

Widget _app(FakeFileSystem fs, FakeGitPort git) => ProviderScope(
      overrides: _overrides(fs, git),
      child: const MaterialApp(home: Scaffold(body: RepoBrowserScreen())),
    );

Finder _convertButton() => find.widgetWithText(ElevatedButton, 'Convert to spec');

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('checkboxes appear on convertible file rows only (AC-1)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1400));
    await tester.pumpWidget(_app(_seededFs(), FakeGitPort()));
    await tester.pumpAndSettle();

    // notes.md + deck.pdf are convertible; diagram.svg + subdir are not.
    expect(find.byType(Checkbox), findsNWidgets(2));
    // The .md and .pdf carry the single-convert button; .svg does not.
    expect(_convertButton(), findsNWidgets(2));
  });

  testWidgets('ticking a checkbox surfaces the "N selected" action bar (AC-2)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1400));
    await tester.pumpWidget(_app(_seededFs(), FakeGitPort()));
    await tester.pumpAndSettle();

    expect(find.textContaining('selected'), findsNothing);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Convert 1 selected'), findsOneWidget);
  });

  testWidgets('"Select all" ticks every convertible row then flips to Clear '
      '(AC-3)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1400));
    await tester.pumpWidget(_app(_seededFs(), FakeGitPort()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('Convert N selected shows a determinate bar and disables rows '
      '(AC-5/AC-11)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1400));
    final git = _GatedGitPort();
    await tester.pumpWidget(_app(_seededFs(), git));
    await tester.pumpAndSettle();

    // Tick one row to reveal the bar, then "Select all", then start.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert 2 selected'));
    await tester.pump(); // one frame — batch is frozen on the first commit

    // Determinate progress: value 1/2, current filename, Cancel present.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.5, 0.001));
    expect(find.textContaining('Converting 1/2'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Rows are disabled mid-batch (checkbox onChanged null).
    final cb = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(cb.onChanged, isNull);

    git.release();
    await tester.pumpAndSettle();
    // Batch finished: bar gone, selection cleared, summary shown.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Converted 2, 0 failed'), findsOneWidget);
    expect(git.commitLog('claude-jobs').length, 2);
  });

  testWidgets('single "Convert to spec" still commits and pops (AC-12)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1400));
    final fs = _seededFs();
    final git = FakeGitPort();
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(fs, git),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: RepoBrowserScreen()),
                ),
              ),
              child: const Text('open-browser'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-browser'));
    await tester.pumpAndSettle();

    expect(_convertButton(), findsNWidgets(2));
    await tester.tap(_convertButton().first);
    await tester.pumpAndSettle();

    // The browser popped on success; the parent route is visible again.
    expect(find.text('open-browser'), findsOneWidget);
    expect(find.byType(RepoBrowserScreen), findsNothing);
    expect(git.commitLog('claude-jobs').length, 1);
  });
}
