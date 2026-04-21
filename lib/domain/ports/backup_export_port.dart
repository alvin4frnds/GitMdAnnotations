/// Abstract boundary between the settings / export feature and the
/// platform-specific Storage Access Framework implementation (M1d-T2).
///
/// The app writes local conflict-archive backups to
/// `$workdir/.gitmdscribe-backups/` (see [ConflictResolver.archiveAndReset]).
/// Those live in the app's private sandbox and are unreachable by the
/// user. This port lets the Settings screen copy the whole tree into a
/// user-visible location they pick via Android's SAF folder picker.
///
/// Kept deliberately narrow — the port takes a raw source path, returns
/// a sealed [ExportOutcome], and doesn't leak any `shared_storage`
/// types into the domain. Tests drive [FakeBackupExportPort]; production
/// wires [SharedStorageBackupExportAdapter] in `bootstrap.dart`.
abstract class BackupExportPort {
  /// Copies every file under [sourcePath] into a user-picked destination.
  ///
  /// Behavior:
  ///   * Adapters display a folder picker to the user and only begin
  ///     copying after the user confirms a destination.
  ///   * If [sourcePath] does not exist (or is empty of regular files)
  ///     the port returns [ExportNoBackupsFound] without ever showing
  ///     the picker.
  ///   * If the user cancels the folder picker, [ExportUserCancelled]
  ///     is returned and no files are written.
  ///   * On any platform error mid-copy, [ExportFailed] carries a
  ///     human-readable message.
  ///   * On success, [ExportSucceeded.fileCount] reports the number of
  ///     regular files successfully copied (directories are recreated
  ///     under the SAF tree but are not counted).
  Future<ExportOutcome> exportDirectory({required String sourcePath});
}

/// Sealed result of [BackupExportPort.exportDirectory]. UI `switch`es
/// are exhaustive — see `SettingsController`.
sealed class ExportOutcome {
  const ExportOutcome();
}

/// Every regular file under `sourcePath` was written to the SAF tree.
/// [fileCount] is zero-safe — an empty source dir still returns
/// [ExportNoBackupsFound], not an ExportSucceeded(0).
class ExportSucceeded extends ExportOutcome {
  const ExportSucceeded(this.fileCount);
  final int fileCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportSucceeded && other.fileCount == fileCount;

  @override
  int get hashCode => fileCount.hashCode;

  @override
  String toString() => 'ExportSucceeded(fileCount: $fileCount)';
}

/// User dismissed the SAF folder picker without choosing a destination.
/// Not an error — UI surfaces this as a quiet "cancelled" affordance and
/// returns to the idle state so the user can try again.
class ExportUserCancelled extends ExportOutcome {
  const ExportUserCancelled();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExportUserCancelled;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ExportUserCancelled()';
}

/// Source directory doesn't exist or contains no regular files. No
/// picker was shown. UI surfaces this as "Nothing to export yet — no
/// backups have been archived."
class ExportNoBackupsFound extends ExportOutcome {
  const ExportNoBackupsFound();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExportNoBackupsFound;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'ExportNoBackupsFound()';
}

/// Transport / platform error during copy. [message] is a human-readable
/// summary safe to show to the user. Adapters MUST NOT leak raw
/// `PlatformException` strings through this field unfiltered.
class ExportFailed extends ExportOutcome {
  const ExportFailed(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportFailed && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ExportFailed($message)';
}
