import 'package:flutter/material.dart';

import '../theme/ironbook_admin_colors.dart';

enum AdminStatusVariant { neutral, accent, success, warning, danger }

class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.surface,
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: IronBookAdminColors.slate900.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: IronBookAdminColors.slate800,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          const Divider(height: 1, color: IronBookAdminColors.border),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }
}

class AdminRowCard extends StatelessWidget {
  const AdminRowCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Ink(
      decoration: BoxDecoration(
        color: IronBookAdminColors.surfaceSoft.withValues(alpha: 0.75),
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: child,
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({
    super.key,
    required this.label,
    this.variant = AdminStatusVariant.neutral,
  });

  final String label;
  final AdminStatusVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = switch (variant) {
      AdminStatusVariant.accent => (
        bg: IronBookAdminColors.amber100,
        fg: IronBookAdminColors.amber800,
        border: IronBookAdminColors.amber200,
      ),
      AdminStatusVariant.success => (
        bg: IronBookAdminColors.emerald100,
        fg: IronBookAdminColors.emerald700,
        border: IronBookAdminColors.emerald200,
      ),
      AdminStatusVariant.warning => (
        bg: IronBookAdminColors.amber100,
        fg: IronBookAdminColors.amber700,
        border: IronBookAdminColors.amber200,
      ),
      AdminStatusVariant.danger => (
        bg: IronBookAdminColors.rose100,
        fg: IronBookAdminColors.rose700,
        border: IronBookAdminColors.rose200,
      ),
      AdminStatusVariant.neutral => (
        bg: IronBookAdminColors.slate100,
        fg: IronBookAdminColors.slate600,
        border: IronBookAdminColors.border,
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
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class AdminButton extends StatelessWidget {
  const AdminButton.primary({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  }) : _primary = true;

  const AdminButton.secondary({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  }) : _primary = false;

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        _primary ? IronBookAdminColors.slate900 : IronBookAdminColors.surface,
      ),
      foregroundColor: WidgetStatePropertyAll(
        _primary ? Colors.white : IronBookAdminColors.slate600,
      ),
      side: WidgetStatePropertyAll(
        _primary
            ? BorderSide.none
            : const BorderSide(color: IronBookAdminColors.border),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 5)],
        Text(label),
      ],
    );

    return _primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class AdminIconAction extends StatelessWidget {
  const AdminIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            backgroundColor: IronBookAdminColors.surface,
            disabledBackgroundColor: IronBookAdminColors.surface,
            foregroundColor: IronBookAdminColors.slate600,
            disabledForegroundColor: IronBookAdminColors.slate400,
            side: const BorderSide(color: IronBookAdminColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.tone = AdminStatusVariant.neutral,
  });

  final String label;
  final String value;
  final AdminStatusVariant tone;

  @override
  Widget build(BuildContext context) {
    final valueColor = switch (tone) {
      AdminStatusVariant.success => IronBookAdminColors.emerald700,
      AdminStatusVariant.warning => IronBookAdminColors.amber700,
      AdminStatusVariant.danger => IronBookAdminColors.rose700,
      _ => IronBookAdminColors.slate900,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.surfaceSoft.withValues(alpha: 0.70),
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: IronBookAdminColors.slate500,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminFieldLabel extends StatelessWidget {
  const AdminFieldLabel({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: IronBookAdminColors.slate600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 5),
          Text(
            hint!,
            style: const TextStyle(
              color: IronBookAdminColors.slate500,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
