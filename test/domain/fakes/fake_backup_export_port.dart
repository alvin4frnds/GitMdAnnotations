import 'package:gitmdscribe/domain/ports/backup_export_port.dart';

/// Scriptable in-memory [BackupExportPort] for [SettingsController] +
/// UI tests. Follows the same pattern as `FakeGitHubReposPort` in
/// `lib/domain/fakes/` — intent here is test-only (the real app never
/// constructs this) so it lives under `test/` not `lib/`.
///
/// Default behavior: returns [ExportSucceeded] with the seeded
/// [fileCount]. Tests arm a different outcome via [scriptOutcome] to
/// exercise the other branches (user-cancel, no-backups, error).
class FakeBackupExportPort implements BackupExportPort {
  FakeBackupExportPort({int fileCount = 3}) : _nextOutcome = ExportSucceeded(fileCount);

  ExportOutcome _nextOutcome;

  /// Every `sourcePath` seen by [exportDirectory], in call order. Lets
  /// tests assert the controller built the `$workdir/.gitmdscribe-backups`
  /// path correctly.
  final List<String> sourcePathsReceived = [];

  /// Arms the next [exportDirectory] call to return [outcome]. Persists
  /// across calls until replaced — unlike the one-shot `scriptError`
  /// pattern in `FakeGitHubReposPort`, export flows tend to be terminal
  /// (user re-navigates to Settings after each attempt) so sticky
  /// scripting matches real-world usage.
  void scriptOutcome(ExportOutcome outcome) {
    _nextOutcome = outcome;
  }

  @override
  Future<ExportOutcome> exportDirectory({required String sourcePath}) async {
    sourcePathsReceived.add(sourcePath);
    return _nextOutcome;
  }
}
