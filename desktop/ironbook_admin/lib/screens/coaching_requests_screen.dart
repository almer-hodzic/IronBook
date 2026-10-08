import 'package:flutter/material.dart';

import '../models/admin_coaching_request.dart';
import '../models/admin_trainer.dart';
import '../services/admin_coaching_request_api_service.dart';
import '../services/admin_trainer_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class CoachingRequestsScreen extends StatefulWidget {
  const CoachingRequestsScreen({
    super.key,
    required this.coachingRequestApiService,
    required this.trainerApiService,
  });

  final AdminCoachingRequestApiService coachingRequestApiService;
  final AdminTrainerApiService trainerApiService;

  @override
  State<CoachingRequestsScreen> createState() => _CoachingRequestsScreenState();
}

class _CoachingRequestsScreenState extends State<CoachingRequestsScreen> {
  late Future<List<AdminCoachingRequest>> _requestsFuture;
  final _searchController = TextEditingController();
  String _activeSearch = '';
  String _activeStatus = 'All';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadRequests({String? search, String? status}) {
    _activeSearch = search?.trim() ?? _activeSearch;
    _activeStatus = status ?? _activeStatus;
    _requestsFuture = widget.coachingRequestApiService.getCoachingRequests(
      search: _activeSearch,
      status: _activeStatus == 'All' ? null : _activeStatus,
    );
  }

  void _refresh() {
    setState(() => _loadRequests());
  }

  Future<void> _handleAction(
    AdminCoachingRequest request,
    Future<AdminCoachingRequest> Function() action,
    String successMessage,
  ) async {
    final confirmed = await _confirmAction(
      title: successMessage,
      description: 'This action will update the selected request.',
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await action();
      if (!mounted) {
        return;
      }
      _refresh();
      _showMessage(successMessage);
    } on AdminCoachingRequestApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message, isError: true);
    }
  }

  Future<bool> _confirmAction({required String title, required String description}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _openReassignDialog(AdminCoachingRequest request) async {
    try {
      final trainers = await widget.coachingRequestApiService
          .getActiveTrainersForCenter(request.centerId);
      if (!mounted) {
        return;
      }

      final trainer = await showDialog<AdminTrainer>(
        context: context,
        builder: (context) => _ReassignTrainerDialog(
          request: request,
          trainers: trainers,
          currentTrainerId: request.trainerProfileId,
        ),
      );

      if (trainer == null || !mounted) {
        return;
      }

      await _handleAction(
        request,
        () => widget.coachingRequestApiService.reassignTrainer(
          request.id,
          trainer.id,
        ),
        'Trainer reassigned.',
      );
    } on AdminCoachingRequestApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? IronBookAdminColors.rose700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Coaching Requests',
      subtitle: 'Review, approve, reject, cancel, and reassign coaching requests.',
      children: [
        _SearchAndFilterPanel(
          searchController: _searchController,
          activeSearch: _activeSearch,
          activeStatus: _activeStatus,
          onSearch: () => setState(
            () => _loadRequests(search: _searchController.text),
          ),
          onClear: () {
            _searchController.clear();
            setState(() => _loadRequests(search: '', status: 'All'));
          },
          onStatusChanged: (status) => setState(
            () => _loadRequests(status: status),
          ),
        ),
        FutureBuilder<List<AdminCoachingRequest>>(
          future: _requestsFuture,
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

            final requests = snapshot.data ?? const <AdminCoachingRequest>[];
            if (requests.isEmpty) {
              return _StatePanel.empty(
                activeSearch: _activeSearch,
                onRefresh: _refresh,
              );
            }

            return _RequestsPanel(
              requests: requests,
              onRefresh: _refresh,
              onApprove: (request) => _handleAction(
                request,
                () => widget.coachingRequestApiService.approve(request.id),
                'Request approved.',
              ),
              onReject: (request) => _handleAction(
                request,
                () => widget.coachingRequestApiService.reject(request.id),
                'Request rejected.',
              ),
              onCancel: (request) => _handleAction(
                request,
                () => widget.coachingRequestApiService.cancel(request.id),
                'Request cancelled.',
              ),
              onReassign: _openReassignDialog,
            );
          },
        ),
      ],
    );
  }
}

