import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The "Sign in with a token instead" dialog launched from
/// [SignInScreen]. Split out so the Sign In file stays under the
/// per-file line budget and so the dialog has its own test surface.
///
/// On submit, [Navigator.pop] returns the trimmed PAT to the caller;
/// on cancel, it returns `null`. The Sign in button is disabled while
/// the field is empty so an empty token can never reach the auth port.
class PatDialog extends StatefulWidget {
  const PatDialog({super.key});

  @override
  State<PatDialog> createState() => _PatDialogState();
}

class _PatDialogState extends State<PatDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Wrap in a local Theme that pins AlertDialog's backgroundColor to
    // our tokens. Without this, Flutter falls back to the ambient
    // dialogBackgroundColor (which can resolve to an undefined default
    // outside a MaterialApp — the root cause of the M1a QA "black
    // surface" report).
    return Theme(
      data: Theme.of(context).copyWith(
        dialogTheme: DialogThemeData(backgroundColor: t.surfaceElevated),
      ),
      child: AlertDialog(
        backgroundColor: t.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        title: Text(
          'Paste personal access token',
          style: TextStyle(color: t.textPrimary, fontSize: 15),
        ),
        // Do NOT autofocus: on Android tablets (OnePlus Pad Go 2 in
        // particular), autofocus + obscureText triggers the vendor's
        // "OplusSecurityInputMethod" which paints opaque-black over the
        // full Flutter surface, masking the dialog. Let the user tap to
        // focus — the standard keyboard animates in and the dialog
        // stays visible.
        content: TextField(
          controller: _controller,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Personal access token',
            labelStyle: TextStyle(color: t.textMuted, fontSize: 12),
            hintText: 'ghp_…',
            hintStyle: appMono(context, size: 12, color: t.textMuted),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: t.borderSubtle),
            ),
          ),
          style: appMono(context, size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            // Sign in is disabled until the field has content so the
            // dialog never submits an empty PAT against the auth port.
            onPressed: _controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
