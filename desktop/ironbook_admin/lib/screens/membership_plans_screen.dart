import 'package:flutter/material.dart';

import '../models/admin_membership_plan.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_membership_plan_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';
import 'membership_plan_form_screen.dart';

class MembershipPlansScreen extends StatefulWidget {
  const MembershipPlansScreen({
    super.key,
    required this.membershipPlanApiService,
    required this.centerApiService,
  });

  final AdminMembershipPlanApiService membershipPlanApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<MembershipPlansScreen> createState() => _MembershipPlansScreenState();
}

class _MembershipPlansScreenState extends State<MembershipPlansScreen> {
  late Future<List<AdminMembershipPlan>> _plansFuture;
  final _searchController = TextEditingController();
  String _activeSearch = '';

  @override
  void initState() {
    super.initState();
    _plansFuture = widget.membershipPlanApiService.getMembershipPlans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadPlans({String? search}) {
    setState(() {
      _activeSearch = search?.trim() ?? '';
      _plansFuture = widget.membershipPlanApiService.getMembershipPlans(
        search: _activeSearch,
      );
    });
  }

  Future<void> _openAddPlan() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MembershipPlanFormScreen(
          membershipPlanApiService: widget.membershipPlanApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadPlans(search: _activeSearch);
    _showSuccess('Membership plan created.');
  }

  Future<void> _openEditPlan(AdminMembershipPlan plan) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MembershipPlanFormScreen(
          planId: plan.id,
          membershipPlanApiService: widget.membershipPlanApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadPlans(search: _activeSearch);
    _showSuccess('Membership plan updated.');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Membership & Group Trainings',
      subtitle: 'Manage membership plans, pricing, and center availability.',
      actions: AdminButton.primary(
        onPressed: _openAddPlan,
        icon: Icons.add,
        label: 'Add New Package',
      ),
      children: [
        _SearchStrip(
          controller: _searchController,
          activeSearch: _activeSearch,
          onSearch: () => _loadPlans(search: _searchController.text),
          onClear: () {
            _searchController.clear();
            _loadPlans();
          },
        ),
        FutureBuilder<List<AdminMembershipPlan>>(
          future: _plansFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StatePanel.loading();
            }

            if (snapshot.hasError) {
              return _StatePanel.error(
                message: snapshot.error.toString(),
                onRetry: () => _loadPlans(search: _activeSearch),
              );
            }

            final plans = snapshot.data ?? const <AdminMembershipPlan>[];
            if (plans.isEmpty) {
              return _StatePanel.empty(
                activeSearch: _activeSearch,
                onRefresh: () => _loadPlans(search: _activeSearch),
              );
            }

            return _PlansPanel(
              plans: plans,
              onEdit: _openEditPlan,
              onRefresh: () => _loadPlans(search: _activeSearch),
            );
          },
        ),
        AdminPanel(
          title: 'Group Trainings',
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Group training management is unavailable until its real backend slice is implemented.',
                  style: TextStyle(
                    color: IronBookAdminColors.slate500,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const AdminStatusChip(label: 'Later'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchStrip extends StatelessWidget {
  const _SearchStrip({
    required this.controller,
    required this.activeSearch,
    required this.onSearch,
    required this.onClear,
  });

  final TextEditingController controller;
  final String activeSearch;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Search',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search by package name',
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 10),
          AdminButton.primary(
            onPressed: onSearch,
            icon: Icons.search,
            label: 'Search',
          ),
          const SizedBox(width: 8),
          AdminButton.secondary(
            onPressed: onClear,
            icon: Icons.clear,
            label: activeSearch.isEmpty ? 'Clear' : 'Clear Search',
          ),
        ],
      ),
    );
  }
}

class _PlansPanel extends StatelessWidget {
  const _PlansPanel({
    required this.plans,
    required this.onEdit,
    required this.onRefresh,
  });

  final List<AdminMembershipPlan> plans;
  final ValueChanged<AdminMembershipPlan> onEdit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Membership Packages',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        children: [
          const _PlansHeader(),
          const SizedBox(height: 8),
          for (final plan in plans) ...[
            _PlanRow(plan: plan, onEdit: () => onEdit(plan)),
            if (plan != plans.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _PlansHeader extends StatelessWidget {
  const _PlansHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 5, child: _HeaderText('Package')),
          Expanded(flex: 3, child: _HeaderText('Centers')),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: _HeaderText('Status & Actions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: IronBookAdminColors.slate500,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.onEdit});

  final AdminMembershipPlan plan;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final centerLabel = plan.centers.isEmpty
        ? 'No centers assigned'
        : plan.centers
              .map((center) => '${center.centerName} / ${center.location}')
              .join(', ');

    return AdminRowCard(
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatPrice(plan.monthlyPrice),
                  style: const TextStyle(
                    color: IronBookAdminColors.slate900,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_hasText(plan.description)) ...[
                  const SizedBox(height: 4),
                  Text(
                    plan.description!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: IronBookAdminColors.slate500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              centerLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: IronBookAdminColors.slate600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                AdminStatusChip(
                  label: plan.isActive ? 'Active' : 'Inactive',
                  variant: plan.isActive
                      ? AdminStatusVariant.success
                      : AdminStatusVariant.neutral,
                ),
                AdminButton.secondary(
                  onPressed: onEdit,
                  icon: Icons.edit_outlined,
                  label: 'Edit Package',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatPrice(double price) => 'EUR ${price.toStringAsFixed(2)} / month';

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _StatePanel.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading membership plans',
      message = 'Please wait while plans are loaded.',
      action = null,
      loading = true;

  factory _StatePanel.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Membership plans could not be loaded',
      message: message,
      action: AdminButton.primary(
        onPressed: onRetry,
        icon: Icons.refresh,
        label: 'Retry',
      ),
    );
  }

  factory _StatePanel.empty({
    required String activeSearch,
    required VoidCallback onRefresh,
  }) {
    return _StatePanel(
      icon: Icons.event_available_outlined,
      title: activeSearch.isEmpty
          ? 'No membership plans yet'
          : 'No matching membership plans',
      message: activeSearch.isEmpty
          ? 'Create the first package and assign it to real centers.'
          : 'No plans matched the current search.',
      action: AdminButton.secondary(
        onPressed: onRefresh,
        icon: Icons.refresh,
        label: 'Refresh',
      ),
    );
  }

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: title,
      child: SizedBox(
        height: 260,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const CircularProgressIndicator()
                else
                  Icon(icon, size: 42, color: IronBookAdminColors.slate500),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