class _SearchAndFilterPanel extends StatelessWidget {
  const _SearchAndFilterPanel({
    required this.searchController,
    required this.activeSearch,
    required this.activeStatus,
    required this.onSearch,
    required this.onClear,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String activeSearch;
  final String activeStatus;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    const statuses = ['All', 'Pending', 'Approved', 'Rejected', 'Cancelled'];

    return AdminPanel(
      title: 'Search & Filter',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search member, trainer, or center',
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 10),
          AdminButton.primary(onPressed: onSearch, icon: Icons.search, label: 'Search'),
          const SizedBox(width: 8),
          AdminButton.secondary(
            onPressed: onClear,
            icon: Icons.clear,
            label: activeSearch.isEmpty ? 'Clear' : 'Clear Search',
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: IronBookAdminColors.surface,
                border: Border.all(color: IronBookAdminColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButton<String>(
                  value: statuses.contains(activeStatus) ? activeStatus : 'All',
                  items: statuses
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => value != null ? onStatusChanged(value) : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({
    required this.requests,
    required this.onRefresh,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
    required this.onReassign,
  });

  final List<AdminCoachingRequest> requests;
  final VoidCallback onRefresh;
  final ValueChanged<AdminCoachingRequest> onApprove;
  final ValueChanged<AdminCoachingRequest> onReject;
  final ValueChanged<AdminCoachingRequest> onCancel;
  final ValueChanged<AdminCoachingRequest> onReassign;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Requests',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        children: [
          const _RequestHeader(),
          const SizedBox(height: 8),
          for (final request in requests) ...[
            _RequestRow(
              request: request,
              onApprove: () => onApprove(request),
              onReject: () => onReject(request),
              onCancel: () => onCancel(request),
              onReassign: () => onReassign(request),
            ),
            if (request != requests.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RequestHeader extends StatelessWidget {
  const _RequestHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderText('Member / Trainer')),
          Expanded(flex: 2, child: _HeaderText('Center')),
          Expanded(flex: 2, child: _HeaderText('Date & Time')),
          Expanded(flex: 1, child: _HeaderText('Duration')),
          Expanded(flex: 1, child: _HeaderText('Status')),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _HeaderText('Actions'),
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

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
    required this.onReassign,
  });

  final AdminCoachingRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onReassign;

  @override
  Widget build(BuildContext context) {
    final statusVariant = switch (request.status) {
      'Pending' => AdminStatusVariant.accent,
      'Approved' => AdminStatusVariant.success,
      'Rejected' => AdminStatusVariant.danger,
      'Cancelled' => AdminStatusVariant.neutral,
      _ => AdminStatusVariant.neutral,
    };


    final canApprove = request.status == 'Pending';
    final canReject = request.status == 'Pending' || request.status == 'Approved';
    final canCancel = request.status != 'Cancelled' && request.status != 'Rejected';

    return AdminRowCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.memberName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(request.trainerName, style: const TextStyle(fontSize: 12, color: IronBookAdminColors.slate500)),
                if (request.fitnessGoal != null && request.fitnessGoal!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(request.fitnessGoal!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: IronBookAdminColors.slate500)),
                ],
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(request.centerName)),
          Expanded(
            flex: 2,
            child: Text(_formatDateTime(request.requestedStartAt), style: const TextStyle(fontSize: 12)),
          ),
          Expanded(flex: 1, child: Text('${request.durationMinutes} min')),
          Expanded(flex: 1, child: AdminStatusChip(label: request.statusLabel, variant: statusVariant)),
          Expanded(
            flex: 2,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                if (canApprove) _ActionButton(icon: Icons.check, label: 'Approve', onPressed: onApprove),
                if (canReject) _ActionButton(icon: Icons.block, label: 'Reject', onPressed: onReject),
                if (canCancel) _ActionButton(icon: Icons.cancel, label: 'Cancel', onPressed: onCancel),
                _ActionButton(icon: Icons.swap_horiz, label: 'Reassign', onPressed: onReassign),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10))]),
    );
  }
}

class _ReassignTrainerDialog extends StatefulWidget {
  const _ReassignTrainerDialog({
    required this.request,
    required this.trainers,
    required this.currentTrainerId,
  });

  final AdminCoachingRequest request;
  final List<AdminTrainer> trainers;
  final int currentTrainerId;

  @override
  State<_ReassignTrainerDialog> createState() => _ReassignTrainerDialogState();
}

class _ReassignTrainerDialogState extends State<_ReassignTrainerDialog> {
  late AdminTrainer? _selectedTrainer = widget.trainers.firstWhere(
    (trainer) => trainer.id == widget.currentTrainerId,
    orElse: () => widget.trainers.first,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reassign Trainer'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request: ${widget.request.memberName} • ${widget.request.requestedStartAt.toLocal().toString()}'),
            const SizedBox(height: 16),
            const Text('Select a trainer assigned to the same center:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<AdminTrainer>(
              initialValue: _selectedTrainer,
              items: widget.trainers
                  .map(
                    (trainer) => DropdownMenuItem(
                      value: trainer,
                      child: Text(trainer.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (trainer) => setState(() => _selectedTrainer = trainer),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedTrainer == null
              ? null
              : () => Navigator.of(context).pop(_selectedTrainer),
          child: const Text('Reassign'),
        ),
      ],
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
        title = 'Loading requests',
        message = 'Loading coaching requests from the real API...',
        action = null,
        loading = true;

  factory _StatePanel.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Requests could not be loaded',
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
      icon: Icons.inbox_outlined,
      title: activeSearch.isEmpty ? 'No coaching requests found' : 'No matching requests',
      message: activeSearch.isEmpty
          ? 'No coaching requests are available in the database.'
          : 'No requests matched the current search.',
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
      title: 'Coaching Requests',
      child: SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: IronBookAdminColors.slate400),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: IronBookAdminColors.slate500,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
