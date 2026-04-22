import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/backup_export_port.dart';
import '../last_session.dart';
import '../providers/auth_providers.dart';
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

/// A "clear all local copies" wipe is in flight. UI disables the row
/// and shows a spinner until a terminal state lands.
class SettingsClearing extends SettingsState {
  const SettingsClearing();
}

/// Terminal success for the clear-all action. Cloned workdirs and
/// drafts have been removed; the in-memory repo/workdir providers and
/// the `lastOpened*` secure-storage keys were also reset so the UI
/// falls back to RepoPicker on the next frame.
class SettingsClearDone extends SettingsState {
  const SettingsClearDone();
}

/// Terminal failure for the clear-all action. Partial progress (e.g.
/// `repos/` removed but `drafts/` failed) is possible — we keep the
/// repo/workdir pointer intact so the user can retry without losing
/// their selection.
class SettingsClearFailed extends SettingsState {
  const SettingsClearFailed(this.message);
  final String message;
}

/// Wires [BackupExportPort] into a Riverpod `AsyncNotifier`. Intents:
///   * [exportBackups] — kicks off the SAF export flow against
///     `$workdir/.gitmdscribe-backups`.
///   * [clearAllLocal] — wipes every cloned repo + review draft under
///     the app's docs directory and drops the persisted last-session
///     pointer. The user stays signed in.
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

  /// Deletes `<appDocs>/repos` and `<appDocs>/drafts` recursively,
  /// clears the `lastOpened*` secure-storage keys, and resets the
  /// in-memory repo/workdir providers so `_AuthGate` routes back to
  /// RepoPicker on the next frame. Auth state is intentionally
  /// untouched — use sign-out for that.
  ///
  /// Double-tap safe: a second call while [SettingsClearing] is in
  /// flight is a no-op.
  Future<void> clearAllLocal() async {
    if (state.value is SettingsClearing) return;
    state = const AsyncValue.data(SettingsClearing());
    try {
      final fs = ref.read(fileSystemProvider);
      final reposRoot = await fs.appDocsPath('repos');
      final draftsRoot = await fs.appDocsPath('drafts');
      await fs.remove(reposRoot);
      await fs.remove(draftsRoot);
      await clearLastSession(ref.read(secureStorageProvider));
      ref.read(currentRepoProvider.notifier).state = null;
      ref.read(currentWorkdirProvider.notifier).state = null;
      state = const AsyncValue.data(SettingsClearDone());
    } on Object catch (e) {
      state = AsyncValue.data(SettingsClearFailed(e.toString()));
    }
  }
}
