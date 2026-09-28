import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../services/admin_center_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';
import 'center_form_screen.dart';

class CentersManagementScreen extends StatefulWidget {
  const CentersManagementScreen({super.key, required this.centerApiService});

  final AdminCenterApiService centerApiService;

  @override
  State<CentersManagementScreen> createState() =>
      _CentersManagementScreenState();
}

class _CentersManagementScreenState extends State<CentersManagementScreen> {
  late Future<List<AdminCenter>> _centersFuture;
  final _searchController = TextEditingController();
  String _activeSearch = '';

  @override
  void initState() {
    super.initState();
    _centersFuture = widget.centerApiService.getCenters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCenters({String? search}) {
    setState(() {
      _activeSearch = search?.trim() ?? '';
      _centersFuture = widget.centerApiService.getCenters(
        search: _activeSearch,
      );
    });
  }

  Future<void> _openAddCenter() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            CenterFormScreen(centerApiService: widget.centerApiService),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadCenters(search: _activeSearch);
    _showSuccess('Center created.');
  }

  Future<void> _openEditCenter(AdminCenter center) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CenterFormScreen(
          centerId: center.id,
          centerApiService: widget.centerApiService,
        ),
      ),
    );

    if (!mounted || changed != true) {
      return;
    }

    _loadCenters(search: _activeSearch);
    _showSuccess('Center updated.');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Centers Management',
      subtitle: 'Manage center locations, services, and operational status.',
      actions: AdminButton.primary(
        onPressed: _openAddCenter,
        icon: Icons.add,
        label: 'Add New Center',
      ),
      children: [
        _SearchStrip(
          controller: _searchController,
          activeSearch: _activeSearch,
          onSearch: () => _loadCenters(search: _searchController.text),
          onClear: () {
            _searchController.clear();
            _loadCenters();
          },
        ),
        FutureBuilder<List<AdminCenter>>(
          future: _centersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StatePanel.loading();
            }

            if (snapshot.hasError) {
              return _StatePanel.error(
                message: snapshot.error.toString(),
                onRetry: () => _loadCenters(search: _activeSearch),
              );
            }

            final centers = snapshot.data ?? const <AdminCenter>[];
            if (centers.isEmpty) {
              return _StatePanel.empty(
                activeSearch: _activeSearch,
                onRefresh: () => _loadCenters(search: _activeSearch),
              );
            }

            return _CentersPanel(
              centers: centers,
              onEdit: _openEditCenter,
              onRefresh: () => _loadCenters(search: _activeSearch),
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
                hintText: 'Search by name or location',
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

class _CentersPanel extends StatelessWidget {
  const _CentersPanel({
    required this.centers,
    required this.onEdit,
    required this.onRefresh,
  });

  final List<AdminCenter> centers;
  final ValueChanged<AdminCenter> onEdit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Center Locations',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        children: [
          const _CentersHeader(),
          const SizedBox(height: 8),
          for (final center in centers) ...[
            _CenterRow(center: center, onEdit: () => onEdit(center)),
            if (center != centers.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _CentersHeader extends StatelessWidget {
  const _CentersHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 5, child: _HeaderText('Center')),
          Expanded(flex: 3, child: _HeaderText('Capacity')),
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

class _CenterRow extends StatelessWidget {
  const _CenterRow({required this.center, required this.onEdit});

  final AdminCenter center;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
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
                  center.name,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: IronBookAdminColors.slate500,
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        center.location,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: IronBookAdminColors.slate500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_hasText(center.amenities)) ...[
                  const SizedBox(height: 4),
                  Text(
                    center.amenities!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: IronBookAdminColors.slate600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AdminMetricCard(
                label: 'Capacity',
                value: center.capacity > 0
                    ? center.capacity.toString()
                    : 'Not configured',
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
                  label: center.isActive ? 'Active' : 'Inactive',
                  variant: center.isActive
                      ? AdminStatusVariant.success
                      : AdminStatusVariant.neutral,
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
      title = 'Loading centers',
      message = 'Please wait while centers are loaded.',
      action = null,
      loading = true;

  factory _StatePanel.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Centers could not be loaded',
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
      icon: Icons.apartment_outlined,
      title: activeSearch.isEmpty ? 'No centers yet' : 'No matching centers',
      message: activeSearch.isEmpty
          ? 'Create the first center to start managing branch data.'
          : 'No centers matched the current search.',
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
