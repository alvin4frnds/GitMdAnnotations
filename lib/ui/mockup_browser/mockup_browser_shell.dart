import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'mockup_registry.dart';

class MockupBrowserShell extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const MockupBrowserShell({super.key, required this.themeMode});

  @override
  State<MockupBrowserShell> createState() => _MockupBrowserShellState();
}

class _MockupBrowserShellState extends State<MockupBrowserShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entry = mockupRegistry[_selected];

    return Scaffold(
      backgroundColor: t.surfaceBackground,
      body: SafeArea(
        child: Row(
          children: [
            _SidebarRail(
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              themeMode: widget.themeMode,
            ),
            Container(width: 1, color: t.borderSubtle),
            Expanded(
              child: ClipRect(
                child: KeyedSubtree(
                  key: ValueKey(_selected),
                  child: Builder(builder: entry.builder),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRail extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueNotifier<ThemeMode> themeMode;
  const _SidebarRail({
    required this.selected,
    required this.onSelect,
    required this.themeMode,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 240,
      color: t.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'GitMdAnnotations',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Mockup browser',
              style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: mockupRegistry.length,
              itemBuilder: (context, i) => _RailItem(
                label: mockupRegistry[i].label,
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          Divider(height: 1, color: t.borderSubtle),
          _ThemeToggle(themeMode: themeMode),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? t.accentSoftBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? t.accentPrimary : t.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const _ThemeToggle({required this.themeMode});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return InkWell(
          onTap: () => themeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  size: 16,
                  color: t.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  isDark ? 'Dark mode' : 'Light mode',
                  style: TextStyle(fontSize: 12, color: t.textMuted, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  'tap',
                  style: TextStyle(fontSize: 10, color: t.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
