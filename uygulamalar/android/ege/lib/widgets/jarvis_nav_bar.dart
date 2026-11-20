import 'package:flutter/material.dart';

import 'jarvis_fx.dart';
import 'jarvis_ui.dart';

class JarvisNavItem {
  const JarvisNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeColor,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Small status dot on the icon (e.g. PC online state); null hides it.
  final Color? badgeColor;
}

/// Frosted bottom navigation with a sliding glow indicator.
class JarvisNavBar extends StatelessWidget {
  const JarvisNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<JarvisNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    const slide = Duration(milliseconds: 380);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JColors.surface,
        border: Border(top: BorderSide(color: JColors.border)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth / items.length;
              final sel = selectedIndex.clamp(0, items.length - 1);
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: slide,
                    curve: Curves.easeOutBack,
                    left: w * sel + w * 0.14,
                    width: w * 0.72,
                    top: 6,
                    height: 32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: JColors.primary.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: slide,
                    curve: Curves.easeOutCubic,
                    left: w * sel + w * 0.32,
                    width: w * 0.36,
                    top: 0,
                    height: 2.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: JColors.accent,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavButton(
                            item: items[i],
                            selected: i == sel,
                            onTap: () {
                              JFx.selection();
                              onSelected(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final JarvisNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? JColors.accent : JColors.muted;
    Widget icon = Icon(selected ? item.selectedIcon : item.icon, size: 22, color: color);
    if (item.badgeColor != null) {
      icon = Badge(backgroundColor: item.badgeColor, smallSize: 7, child: icon);
    }
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 11),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                child: icon,
              ),
              const SizedBox(height: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  letterSpacing: selected ? 0.2 : 0,
                ),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
