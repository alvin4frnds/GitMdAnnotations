import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_identity_codec.dart';
import 'package:gitmdscribe/app/providers/auth_providers.dart';
import 'package:gitmdscribe/app/providers/settings_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_auth_port.dart';
import 'package:gitmdscribe/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdscribe/domain/ports/backup_export_port.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';
import 'package:gitmdscribe/ui/screens/settings/settings_screen.dart';
import 'package:gitmdscribe/ui/theme/app_theme.dart';
import 'package:gitmdscribe/ui/theme/tokens.dart';

import '../../../domain/fakes/fake_backup_export_port.dart';

const _identity = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
const _repo = RepoRef(owner: 'demo', name: 'payments-api');

Widget _host({
  required FakeBackupExportPort port,
  RepoRef? repo = _repo,
  String? workdir = '/repo',
  bool signedIn = true,
}) {
  final storage = FakeSecureStorage();
  if (signedIn) {
    storage
      ..writeString(SecureStorageKeys.authToken, 'gho_test')
      ..writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );
  }
  return ProviderScope(
    overrides: [
      backupExportPortProvider.overrideWithValue(port),
      authPortProvider.overrideWithValue(FakeAuthPort()),
      secureStorageProvider.overrideWithValue(storage),
      if (workdir != null) currentWorkdirProvider.overrideWith((_) => workdir),
      if (repo != null) currentRepoProvider.overrideWith((_) => repo),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: const SettingsScreen(),
    ),
  );
}

const Size _landscape = Size(1280, 800);

Future<void> _resize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_landscape);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets(
    'renders idle state: account, repo, and Export row with "Export" chip',
    (tester) async {
      await _resize(tester);
      final port = FakeBackupExportPort();
      await tester.pumpWidget(_host(port: port));
      await tester.pumpAndSettle();

      // Section headers + labels.
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('REPOSITORY'), findsOneWidget);
      expect(find.text('DATA'), findsOneWidget);

      // Account row shows identity; repo row shows owner/name.
      expect(find.text('Ada Lovelace <ada@example.com>'), findsOneWidget);
      expect(find.text('demo/payments-api'), findsOneWidget);

      // Export row + idle chip.
      expect(find.text('Export backups'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Export row invokes the port with the computed source path',
    (tester) async {
      await _resize(tester);
      final port = FakeBackupExportPort()
        ..scriptOutcome(const ExportSucceeded(4));
      await tester
          .pumpWidget(_host(port: port, workdir: '/workdir/repo-x'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export backups'));
      await tester.pumpAndSettle();

      expect(port.sourcePathsReceived,
          ['/workdir/repo-x/.gitmdscribe-backups']);
      // Success chip replaces "Export".
      expect(find.text('4 files'), findsOneWidget);
    },
  );
}
