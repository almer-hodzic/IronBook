import 'package:flutter/material.dart';

import '../services/admin_center_api_service.dart';
import '../services/admin_membership_plan_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'centers_management_screen.dart';
import 'membership_plans_screen.dart';

enum AdminSection { dashboard, centers, memberships }

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.centerApiService,
    required this.membershipPlanApiService,
  });

  final AdminCenterApiService centerApiService;
  final AdminMembershipPlanApiService membershipPlanApiService;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminSection _activeSection = AdminSection.dashboard;

  @override
  Widget build(BuildContext context) {
    final content = switch (_activeSection) {
      AdminSection.dashboard => _AdminDashboardHome(
        onOpenCenters: () => _selectSection(AdminSection.centers),
        onOpenMemberships: () => _selectSection(AdminSection.memberships),
      ),
      AdminSection.centers => CentersManagementScreen(
        centerApiService: widget.centerApiService,
      ),
      AdminSection.memberships => MembershipPlansScreen(
        membershipPlanApiService: widget.membershipPlanApiService,
        centerApiService: widget.centerApiService,
      ),
    };

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              IronBookAdminColors.pageTop,
              IronBookAdminColors.pageBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 920;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1260),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: IronBookAdminColors.surface,
                        border: Border.all(color: IronBookAdminColors.border),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: IronBookAdminColors.slate900.withValues(
                              alpha: 0.12,
                            ),
                            blurRadius: 70,
                            offset: const Offset(0, 28),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: compact
                            ? Column(
                                children: [
                                  _AdminSidebar(
                                    activeSection: _activeSection,
                                    compact: true,
                                    onSectionChanged: _selectSection,
                                  ),
                                  Expanded(child: content),
                                ],
                              )
                            : Row(
                                children: [
                                  _AdminSidebar(
                                    activeSection: _activeSection,
                                    onSectionChanged: _selectSection,
                                  ),
                                  Expanded(child: content),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _selectSection(AdminSection section) {
    setState(() {
      _activeSection = section;
    });
  }
}

class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: IronBookAdminColors.surfacePanel,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            decoration: const BoxDecoration(
              color: Color(0xE6FFFFFF),
              border: Border(
                bottom: BorderSide(color: IronBookAdminColors.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const AdminIconAction(
                      icon: Icons.search,
                      tooltip: 'Search is unavailable until global search is implemented.',
                    ),
                    const AdminIconAction(
                      icon: Icons.notifications_none,
                      tooltip: 'Notifications are unavailable until authentication is implemented.',
                    ),
                    const AdminStatusChip(
                      label: 'Layout',
                      variant: AdminStatusVariant.accent,
                    ),
                    ?actions,
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: IronBookAdminColors.surfaceSoft.withValues(alpha: 0.60),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _withSpacing(children),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Widget> _withSpacing(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        spaced.add(const SizedBox(height: 14));
      }
      spaced.add(children[index]);
    }

    return spaced;
  }
}

class AdminFormPage extends StatelessWidget {
  const AdminFormPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              IronBookAdminColors.pageTop,
              IronBookAdminColors.pageBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: AdminPanel(
                  title: title,
                  action: actions,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.activeSection,
    required this.onSectionChanged,
    this.compact = false,
  });

  final AdminSection activeSection;
  final ValueChanged<AdminSection> onSectionChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sidebar = Container(
      width: compact ? double.infinity : 250,
      height: compact ? null : double.infinity,
      decoration: BoxDecoration(
        color: IronBookAdminColors.sidebarSurface,
        border: Border(
          right: compact
              ? BorderSide.none
              : const BorderSide(color: IronBookAdminColors.border),
          bottom: compact
              ? const BorderSide(color: IronBookAdminColors.border)
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SidebarBrand(),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: _navItems()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SidebarBrand(),
                  const SizedBox(height: 30),
                  ..._navItems(),
                  const Spacer(),
                  const _SidebarScopeCard(),
                ],
              ),
      ),
    );

    return sidebar;
  }

  List<Widget> _navItems() {
    return [
      _SidebarItem(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        selected: activeSection == AdminSection.dashboard,
        onTap: () => onSectionChanged(AdminSection.dashboard),
      ),
      _SidebarItem(
        icon: Icons.apartment,
        label: 'Centers',
        selected: activeSection == AdminSection.centers,
        onTap: () => onSectionChanged(AdminSection.centers),
      ),
      const _SidebarItem(
        icon: Icons.assignment_outlined,
        label: 'Coaching Requests',
        enabled: false,
      ),
      const _SidebarItem(
        icon: Icons.groups_outlined,
        label: 'Trainers',
        enabled: false,
      ),
      _SidebarItem(
        icon: Icons.event_available_outlined,
        label: 'Memberships',
        selected: activeSection == AdminSection.memberships,
        onTap: () => onSectionChanged(AdminSection.memberships),
      ),
      const _SidebarItem(
        icon: Icons.payments_outlined,
        label: 'Payments',
        enabled: false,
      ),
      const _SidebarItem(
        icon: Icons.insert_chart_outlined,
        label: 'Reports',
        enabled: false,
      ),
    ];
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.surface,
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IronBook',
                  style: TextStyle(
                    color: IronBookAdminColors.slate900,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Admin Console',
                  style: TextStyle(
                    color: IronBookAdminColors.slate500,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarScopeCard extends StatelessWidget {
  const _SidebarScopeCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FEE7),
        border: Border.all(color: IronBookAdminColors.lime200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SCOPE',
              style: TextStyle(
                color: IronBookAdminColors.lime900,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.3,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Centers and Memberships are backed by the real API.',
              style: TextStyle(
                color: IronBookAdminColors.lime900,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardHome extends StatelessWidget {
  const _AdminDashboardHome({
    required this.onOpenCenters,
    required this.onOpenMemberships,
  });

  final VoidCallback onOpenCenters;
  final VoidCallback onOpenMemberships;

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Admin Dashboard',
      subtitle: 'Shared operations layout for the IronBook admin workspace.',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 760;

            final cards = [
              _ModuleCard(
                icon: Icons.apartment,
                title: 'Centers Management',
                description:
                    'Manage real IronBook center records from the API.',
                status: 'Available',
                statusVariant: AdminStatusVariant.success,
                buttonLabel: 'Open Centers',
                onPressed: onOpenCenters,
              ),
              _ModuleCard(
                icon: Icons.event_available_outlined,
                title: 'Membership Packages',
                description:
                    'Manage real membership plans and center availability.',
                status: 'Available',
                statusVariant: AdminStatusVariant.success,
                buttonLabel: 'Open Memberships',
                onPressed: onOpenMemberships,
              ),
            ];

            if (!twoColumns) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    if (card != cards.last) const SizedBox(height: 14),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 14),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
        AdminPanel(
          title: 'Deferred Admin Areas',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _DeferredChip(
                icon: Icons.assignment_outlined,
                label: 'Coaching Requests',
              ),
              _DeferredChip(icon: Icons.groups_outlined, label: 'Trainers'),
              _DeferredChip(icon: Icons.payments_outlined, label: 'Payments'),
              _DeferredChip(
                icon: Icons.insert_chart_outlined,
                label: 'Reports',
              ),
            ],
          ),
        ),
        const _DashboardNotice(),
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.statusVariant,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final AdminStatusVariant statusVariant;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: title,
      action: AdminStatusChip(label: status, variant: statusVariant),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: IronBookAdminColors.lime100,
              border: Border.all(color: IronBookAdminColors.lime200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: IronBookAdminColors.lime900, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                AdminButton.primary(
                  onPressed: onPressed,
                  icon: Icons.arrow_forward,
                  label: buttonLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeferredChip extends StatelessWidget {
  const _DeferredChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.slate100,
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: IronBookAdminColors.slate500),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: IronBookAdminColors.slate600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const AdminStatusChip(label: 'Later'),
          ],
        ),
      ),
    );
  }
}

class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice();

  @override
  Widget build(BuildContext context) {
    return const AdminPanel(
      title: 'Operations Overview',
      child: Text(
        'Analytics, attendance, revenue, notifications, and authentication-specific controls will appear after their real backend slices exist. This page intentionally avoids fake operational metrics.',
        style: TextStyle(
          color: IronBookAdminColors.slate500,
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronBookAdminColors.lime500,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'IB',
        style: TextStyle(
          color: IronBookAdminColors.slate900,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? IronBookAdminColors.lime900
        : enabled
        ? IronBookAdminColors.slate600
        : IronBookAdminColors.slate400;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: enabled || selected ? label : '$label is not implemented yet',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled || selected ? onTap : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? IronBookAdminColors.lime100
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? IronBookAdminColors.lime200
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!enabled && !selected) ...[
                      const SizedBox(width: 8),
                      const AdminStatusChip(label: 'Later'),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
