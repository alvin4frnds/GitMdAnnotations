import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/settings_controller.dart';
import 'package:gitmdannotations_tablet/app/providers/settings_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/domain/ports/backup_export_port.dart';

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
