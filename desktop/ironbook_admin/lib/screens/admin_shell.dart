import 'package:flutter/material.dart';

import '../services/admin_center_api_service.dart';
import 'centers_management_screen.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.centerApiService});

  final AdminCenterApiService centerApiService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _AdminSidebar(),
          Expanded(
            child: CentersManagementScreen(centerApiService: centerApiService),
          ),
        ],
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      color: const Color(0xFF18202B),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IronBook',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Admin',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
              ),
              const SizedBox(height: 32),
              const _SidebarItem(
                icon: Icons.dashboard_outlined,
                label: 'Dashboard',
                enabled: false,
              ),
              const _SidebarItem(
                icon: Icons.apartment,
                label: 'Centers',
                selected: true,
              ),
              const _SidebarItem(
                icon: Icons.badge_outlined,
                label: 'Trainers',
                enabled: false,
              ),
              const _SidebarItem(
                icon: Icons.event_available_outlined,
                label: 'Memberships & Classes',
                enabled: false,
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
              const Spacer(),
              Text(
                'Unavailable items are intentionally deferred.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.54),
                  fontSize: 12,
                ),
              ),
            ],
          ),
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : enabled
        ? Colors.white.withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.38);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF273449) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        minLeadingWidth: 24,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, color: color, size: 20),
        title: Text(label, style: TextStyle(color: color)),
        subtitle: enabled || selected
            ? null
            : Text(
                'Not implemented',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.36),
                  fontSize: 11,
                ),
              ),
        enabled: enabled,
        selected: selected,
      ),
    );
  }
}
