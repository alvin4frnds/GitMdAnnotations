import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Shared dialog chrome for modal-style confirmation screens rendered inside
/// the mockup browser pane. Renders a dimmed backdrop with a centered, rounded
/// card. The card composes three optional regions: a header (icon + title +
/// description), an arbitrary content column, and a footer button row.
class ModalShell extends StatelessWidget {
  /// Width of the card in logical pixels (matches the mockup spec: 520 / 540 /
  /// 580).
  final double cardWidth;
  final Widget header;
  final List<Widget> sections;
  final Widget footer;

  const ModalShell({
    super.key,
    required this.cardWidth,
    required this.header,
    required this.sections,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: Colors.black.withValues(alpha: 0.30),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cardWidth),
            child: Container(
              decoration: BoxDecoration(
                color: t.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  ...sections,
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard header: a colored icon square + heading + description. The
/// description is provided as inline spans so screens can embed `mono` runs.
class ModalHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String heading;
  final List<InlineSpan> descriptionSpans;

  const ModalHeader({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.heading,
    required this.descriptionSpans,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: descriptionSpans),
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontally-padded section that sits on the sunken surface and is
/// separated from its neighbours by hairline top/bottom borders.
class ModalSunkenSection extends StatelessWidget {
  final Widget child;
  final bool topBorder;
  final bool bottomBorder;
  final EdgeInsetsGeometry padding;

  const ModalSunkenSection({
    super.key,
    required this.child,
    this.topBorder = true,
    this.bottomBorder = true,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 12),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border(
          top: topBorder ? BorderSide(color: t.borderSubtle) : BorderSide.none,
          bottom:
              bottomBorder ? BorderSide(color: t.borderSubtle) : BorderSide.none,
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A small uppercase caption (e.g. "Files to be committed") used as a label
/// above sunken content blocks.
class ModalCaption extends StatelessWidget {
  final String text;
  const ModalCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

/// Right-aligned footer button row. The last button is rendered primary; all
/// preceding buttons are ghost.
class ModalFooter extends StatelessWidget {
  /// Optional leading widget rendered on the left (e.g. the offline warning
  /// on the submit dialog).
  final Widget? leading;
  final List<Widget> buttons;

  const ModalFooter({super.key, this.leading, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          if (leading != null) Expanded(child: leading!) else const Spacer(),
          ...[
            for (int i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              buttons[i],
            ],
          ],
        ],
      ),
    );
  }
}

/// Low-opacity footer ghost button.
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const GhostButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed ?? () {},
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

/// Primary footer button (solid, accentPrimary by default).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? background;
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ElevatedButton(
      onPressed: onPressed ?? () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: background ?? t.accentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
