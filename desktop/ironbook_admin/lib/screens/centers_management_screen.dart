import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../services/admin_center_api_service.dart';
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
    final theme = Theme.of(context);

    return Container(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Centers Management',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage branch records stored in the IronBook database.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openAddCenter,
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Center'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SearchBar(
                controller: _searchController,
                onSearch: () => _loadCenters(search: _searchController.text),
                onClear: () {
                  _searchController.clear();
                  _loadCenters();
                },
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<List<AdminCenter>>(
                  future: _centersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _CenteredMessage.loading();
                    }

                    if (snapshot.hasError) {
                      return _CenteredMessage.error(
                        message: snapshot.error.toString(),
                        onRetry: () => _loadCenters(search: _activeSearch),
                      );
                    }

                    final centers = snapshot.data ?? const <AdminCenter>[];
                    if (centers.isEmpty) {
                      return _CenteredMessage.empty(
                        activeSearch: _activeSearch,
                        onRefresh: () => _loadCenters(search: _activeSearch),
                      );
                    }

                    return _CentersTable(
                      centers: centers,
                      onEdit: _openEditCenter,
                      onRefresh: () => _loadCenters(search: _activeSearch),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSearch,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search centers',
              hintText: 'Search by name or location',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Search'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
        ),
      ],
    );
  }
}

class _CentersTable extends StatelessWidget {
  const _CentersTable({
    required this.centers,
    required this.onEdit,
    required this.onRefresh,
  });

  final List<AdminCenter> centers;
  final ValueChanged<AdminCenter> onEdit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE3EA)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Row(
              children: [
                Text('${centers.length} centers'),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Location')),
                    DataColumn(label: Text('Capacity')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final center in centers)
                      DataRow(
                        cells: [
                          DataCell(Text(center.name)),
                          DataCell(Text(center.location)),
                          DataCell(
                            Text(
                              center.capacity > 0
                                  ? center.capacity.toString()
                                  : 'Not configured',
                            ),
                          ),
                          DataCell(_StatusChip(isActive: center.isActive)),
                          DataCell(
                            TextButton.icon(
                              onPressed: () => onEdit(center),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final background = isActive
        ? const Color(0xFFE2F5EA)
        : const Color(0xFFF1F3F6);
    final foreground = isActive
        ? const Color(0xFF176B3A)
        : const Color(0xFF5C6673);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _CenteredMessage.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading centers',
      message = 'Please wait while centers are loaded.',
      action = null,
      loading = true;

  factory _CenteredMessage.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _CenteredMessage(
      icon: Icons.cloud_off_outlined,
      title: 'Centers could not be loaded',
      message: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    );
  }

  factory _CenteredMessage.empty({
    required String activeSearch,
    required VoidCallback onRefresh,
  }) {
    return _CenteredMessage(
      icon: Icons.apartment_outlined,
      title: activeSearch.isEmpty ? 'No centers yet' : 'No matching centers',
      message: activeSearch.isEmpty
          ? 'Create the first center to start managing branch data.'
          : 'No centers matched the current search.',
      action: OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
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
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 44, color: const Color(0xFF607089)),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
