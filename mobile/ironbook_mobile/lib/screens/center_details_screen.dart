import 'package:flutter/material.dart';

import '../models/center.dart';
import '../services/center_api_service.dart';

class CenterDetailsScreen extends StatefulWidget {
  const CenterDetailsScreen({
    super.key,
    required this.centerId,
    this.initialName,
    required this.centerApiService,
  });

  final int centerId;
  final String? initialName;
  final CenterApiService centerApiService;

  @override
  State<CenterDetailsScreen> createState() => _CenterDetailsScreenState();
}

class _CenterDetailsScreenState extends State<CenterDetailsScreen> {
  late Future<FitnessCenter> _centerFuture;

  @override
  void initState() {
    super.initState();
    _centerFuture = widget.centerApiService.getCenter(widget.centerId);
  }

  void _retry() {
    setState(() {
      _centerFuture = widget.centerApiService.getCenter(widget.centerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialName ?? 'Center details')),
      body: SafeArea(
        child: FutureBuilder<FitnessCenter>(
          future: _centerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _DetailsLoading();
            }

            if (snapshot.hasError) {
              return _DetailsMessage(
                title: 'Center details are unavailable',
                message: snapshot.error.toString(),
                action: FilledButton(
                  onPressed: _retry,
                  child: const Text('Retry'),
                ),
              );
            }

            final center = snapshot.data;
            if (center == null) {
              return const _DetailsMessage(
                title: 'Center details are unavailable',
                message: 'No center data was returned.',
              );
            }

            return _CenterDetailsContent(center: center);
          },
        ),
      ),
    );
  }
}

class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading center details...'),
        ],
      ),
    );
  }
}

class _CenterDetailsContent extends StatelessWidget {
  const _CenterDetailsContent({required this.center});

  final FitnessCenter center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[
      Text(center.name, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.location_on_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(center.location)),
        ],
      ),
    ];

    if (center.capacity != null && center.capacity! > 0) {
      sections.addAll([
        const SizedBox(height: 20),
        _DetailSection(title: 'Capacity', body: center.capacity.toString()),
      ]);
    }

    if (_hasText(center.amenities)) {
      sections.addAll([
        const SizedBox(height: 20),
        _DetailSection(title: 'Amenities', body: center.amenities!.trim()),
      ]);
    }

    if (_hasText(center.notes)) {
      sections.addAll([
        const SizedBox(height: 20),
        _DetailSection(title: 'Notes', body: center.notes!.trim()),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: sections,
    );
  }

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(body),
      ],
    );
  }
}

class _DetailsMessage extends StatelessWidget {
  const _DetailsMessage({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
