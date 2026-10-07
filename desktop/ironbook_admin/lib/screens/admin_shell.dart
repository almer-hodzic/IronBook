import 'package:flutter/material.dart';

import '../services/admin_center_api_service.dart';
import '../services/admin_membership_plan_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'centers_management_screen.dart';
import 'membership_plans_screen.dart';

enum AdminSection { centers, memberships }

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
  AdminSection _activeSection = AdminSection.centers;

  @override
  Widget build(BuildContext context) {
    final content = switch (_activeSection) {
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1260),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: IronBookAdminColors.surface,
                    border: Border.all(color: IronBookAdminColors.border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: IronBookAdminColors.slate900.withValues(
                          alpha: 0.06,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        _AdminSidebar(
                          activeSection: _activeSection,
                          onSectionChanged: (section) {
                            setState(() {
                              _activeSection = section;
                            });
                          },
                        ),
                        Expanded(child: content),
                      ],
                    ),
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
      color: IronBookAdminColors.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                if (actions != null) ...[const SizedBox(width: 12), actions!],
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: IronBookAdminColors.surfaceSoft.withValues(alpha: 0.60),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
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
  });

  final AdminSection activeSection;
  final ValueChanged<AdminSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 214,
      decoration: const BoxDecoration(
        color: Color(0xB3F8FAFC),
        border: Border(right: BorderSide(color: IronBookAdminColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: IronBookAdminColors.surface,
                border: Border.all(color: IronBookAdminColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
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
            ),
            const SizedBox(height: 30),
            _SidebarItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              enabled: false,
            ),
            _SidebarItem(
              icon: Icons.apartment,
              label: 'Centers',
              selected: activeSection == AdminSection.centers,
              onTap: () => onSectionChanged(AdminSection.centers),
            ),
            _SidebarItem(
              icon: Icons.assignment_outlined,
              label: 'Coaching Requests',
              enabled: false,
            ),
            _SidebarItem(
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
            _SidebarItem(
              icon: Icons.payments_outlined,
              label: 'Payments',
              enabled: false,
            ),
            _SidebarItem(
              icon: Icons.insert_chart_outlined,
              label: 'Reports',
              enabled: false,
            ),
            const Spacer(),
            DecoratedBox(
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
            ),
          ],
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
        ? Colors.white
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
            color: selected ? IronBookAdminColors.slate900 : Colors.transparent,
            border: Border.all(
              color: selected
                  ? IronBookAdminColors.slate900
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!enabled && !selected)
                  const AdminStatusChip(label: 'Later'),
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
