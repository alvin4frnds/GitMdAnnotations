import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/backup_export_port.dart';
import '../providers/settings_providers.dart';
import '../providers/spec_providers.dart';

/// Sealed UI-level state for the Settings screen. The Export-backups
/// row pattern-matches on this to pick the right trailing chip (idle
/// "Export", spinner, "Copied N files", error label, etc.). Mirrors the
/// shape of [RepoPickerState] / [ChangelogViewerState] so the UI has a
/// single convention for exhaustive switches.
sealed class SettingsState {
  const SettingsState();
}

/// No export in flight. Default state after the controller is built.
class SettingsIdle extends SettingsState {
  const SettingsIdle();
}

/// User tapped "Export" and we're either showing the folder picker or
/// copying files. UI disables the row + shows a spinner.
class SettingsExporting extends SettingsState {
  const SettingsExporting();
}

/// Copy finished successfully; [fileCount] files were written.
class SettingsExportDone extends SettingsState {
  const SettingsExportDone(this.fileCount);
  final int fileCount;
}

/// Exported was attempted but didn't produce backups. Used for both
/// "user cancelled" and "nothing to export" — the UI differentiates via
/// [reason] so messaging can stay quiet for user-cancel vs. informative
/// for no-backups.
class SettingsExportSkipped extends SettingsState {
  const SettingsExportSkipped(this.reason);
  final SettingsSkipReason reason;
}

/// Why a previous export attempt didn't complete. Sealed-like enum.
enum SettingsSkipReason { userCancelled, noBackupsFound, noWorkdir }

/// Terminal failure state — adapter raised an error mid-copy.
class SettingsExportFailed extends SettingsState {
  const SettingsExportFailed(this.message);
  final String message;
}

/// Wires [BackupExportPort] into a Riverpod `AsyncNotifier`. Intents:
///   * [exportBackups] — kicks off the SAF export flow against
///     `$workdir/.gitmdscribe-backups`.
class SettingsController extends AsyncNotifier<SettingsState> {
  BackupExportPort get _port => ref.read(backupExportPortProvider);

  @override
  Future<SettingsState> build() async => const SettingsIdle();

  /// Starts an export. Does nothing if a previous export is still in
  /// flight — the UI disables the button meanwhile so this is
  /// defence-in-depth against double-taps.
  Future<void> exportBackups() async {
    if (state.value is SettingsExporting) return;

    final workdir = ref.read(currentWorkdirProvider);
    if (workdir == null) {
      state = const AsyncValue.data(
        SettingsExportSkipped(SettingsSkipReason.noWorkdir),
      );
      return;
    }

    state = const AsyncValue.data(SettingsExporting());

    final source = '$workdir/.gitmdscribe-backups';
    try {
      final outcome = await _port.exportDirectory(sourcePath: source);
      state = AsyncValue.data(switch (outcome) {
        ExportSucceeded(:final fileCount) => SettingsExportDone(fileCount),
        ExportUserCancelled() =>
          const SettingsExportSkipped(SettingsSkipReason.userCancelled),
        ExportNoBackupsFound() =>
          const SettingsExportSkipped(SettingsSkipReason.noBackupsFound),
        ExportFailed(:final message) => SettingsExportFailed(message),
      });
    } on Object catch (e) {
      // Adapters shouldn't leak raw exceptions — but if one does, keep
      // the UI navigable by surfacing a failure state rather than
      // bouncing into AsyncValue.error.
      state = AsyncValue.data(SettingsExportFailed(e.toString()));
    }
  }
}
