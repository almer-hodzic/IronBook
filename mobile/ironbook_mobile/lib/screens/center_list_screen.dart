import 'package:flutter/material.dart';

import '../models/center.dart';
import '../services/center_api_service.dart';
import 'center_details_screen.dart';

class CenterListScreen extends StatefulWidget {
  const CenterListScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<CenterListScreen> createState() => _CenterListScreenState();
}

class _CenterListScreenState extends State<CenterListScreen> {
  late Future<List<FitnessCenter>> _centersFuture;
  int? _selectedCenterId;

  @override
  void initState() {
    super.initState();
    _centersFuture = widget.centerApiService.getCenters();
  }

  void _retry() {
    setState(() {
      _centersFuture = widget.centerApiService.getCenters();
    });
  }

  Future<void> _openCenter(FitnessCenter center) async {
    setState(() {
      _selectedCenterId = center.id;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CenterDetailsScreen(
          centerId: center.id,
          initialName: center.name,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('IronBook')),
      body: FutureBuilder<List<FitnessCenter>>(
        future: _centersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _CenterListMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Centers could not be loaded',
              message: snapshot.error.toString(),
              action: FilledButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            );
          }

          final centers = snapshot.data ?? const <FitnessCenter>[];
          if (centers.isEmpty) {
            return _CenterListMessage(
              icon: Icons.location_off_outlined,
              title: 'No active centers',
              message: 'There are no active IronBook centers available right now.',
              action: OutlinedButton(
                onPressed: _retry,
                child: const Text('Refresh'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: centers.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Available fitness centers', style: theme.textTheme.headlineSmall),
                      if (_selectedCenterId != null) ...[
                        const SizedBox(height: 8),
                        Text('Selected center ID: $_selectedCenterId', style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                );
              }

              final center = centers[index - 1];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text(center.name),
                  subtitle: Text(center.location),
                  trailing: const Icon(Icons.chevron_right),
                  selected: center.id == _selectedCenterId,
                  onTap: () => _openCenter(center),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CenterListMessage extends StatelessWidget {
  const _CenterListMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}
