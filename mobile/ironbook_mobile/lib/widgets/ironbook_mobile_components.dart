import 'package:flutter/material.dart';

import '../theme/ironbook_mobile_colors.dart';

enum IronBookTagVariant { neutral, accent, success, warning, danger }

class IronBookMobileShell extends StatelessWidget {
  const IronBookMobileShell({
    super.key,
    required this.children,
    this.bottomNav,
  });

  final List<Widget> children;
  final Widget? bottomNav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              IronBookMobileColors.backgroundTop,
              IronBookMobileColors.backgroundBottom,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -72,
              top: -54,
              child: _GlowCircle(
                color: IronBookMobileColors.accent.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              right: -84,
              bottom: -70,
              child: _GlowCircle(
                color: IronBookMobileColors.accentHot.withValues(alpha: 0.14),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: _withSpacing(children),
                    ),
                  ),
                  if (bottomNav != null)
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xE6FFFFFF),
                        border: Border(
                          top: BorderSide(color: IronBookMobileColors.slate200),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: bottomNav,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _withSpacing(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        spaced.add(const SizedBox(height: 10));
      }
      spaced.add(children[index]);
    }

    return spaced;
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 210,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class IronBookMobileHeader extends StatelessWidget {
  const IronBookMobileHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) ...[
                IronBookMobileButton.secondary(
                  onPressed: onBack,
                  icon: Icons.arrow_back,
                  label: 'Back',
                  compact: true,
                ),
                const SizedBox(height: 8),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class IronBookMobileSection extends StatelessWidget {
  const IronBookMobileSection({
    super.key,
    required this.child,
    this.muted = false,
  });

  final Widget child;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted
            ? IronBookMobileColors.surfaceMuted.withValues(alpha: 0.85)
            : IronBookMobileColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: IronBookMobileColors.slate200),
        boxShadow: [
          BoxShadow(
            color: IronBookMobileColors.slate900.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class IronBookTag extends StatelessWidget {
  const IronBookTag({
    super.key,
    required this.label,
    this.variant = IronBookTagVariant.neutral,
  });

  final String label;
  final IronBookTagVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = switch (variant) {
      IronBookTagVariant.accent => (
        bg: IronBookMobileColors.amber100.withValues(alpha: 0.75),
        fg: IronBookMobileColors.amber700,
        border: const Color(0xFFFDE68A),
      ),
      IronBookTagVariant.success => (
        bg: IronBookMobileColors.emerald100,
        fg: IronBookMobileColors.emerald700,
        border: const Color(0xFFA7F3D0),
      ),
      IronBookTagVariant.warning => (
        bg: IronBookMobileColors.amber100,
        fg: IronBookMobileColors.amber700,
        border: const Color(0xFFFDE68A),
      ),
      IronBookTagVariant.danger => (
        bg: IronBookMobileColors.rose100,
        fg: IronBookMobileColors.rose700,
        border: const Color(0xFFFECDD3),
      ),
      IronBookTagVariant.neutral => (
        bg: IronBookMobileColors.slate100,
        fg: IronBookMobileColors.slate600,
        border: IronBookMobileColors.slate200,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: colors.fg,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class IronBookMobileButton extends StatelessWidget {
  const IronBookMobileButton.primary({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.compact = false,
  }) : _primary = true;

  const IronBookMobileButton.secondary({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.compact = false,
  }) : _primary = false;

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool compact;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        _primary ? IronBookMobileColors.slate900 : IronBookMobileColors.surface,
      ),
      foregroundColor: WidgetStatePropertyAll(
        _primary ? Colors.white : IronBookMobileColors.slate700,
      ),
      side: WidgetStatePropertyAll(
        _primary
            ? BorderSide.none
            : const BorderSide(color: IronBookMobileColors.slate200),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 10,
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label),
      ],
    );

    return _primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class IronBookBottomNav extends StatelessWidget {
  const IronBookBottomNav({
    super.key,
    this.activeLabel = 'Home',
    this.onDashboardTap,
  });

  final String activeLabel;
  final VoidCallback? onDashboardTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BottomNavItem(
            icon: Icons.home_outlined,
            label: 'Home',
            active: activeLabel == 'Home',
          ),
        ),
        Expanded(
          child: _BottomNavItem(
            icon: Icons.fitness_center,
            label: 'Classes',
            active: activeLabel == 'Classes',
          ),
        ),
        Expanded(
          child: _BottomNavItem(
            icon: Icons.groups_outlined,
            label: 'Trainers',
            active: activeLabel == 'Trainers',
          ),
        ),
        Expanded(
          child: _BottomNavItem(
            icon: Icons.assignment_turned_in_outlined,
            label: 'Dashboard',
            active: activeLabel == 'Dashboard',
            onTap: onDashboardTap,
          ),
        ),
        Expanded(
          child: _BottomNavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            active: activeLabel == 'Profile',
          ),
        ),
      ],
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: active ? 1 : 0.55,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: active ? IronBookMobileColors.slate900 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? Colors.white : IronBookMobileColors.slate500,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white : IronBookMobileColors.slate500,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
