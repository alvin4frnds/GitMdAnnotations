import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/settings_controller.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/settings_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/backup_export_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/file_system_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/secure_storage_port.dart';

import '../../domain/fakes/fake_backup_export_port.dart';

({ProviderContainer container, FakeBackupExportPort port}) _buildContainer({
  String? workdir,
  FakeBackupExportPort? port,
}) {
  final port0 = port ?? FakeBackupExportPort();
  final container = ProviderContainer(overrides: [
    backupExportPortProvider.overrideWithValue(port0),
    if (workdir != null) currentWorkdirProvider.overrideWith((_) => workdir),
  ]);
  addTearDown(container.dispose);
  return (container: container, port: port0);
}

void main() {
  group('SettingsController.build()', () {
    test('starts in SettingsIdle', () async {
      final env = _buildContainer(workdir: '/repo');
      final state =
          await env.container.read(settingsControllerProvider.future);
      expect(state, isA<SettingsIdle>());
    });
  });

  group('SettingsController.exportBackups()', () {
    test(
        'happy path: Idle → Exporting (transient) → ExportDone with '
        r'fileCount, passes `$workdir/.gitmdscribe-backups` to the port',
        () async {
      final port = FakeBackupExportPort()..scriptOutcome(const ExportSucceeded(7));
      final env = _buildContainer(workdir: '/tmp/repo-x', port: port);
      // Drain the initial-build frame so `state.value` reads Idle.
      await env.container.read(settingsControllerProvider.future);

      // Kick off the export but don't await yet — we want to observe
      // the intermediate Exporting state the controller sets
      // synchronously before awaiting the port.
      final future = env.container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      expect(
        env.container.read(settingsControllerProvider).value,
        isA<SettingsExporting>(),
        reason: 'controller must surface Exporting before awaiting the port',
      );

      await future;
      final finalState =
          env.container.read(settingsControllerProvider).value;
      expect(finalState, isA<SettingsExportDone>());
      expect((finalState as SettingsExportDone).fileCount, 7);

      expect(port.sourcePathsReceived,
          ['/tmp/repo-x/.gitmdscribe-backups']);
    });

    test('user cancels folder picker → SettingsExportSkipped(userCancelled)',
        () async {
      final port = FakeBackupExportPort()
        ..scriptOutcome(const ExportUserCancelled());
      final env = _buildContainer(workdir: '/repo', port: port);
      await env.container.read(settingsControllerProvider.future);

      await env.container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      final state = env.container.read(settingsControllerProvider).value;
      expect(state, isA<SettingsExportSkipped>());
      expect((state as SettingsExportSkipped).reason,
          SettingsSkipReason.userCancelled);
    });

    test('no backups on disk → SettingsExportSkipped(noBackupsFound)',
        () async {
      final port = FakeBackupExportPort()
        ..scriptOutcome(const ExportNoBackupsFound());
      final env = _buildContainer(workdir: '/repo', port: port);
      await env.container.read(settingsControllerProvider.future);

      await env.container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      final state = env.container.read(settingsControllerProvider).value;
      expect(state, isA<SettingsExportSkipped>());
      expect((state as SettingsExportSkipped).reason,
          SettingsSkipReason.noBackupsFound);
    });

    test('adapter error → SettingsExportFailed with message', () async {
      final port = FakeBackupExportPort()
        ..scriptOutcome(const ExportFailed('SAF threw PlatformException'));
      final env = _buildContainer(workdir: '/repo', port: port);
      await env.container.read(settingsControllerProvider.future);

      await env.container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      final state = env.container.read(settingsControllerProvider).value;
      expect(state, isA<SettingsExportFailed>());
      expect((state as SettingsExportFailed).message,
          contains('PlatformException'));
    });

    test(
        'no workdir → SettingsExportSkipped(noWorkdir); port is NOT called',
        () async {
      final port = FakeBackupExportPort();
      final env = _buildContainer(port: port); // no workdir override
      await env.container.read(settingsControllerProvider.future);

      await env.container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      final state = env.container.read(settingsControllerProvider).value;
      expect(state, isA<SettingsExportSkipped>());
      expect((state as SettingsExportSkipped).reason,
          SettingsSkipReason.noWorkdir);
      expect(port.sourcePathsReceived, isEmpty,
          reason:
              'no workdir means no source path — port must not be hit');
    });

    test('double-tap while Exporting is a no-op (port called once)',
        () async {
      // Use a completer-wrapped port so we can observe the in-flight
      // state mid-call.
      final blocking = _BlockingBackupExportPort();
      final container = ProviderContainer(overrides: [
        backupExportPortProvider.overrideWithValue(blocking),
        currentWorkdirProvider.overrideWith((_) => '/repo'),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      final first = container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      // Mid-flight second tap. The controller should short-circuit.
      final second = container
          .read(settingsControllerProvider.notifier)
          .exportBackups();
      blocking.complete(const ExportSucceeded(1));
      await first;
      await second;

      expect(blocking.callCount, 1,
          reason: 'double-tap during Exporting must not re-invoke the port');
      final state = container.read(settingsControllerProvider).value;
      expect(state, isA<SettingsExportDone>());
    });
  });

  group('SettingsController.clearAllLocal()', () {
    test(
      'happy path: removes repos + drafts, clears lastOpened* keys, '
      'resets repo/workdir providers, ends in SettingsClearDone',
      () async {
        final fs = FakeFileSystem()
          ..seedFile('/docs/repos/demo/payments-api/README.md', 'hello')
          ..seedFile(
            '/docs/drafts/spec-1/03-review.md.draft',
            '{"answers":{},"freeFormNotes":""}',
          );
        final storage = FakeSecureStorage()
          ..writeString(SecureStorageKeys.lastOpenedRepo, 'demo|payments-api|main')
          ..writeString(SecureStorageKeys.lastOpenedWorkdir,
              '/docs/repos/demo/payments-api')
          ..writeString(SecureStorageKeys.lastOpenedJobId, 'spec-1');

        final container = ProviderContainer(overrides: [
          backupExportPortProvider.overrideWithValue(FakeBackupExportPort()),
          fileSystemProvider.overrideWithValue(fs),
          secureStorageProvider.overrideWithValue(storage),
          currentRepoProvider.overrideWith(
            (_) => const RepoRef(
              owner: 'demo',
              name: 'payments-api',
              defaultBranch: 'main',
            ),
          ),
          currentWorkdirProvider
              .overrideWith((_) => '/docs/repos/demo/payments-api'),
        ]);
        addTearDown(container.dispose);
        await container.read(settingsControllerProvider.future);

        // Kick off clear but don't await — observe the transient
        // SettingsClearing state before the awaited removes complete.
        final future = container
            .read(settingsControllerProvider.notifier)
            .clearAllLocal();
        expect(
          container.read(settingsControllerProvider).value,
          isA<SettingsClearing>(),
          reason:
              'controller must surface Clearing before awaiting removes',
        );

        await future;

        expect(
          container.read(settingsControllerProvider).value,
          isA<SettingsClearDone>(),
        );
        expect(await fs.exists('/docs/repos'), isFalse);
        expect(await fs.exists('/docs/drafts'), isFalse);
        expect(storage.snapshot.containsKey(SecureStorageKeys.lastOpenedRepo),
            isFalse);
        expect(
            storage.snapshot
                .containsKey(SecureStorageKeys.lastOpenedWorkdir),
            isFalse);
        expect(
            storage.snapshot.containsKey(SecureStorageKeys.lastOpenedJobId),
            isFalse);
        expect(container.read(currentRepoProvider), isNull);
        expect(container.read(currentWorkdirProvider), isNull);
      },
    );

    test('no repos or drafts on disk → still lands in SettingsClearDone',
        () async {
      final fs = FakeFileSystem(); // nothing seeded
      final storage = FakeSecureStorage();
      final container = ProviderContainer(overrides: [
        backupExportPortProvider.overrideWithValue(FakeBackupExportPort()),
        fileSystemProvider.overrideWithValue(fs),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      await container
          .read(settingsControllerProvider.notifier)
          .clearAllLocal();

      expect(
        container.read(settingsControllerProvider).value,
        isA<SettingsClearDone>(),
      );
    });

    test('double-tap while Clearing is a no-op (fs.remove called once)',
        () async {
      final blocking = _BlockingFileSystem();
      final container = ProviderContainer(overrides: [
        backupExportPortProvider.overrideWithValue(FakeBackupExportPort()),
        fileSystemProvider.overrideWithValue(blocking),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      final first = container
          .read(settingsControllerProvider.notifier)
          .clearAllLocal();
      final second = container
          .read(settingsControllerProvider.notifier)
          .clearAllLocal();
      blocking.complete();
      await first;
      await second;

      expect(blocking.removeCallCount, 2,
          reason:
              'single clear invokes remove twice (repos + drafts); the '
              'second tap must not enter the try/catch at all');
      expect(
        container.read(settingsControllerProvider).value,
        isA<SettingsClearDone>(),
      );
    });

    test(
      'fs throws → SettingsClearFailed with cause message; '
      'lastOpened* keys and repo/workdir providers remain intact',
      () async {
        final throwing = _ThrowingFileSystem(
          const FsIoFailure('/docs/repos', 'ENOSPC: no space left on device'),
        );
        final storage = FakeSecureStorage()
          ..writeString(SecureStorageKeys.lastOpenedRepo, 'demo|x|main')
          ..writeString(SecureStorageKeys.lastOpenedWorkdir, '/docs/repos/demo/x');
        const ref =
            RepoRef(owner: 'demo', name: 'x', defaultBranch: 'main');

        final container = ProviderContainer(overrides: [
          backupExportPortProvider.overrideWithValue(FakeBackupExportPort()),
          fileSystemProvider.overrideWithValue(throwing),
          secureStorageProvider.overrideWithValue(storage),
          currentRepoProvider.overrideWith((_) => ref),
          currentWorkdirProvider.overrideWith((_) => '/docs/repos/demo/x'),
        ]);
        addTearDown(container.dispose);
        await container.read(settingsControllerProvider.future);

        await container
            .read(settingsControllerProvider.notifier)
            .clearAllLocal();

        final state = container.read(settingsControllerProvider).value;
        expect(state, isA<SettingsClearFailed>());
        expect((state as SettingsClearFailed).message, contains('ENOSPC'));
        expect(
            storage.snapshot.containsKey(SecureStorageKeys.lastOpenedRepo),
            isTrue,
            reason: 'failed clear must not drop the session pointer');
        expect(
            storage.snapshot
                .containsKey(SecureStorageKeys.lastOpenedWorkdir),
            isTrue);
        expect(container.read(currentRepoProvider), ref);
        expect(container.read(currentWorkdirProvider),
            '/docs/repos/demo/x');
      },
    );
  });
}

/// [FileSystemPort] stub whose `remove()` future never resolves until
/// [complete] is called. Used to pin the Clearing state long enough to
/// observe a concurrent call to `clearAllLocal()`.
class _BlockingFileSystem implements FileSystemPort {
  int removeCallCount = 0;
  final Completer<void> _c = Completer<void>();

  void complete() => _c.complete();

  @override
  Future<String> appDocsPath(String sub) async => '/docs/$sub';

  @override
  Future<void> remove(String path) {
    removeCallCount++;
    return _c.future;
  }

  // --- unused by clearAllLocal() ---
  @override
  Future<bool> exists(String path) async => false;
  @override
  Future<List<FsEntry>> listDir(String dir) async => const [];
  @override
  Future<String> readString(String path) async => '';
  @override
  Future<List<int>> readBytes(String path) async => const [];
  @override
  Future<void> writeString(String path, String contents) async {}
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}
  @override
  Future<void> mkdirp(String path) async {}
}

/// [FileSystemPort] stub whose `remove()` raises [_error] on every
/// call. Used to exercise the `SettingsClearFailed` branch.
class _ThrowingFileSystem implements FileSystemPort {
  _ThrowingFileSystem(this._error);
  final FsError _error;

  @override
  Future<String> appDocsPath(String sub) async => '/docs/$sub';

  @override
  Future<void> remove(String path) async => throw _error;

  // --- unused by clearAllLocal() ---
  @override
  Future<bool> exists(String path) async => false;
  @override
  Future<List<FsEntry>> listDir(String dir) async => const [];
  @override
  Future<String> readString(String path) async => '';
  @override
  Future<List<int>> readBytes(String path) async => const [];
  @override
  Future<void> writeString(String path, String contents) async {}
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}
  @override
  Future<void> mkdirp(String path) async {}
}

/// Port whose `exportDirectory` future doesn't resolve until the test
/// calls [complete]. Used to pin the Exporting state long enough to
/// observe a concurrent call to `exportBackups()`.
class _BlockingBackupExportPort implements BackupExportPort {
  int callCount = 0;
  final Completer<ExportOutcome> _c = Completer<ExportOutcome>();

  void complete(ExportOutcome outcome) {
    _c.complete(outcome);
  }

  @override
  Future<ExportOutcome> exportDirectory({required String sourcePath}) {
    callCount++;
    return _c.future;
  }
}
