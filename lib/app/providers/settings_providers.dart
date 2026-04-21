import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/backup_export_port.dart';
import '../controllers/settings_controller.dart';

/// Binds the [BackupExportPort] implementation at composition root.
/// Tests override via
/// `ProviderContainer(overrides: [backupExportPortProvider.overrideWithValue(fake)])`.
/// `bootstrap.dart` wires the production
/// [SharedStorageBackupExportAdapter].
final backupExportPortProvider = Provider<BackupExportPort>((ref) {
  throw UnimplementedError(
    'backupExportPortProvider must be overridden at composition root',
  );
});

/// Top-level settings-screen state surfaced to the UI. See
/// [SettingsController].
final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
