import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/controllers/auth_controller.dart';
import '../../../app/providers/auth_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'pat_dialog.dart';

/// Screen 1 — Sign in (GitHub Device Flow + PAT fallback).
///
/// Wired in T12 to [authControllerProvider]. Behaviour per the sealed
/// [AuthState] plus Riverpod's [AsyncValue]:
///   data(AuthSignedOut)                 → default card, GitHub button live
///   data(AuthDeviceFlowAwaitingUser)    → shows challenge.userCode
///   data(AuthSignedIn)                  → brief "Signed in as @…" message
///   loading                             → spinner replaces GitHub button
///   error                               → inline error banner + button
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(authControllerProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accentSoftBg, t.surfaceBackground],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            elevation: 0,
            color: t.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: t.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
              child: _SignInBody(async: async),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInBody extends ConsumerWidget {
  const _SignInBody({required this.async});
  final AsyncValue<AuthState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final controller = ref.read(authControllerProvider.notifier);
    final children = <Widget>[
      _BrandMark(),
      const SizedBox(height: 20),
      Text(
        'GitMdScribe',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Sign in with your GitHub account to start reviewing specs.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: t.textMuted,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 24),
    ];

    // Error banner sits above the action row so the user sees *why* before
    // reading what to do next. The main action stays clickable.
    if (async.hasError) {
      children.add(_ErrorBanner(message: async.error.toString()));
      children.add(const SizedBox(height: 12));
    }

    final data = async.value;
    if (data is AuthDeviceFlowAwaitingUser) {
      children.add(_DeviceCodePanel(
        userCode: data.challenge.userCode,
        verificationUri: data.challenge.verificationUri,
      ));
      children.add(const SizedBox(height: 16));
    } else if (data is AuthSignedIn) {
      children.add(_SignedInPanel(login: data.session.identity.name));
      children.add(const SizedBox(height: 16));
    }

    if (async.isLoading) {
      children.add(const _LoadingButton());
    } else {
      children.add(
        _GitHubButton(onPressed: () => controller.startDeviceFlow()),
      );
    }
    children.add(const SizedBox(height: 12));
    children.add(
      OutlinedButton(
        onPressed: async.isLoading ? null : () => _openPatDialog(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.borderSubtle),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text(
          'Sign in with a token instead',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
    children.add(const SizedBox(height: 20));
    children.add(
      Text(
        'Device Flow · no backend · token stays in Android Keystore',
        textAlign: TextAlign.center,
        style: appMono(context, size: 10, color: t.textMuted),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Future<void> _openPatDialog(BuildContext context, WidgetRef ref) async {
    // Explicit barrier colour (token-driven scrim): Flutter's default
    // falls back to opaque black in some ancestor-missing setups, which
    // is what produced the "black surface" QA report. Hard-coding the
    // scrim at 54% black keeps the card readable against the app
    // background in both light and dark tokens.
    final pat = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const PatDialog(),
    );
    if (pat == null || pat.isEmpty) return;
    await ref.read(authControllerProvider.notifier).signInWithPat(pat);
  }
}

class _DeviceCodePanel extends StatefulWidget {
  const _DeviceCodePanel({
    required this.userCode,
    required this.verificationUri,
  });
  final String userCode;
  final String verificationUri;

  @override
  State<_DeviceCodePanel> createState() => _DeviceCodePanelState();
}

class _DeviceCodePanelState extends State<_DeviceCodePanel> {
  @override
  void initState() {
    super.initState();
    // Auto-copy the code the moment the panel appears so the user can
    // just tap "Copy & open GitHub" → paste → done. Re-mounting
    // (e.g. after restarting the flow) re-copies the new code.
    Clipboard.setData(ClipboardData(text: widget.userCode));
  }

  Future<void> _copyAndOpen() async {
    await Clipboard.setData(ClipboardData(text: widget.userCode));
    final uri = Uri.parse(widget.verificationUri);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.userCode,
            textAlign: TextAlign.center,
            style: appMono(
              context,
              size: 22,
              weight: FontWeight.w700,
              color: t.accentPrimary,
            ).copyWith(letterSpacing: 2.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Code copied to clipboard. Paste at github.com/login/device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _copyAndOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Copy & open GitHub'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accentPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedInPanel extends StatelessWidget {
  const _SignedInPanel({required this.login});
  final String login;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.statusSuccess.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: t.statusSuccess),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Signed in as @$login',
              style: TextStyle(
                color: t.statusSuccess,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.statusDanger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.statusDanger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: t.statusDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.statusDanger,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: t.accentSoftBg,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.edit_note_rounded, size: 32, color: t.accentPrimary),
      ),
    );
  }
}

class _GitHubButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _GitHubButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.textPrimary,
        foregroundColor: t.surfaceElevated,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code_rounded, size: 18, color: t.surfaceElevated),
          const SizedBox(width: 10),
          const Text(
            'Continue with GitHub',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(t.textPrimary),
        ),
      ),
    );
  }
}

