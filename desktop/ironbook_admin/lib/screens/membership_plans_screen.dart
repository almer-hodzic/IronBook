import 'package:flutter/material.dart';

import '../models/admin_group_training.dart';
import '../models/admin_membership_plan.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_group_training_api_service.dart';
import '../services/admin_membership_plan_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';
import 'group_training_form_screen.dart';
import 'membership_plan_form_screen.dart';

class MembershipPlansScreen extends StatefulWidget {
  const MembershipPlansScreen({
    super.key,
    required this.membershipPlanApiService,
    required this.groupTrainingApiService,
    required this.centerApiService,
  });

  final AdminMembershipPlanApiService membershipPlanApiService;
  final AdminGroupTrainingApiService groupTrainingApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<MembershipPlansScreen> createState() => _MembershipPlansScreenState();
}

class _MembershipPlansScreenState extends State<MembershipPlansScreen> {
  late Future<List<AdminMembershipPlan>> _plansFuture;
  late Future<List<AdminGroupTraining>> _groupTrainingsFuture;
  final _searchController = TextEditingController();
  final _groupSearchController = TextEditingController();
  String _activeSearch = '';
  String _activeGroupSearch = '';

  @override
  void initState() {
    super.initState();
    _plansFuture = widget.membershipPlanApiService.getMembershipPlans();
    _groupTrainingsFuture = widget.groupTrainingApiService.getGroupTrainings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupSearchController.dispose();
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

  void _loadGroupTrainings({String? search}) {
    setState(() {
      _activeGroupSearch = search?.trim() ?? '';
      _groupTrainingsFuture = widget.groupTrainingApiService.getGroupTrainings(
        search: _activeGroupSearch,
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

  Future<void> _openAddGroupTraining() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => GroupTrainingFormScreen(
          groupTrainingApiService: widget.groupTrainingApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadGroupTrainings(search: _activeGroupSearch);
    _showSuccess('Group training created.');
  }

  Future<void> _openEditGroupTraining(AdminGroupTraining training) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => GroupTrainingFormScreen(
          groupTrainingId: training.id,
          groupTrainingApiService: widget.groupTrainingApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadGroupTrainings(search: _activeGroupSearch);
    _showSuccess('Group training updated.');
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
      actions: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AdminButton.secondary(
            onPressed: _openAddGroupTraining,
            icon: Icons.add,
            label: 'Add Group Training',
          ),
          AdminButton.primary(
            onPressed: _openAddPlan,
            icon: Icons.add,
            label: 'Add New Package',
          ),
        ],
      ),
      children: [
        _SearchStrip(
          title: 'Package Search',
          hintText: 'Search by package name',
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
        _SearchStrip(
          title: 'Group Training Search',
          hintText: 'Search by training or trainer',
          controller: _groupSearchController,
          activeSearch: _activeGroupSearch,
          onSearch: () =>
              _loadGroupTrainings(search: _groupSearchController.text),
          onClear: () {
            _groupSearchController.clear();
            _loadGroupTrainings();
          },
        ),
        FutureBuilder<List<AdminGroupTraining>>(
          future: _groupTrainingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StatePanel.loading(
                title: 'Loading group trainings',
                message: 'Please wait while group trainings are loaded.',
              );
            }

            if (snapshot.hasError) {
              return _StatePanel.error(
                title: 'Group trainings could not be loaded',
                message: snapshot.error.toString(),
                onRetry: () => _loadGroupTrainings(search: _activeGroupSearch),
              );
            }

            final trainings = snapshot.data ?? const <AdminGroupTraining>[];
            if (trainings.isEmpty) {
              return _StatePanel.empty(
                icon: Icons.groups_outlined,
                title: _activeGroupSearch.isEmpty
                    ? 'No group trainings yet'
                    : 'No matching group trainings',
                message: _activeGroupSearch.isEmpty
                    ? 'Create the first center class and assign it to a trainer.'
                    : 'No trainings matched the current search.',
                onRefresh: () =>
                    _loadGroupTrainings(search: _activeGroupSearch),
              );
            }

            return _GroupTrainingsPanel(
              trainings: trainings,
              onEdit: _openEditGroupTraining,
              onRefresh: () => _loadGroupTrainings(search: _activeGroupSearch),
            );
          },
        ),
      ],
    );
  }
}

class _SearchStrip extends StatelessWidget {
  const _SearchStrip({
    required this.title,
    required this.hintText,
    required this.controller,
    required this.activeSearch,
    required this.onSearch,
    required this.onClear,
  });

  final String title;
  final String hintText;
  final TextEditingController controller;
  final String activeSearch;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: title,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: hintText,
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

class _GroupTrainingsPanel extends StatelessWidget {
  const _GroupTrainingsPanel({
    required this.trainings,
    required this.onEdit,
    required this.onRefresh,
  });

  final List<AdminGroupTraining> trainings;
  final ValueChanged<AdminGroupTraining> onEdit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Group Trainings',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        children: [
          const _GroupTrainingsHeader(),
          const SizedBox(height: 8),
          for (final training in trainings) ...[
            _GroupTrainingRow(
              training: training,
              onEdit: () => onEdit(training),
            ),
            if (training != trainings.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _GroupTrainingsHeader extends StatelessWidget {
  const _GroupTrainingsHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 4, child: _HeaderText('Training')),
          Expanded(flex: 3, child: _HeaderText('Schedule')),
          Expanded(flex: 3, child: _HeaderText('Center / Trainer')),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: _HeaderText('Capacity & Actions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTrainingRow extends StatelessWidget {
  const _GroupTrainingRow({required this.training, required this.onEdit});

  final AdminGroupTraining training;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AdminRowCard(
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  training.name,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AdminStatusChip(label: training.category),
                    AdminStatusChip(label: training.difficulty),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${_formatDateTime(training.startsAt.toLocal())}\n${training.durationMinutes} min',
              style: const TextStyle(
                color: IronBookAdminColors.slate600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${training.centerLocation}\n${training.trainerName}',
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
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                AdminStatusChip(
                  label: training.status,
                  variant: _statusVariant(training.status),
                ),
                Text(
                  '${training.enrolledCount}/${training.capacity}',
                  style: const TextStyle(
                    color: IronBookAdminColors.slate700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AdminButton.secondary(
                  onPressed: onEdit,
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static AdminStatusVariant _statusVariant(String status) {
    return switch (status) {
      'Active' => AdminStatusVariant.success,
      'Full' => AdminStatusVariant.warning,
      _ => AdminStatusVariant.neutral,
    };
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

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
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

  static String _formatPrice(double price) =>
      'EUR ${price.toStringAsFixed(2)} / month';

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

  const _StatePanel.loading({
    this.title = 'Loading membership plans',
    this.message = 'Please wait while plans are loaded.',
  }) : icon = Icons.hourglass_empty,
       action = null,
       loading = true;

  factory _StatePanel.error({
    String title = 'Membership plans could not be loaded',
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: message,
      action: AdminButton.primary(
        onPressed: onRetry,
        icon: Icons.refresh,
        label: 'Retry',
      ),
    );
  }

  factory _StatePanel.empty({
    String? activeSearch,
    IconData icon = Icons.event_available_outlined,
    String? title,
    String? message,
    required VoidCallback onRefresh,
  }) {
    final search = activeSearch ?? '';
    return _StatePanel(
      icon: icon,
      title:
          title ??
          (search.isEmpty
              ? 'No membership plans yet'
              : 'No matching membership plans'),
      message:
          message ??
          (search.isEmpty
              ? 'Create the first package and assign it to real centers.'
              : 'No plans matched the current search.'),
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
