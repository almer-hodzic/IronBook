import 'package:flutter/material.dart';

import '../models/admin_trainer.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_trainer_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';
import 'trainer_form_screen.dart';

class TrainersManagementScreen extends StatefulWidget {
  const TrainersManagementScreen({
    super.key,
    required this.trainerApiService,
    required this.centerApiService,
  });

  final AdminTrainerApiService trainerApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<TrainersManagementScreen> createState() =>
      _TrainersManagementScreenState();
}

class _TrainersManagementScreenState extends State<TrainersManagementScreen> {
  late Future<List<AdminTrainer>> _trainersFuture;
  final _searchController = TextEditingController();
  String _activeSearch = '';

  @override
  void initState() {
    super.initState();
    _loadTrainers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadTrainers({String? search}) {
    _activeSearch = search?.trim() ?? '';
    _trainersFuture = widget.trainerApiService.getTrainers(
      search: _activeSearch,
    );
  }

  void _refresh() {
    setState(() => _loadTrainers(search: _activeSearch));
  }

  Future<void> _openAddTrainer() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TrainerFormScreen(
          trainerApiService: widget.trainerApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _refresh();
    _showSuccess('Trainer created.');
  }

  Future<void> _openTrainer(AdminTrainer trainer) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TrainerFormScreen(
          trainerId: trainer.id,
          trainerApiService: widget.trainerApiService,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _refresh();
    _showSuccess('Trainer updated.');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Trainers Management',
      subtitle: 'Manage trainer profiles and real center assignments.',
      actions: AdminButton.primary(
        onPressed: _openAddTrainer,
        icon: Icons.add,
        label: 'Add Trainer',
      ),
      children: [
        _SearchStrip(
          controller: _searchController,
          activeSearch: _activeSearch,
          onSearch: () {
            setState(() => _loadTrainers(search: _searchController.text));
          },
          onClear: () {
            _searchController.clear();
            setState(_loadTrainers);
          },
        ),
        FutureBuilder<List<AdminTrainer>>(
          future: _trainersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StatePanel.loading();
            }

            if (snapshot.hasError) {
              return _StatePanel.error(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }

            final trainers = snapshot.data ?? const <AdminTrainer>[];
            if (trainers.isEmpty) {
              return _StatePanel.empty(
                activeSearch: _activeSearch,
                onRefresh: _refresh,
              );
            }

            return _TrainerRosterPanel(
              trainers: trainers,
              onRefresh: _refresh,
              onOpenTrainer: _openTrainer,
            );
          },
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
                hintText: 'Search by trainer name or email',
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

class _TrainerRosterPanel extends StatelessWidget {
  const _TrainerRosterPanel({
    required this.trainers,
    required this.onRefresh,
    required this.onOpenTrainer,
  });

  final List<AdminTrainer> trainers;
  final VoidCallback onRefresh;
  final ValueChanged<AdminTrainer> onOpenTrainer;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Trainer Roster',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        children: [
          const _RosterHeader(),
          const SizedBox(height: 8),
          for (final trainer in trainers) ...[
            _TrainerRow(trainer: trainer, onOpen: () => onOpenTrainer(trainer)),
            if (trainer != trainers.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 4, child: _HeaderText('Trainer')),
          Expanded(flex: 4, child: _HeaderText('Assigned Centers')),
          Expanded(
            flex: 3,
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

class _TrainerRow extends StatelessWidget {
  const _TrainerRow({required this.trainer, required this.onOpen});

  final AdminTrainer trainer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final centerLabel = trainer.centers.isEmpty
        ? 'No active centers assigned'
        : trainer.centers
              .map((center) => '${center.centerName} / ${center.location}')
              .join(', ');

    return AdminRowCard(
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trainer.displayName,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trainer.email,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate500,
                    fontSize: 12,
                  ),
                ),
                if (_hasText(trainer.phoneNumber)) ...[
                  const SizedBox(height: 4),
                  Text(
                    trainer.phoneNumber!.trim(),
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
            flex: 4,
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
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                AdminStatusChip(
                  label: trainer.isActive ? 'Active' : 'Inactive',
                  variant: trainer.isActive
                      ? AdminStatusVariant.success
                      : AdminStatusVariant.neutral,
                ),
                AdminButton.secondary(
                  onPressed: onOpen,
                  icon: Icons.person_outline,
                  label: 'View Profile',
                ),
                AdminButton.secondary(
                  onPressed: onOpen,
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

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
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

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _StatePanel.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading trainers',
      message = 'Please wait while trainer profiles are loaded.',
      action = null,
      loading = true;

  factory _StatePanel.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Trainers could not be loaded',
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
      icon: Icons.groups_outlined,
      title: activeSearch.isEmpty ? 'No trainers yet' : 'No matching trainers',
      message: activeSearch.isEmpty
          ? 'Create the first trainer profile and assign real centers.'
          : 'No trainers matched the current search.',
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
