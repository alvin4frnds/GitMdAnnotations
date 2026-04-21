import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/auth_controller.dart';
import '../../../app/controllers/settings_controller.dart';
import '../../../app/last_session.dart';
import '../../../app/providers/auth_providers.dart';
import '../../../app/providers/settings_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/repo_ref.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Screen 10 — Settings (M1d-T2, IMPLEMENTATION.md §6.4).
///
/// Minimal, list-style layout: a top chrome bar with a back affordance,
/// then a column of rows. Each row is label-on-left, value-on-right. The
/// "Export backups" row is the only interactive one — tapping it kicks
/// off [SettingsController.exportBackups], which pops the Android SAF
/// folder picker and copies `$workdir/.gitmdscribe-backups/` into the
/// picked tree.
///
/// Design intent: looks like JobList's left-rail section headers rather
/// than a Material Switch/List — matches the rest of the app's muted
/// typography-first chrome. No big splashes of color; status shows up
/// as a small trailing chip.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final auth = ref.watch(authControllerProvider).value;
    final repo = ref.watch(currentRepoProvider);
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      backgroundColor: t.surfaceBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TopChrome(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                const _SectionHeader('ACCOUNT'),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Signed in as',
                  value: _authValue(auth),
                  mono: auth is AuthSignedIn,
                ),
                if (auth is AuthSignedIn) ...[
                  const SizedBox(height: 8),
                  _SignOutRow(
                    onSignOut: () => _confirmSignOut(context, ref),
                  ),
                ],
                const SizedBox(height: 24),
                const _SectionHeader('REPOSITORY'),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Repo',
                  value: _repoValue(repo),
                  mono: repo != null,
                ),
                if (repo != null) ...[
                  const SizedBox(height: 8),
                  _ChangeRepoRow(
                    onChange: () => _confirmChangeRepo(context, ref),
                  ),
                ],
                const SizedBox(height: 24),
                const _SectionHeader('DATA'),
                const SizedBox(height: 8),
                _ExportBackupsRow(async: settings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _authValue(AuthState? auth) {
    return switch (auth) {
      AuthSignedIn(:final session) =>
        '${session.identity.name} <${session.identity.email}>',
      AuthDeviceFlowAwaitingUser() => 'Signing in…',
      AuthSignedOut() => 'Not signed in',
      null => '—',
    };
  }

  static String _repoValue(RepoRef? repo) {
    if (repo == null) return 'No repository selected';
    return '${repo.owner}/${repo.name}';
  }

  Future<void> _confirmChangeRepo(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change repository?'),
        content: const Text(
          'You stay signed in. Pending local commits remain on disk under '
          "the current repo's workdir — switch back to see them again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Change repo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Drop the in-memory repo + workdir so _AuthGate re-routes to
    // RepoPicker on the next frame, and clear the persisted
    // last-session keys so the NFR-2 cold-start preload doesn't
    // silently restore the same repo on the next cold launch.
    await clearLastSession(ref.read(secureStorageProvider));
    ref.read(currentRepoProvider.notifier).state = null;
    ref.read(currentWorkdirProvider.notifier).state = null;
    if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Pending drafts and unpushed commits stay on this device. '
          'You can sign back in later to resume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }
}

// ---------------------------------------------------------------------------
// Top chrome
// ---------------------------------------------------------------------------

class _TopChrome extends StatelessWidget {
  const _TopChrome();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, size: 18, color: t.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            splashRadius: 18,
          ),
          const SizedBox(width: 4),
          Icon(Icons.settings_rounded, size: 18, color: t.textPrimary),
          const SizedBox(width: 10),
          Text(
            'Settings',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small building blocks
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label,
      style: TextStyle(
        color: t.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Row with a single Sign out affordance, styled like an `_InfoRow` so
/// it blends into the Account section. Tapping fires [onSignOut] —
/// the SettingsScreen wraps the call in a confirm dialog and pops the
/// Settings route after a successful sign-out.
class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.logout_rounded, size: 16, color: t.statusDanger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sign out',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onSignOut,
            style: TextButton.styleFrom(
              foregroundColor: t.statusDanger,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Row with a "Change repo" affordance, styled like `_SignOutRow` but
/// with the accent color — switching repo is routine, not destructive.
/// Tapping fires [onChange]; SettingsScreen wraps the call in a confirm
/// dialog then clears `currentRepoProvider` + `currentWorkdirProvider`
/// and the persisted last-session keys so `_AuthGate` re-routes to the
/// RepoPicker on the next frame.
class _ChangeRepoRow extends StatelessWidget {
  const _ChangeRepoRow({required this.onChange});
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: 16, color: t.accentPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Change repository',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: t.accentPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: t.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? appMono(context, size: 13)
                  : TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export-backups row
// ---------------------------------------------------------------------------

class _ExportBackupsRow extends ConsumerWidget {
  const _ExportBackupsRow({required this.async});
  final AsyncValue<SettingsState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = async.value ?? const SettingsIdle();
    final disabled = state is SettingsExporting;

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled
              ? null
              : () => ref
                  .read(settingsControllerProvider.notifier)
                  .exportBackups(),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.download_rounded, size: 18, color: t.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export backups',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitleFor(state),
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _TrailingChip(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _subtitleFor(SettingsState state) {
    return switch (state) {
      SettingsIdle() => 'Copy archived local snapshots to a folder you pick.',
      SettingsExporting() => 'Waiting for folder pick, then copying…',
      SettingsExportDone() =>
        'Done. Pick a new destination to export again.',
      SettingsExportSkipped(:final reason) => switch (reason) {
          SettingsSkipReason.userCancelled => 'Cancelled. Tap to try again.',
          SettingsSkipReason.noBackupsFound =>
            'No backups on device yet — nothing to export.',
          SettingsSkipReason.noWorkdir =>
            'No repository selected; pick one first.',
        },
      SettingsExportFailed(:final message) => 'Failed: $message',
    };
  }
}

class _TrailingChip extends StatelessWidget {
  const _TrailingChip({required this.state});
  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return switch (state) {
      SettingsIdle() => _Chip(
          label: 'Export',
          bg: t.accentSoftBg,
          fg: t.accentPrimary,
        ),
      SettingsExporting() => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(t.accentPrimary),
          ),
        ),
      SettingsExportDone(:final fileCount) => _Chip(
          label: '$fileCount file${fileCount == 1 ? '' : 's'}',
          bg: _softStatus(t.statusSuccess),
          fg: t.statusSuccess,
        ),
      SettingsExportSkipped() => _Chip(
          label: 'Skipped',
          bg: t.surfaceSunken,
          fg: t.textMuted,
        ),
      SettingsExportFailed() => _Chip(
          label: 'Error',
          bg: _softStatus(t.statusDanger),
          fg: t.statusDanger,
        ),
    };
  }

  /// Builds a light tint behind a strong status color. Riverpod's theme
  /// already provides [AppTokens.accentSoftBg] for primary, but tokens
  /// don't include soft variants for success/danger — derive by alpha.
  static Color _softStatus(Color strong) => strong.withValues(alpha: 0.12);
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
