import 'package:flutter/material.dart';

import '../models/group_training.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'group_training_details_screen.dart';

class GroupTrainingsScreen extends StatefulWidget {
  const GroupTrainingsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final CenterApiService centerApiService;

  @override
  State<GroupTrainingsScreen> createState() => _GroupTrainingsScreenState();
}

class _GroupTrainingsScreenState extends State<GroupTrainingsScreen> {
  late Future<List<GroupTraining>> _trainingsFuture;
  final _searchController = TextEditingController();
  String _activeSearch = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load({String? search}) {
    _activeSearch = search?.trim() ?? '';
    _trainingsFuture = widget.centerApiService.getGroupTrainingsForCenter(
      widget.centerId,
      search: _activeSearch,
    );
  }

  void _retry() {
    setState(() => _load(search: _activeSearch));
  }

  Future<void> _openTraining(GroupTraining training) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupTrainingDetailsScreen(
          centerId: widget.centerId,
          centerName: widget.centerName,
          groupTrainingId: training.id,
          initialName: training.name,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
    if (mounted) {
      _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Classes'),
      children: [
        IronBookMobileHeader(
          title: 'Group Trainings',
          subtitle: 'Available classes at ${widget.centerName}.',
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Center Classes'),
        ),
        _SearchCard(
          controller: _searchController,
          activeSearch: _activeSearch,
          onSearch: () {
            setState(() => _load(search: _searchController.text));
          },
          onClear: () {
            _searchController.clear();
            setState(_load);
          },
        ),
        FutureBuilder<List<GroupTraining>>(
          future: _trainingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StateCard.loading();
            }

            if (snapshot.hasError) {
              return _StateCard.error(
                message: snapshot.error.toString(),
                onRetry: _retry,
              );
            }

            final trainings = snapshot.data ?? const <GroupTraining>[];
            if (trainings.isEmpty) {
              return _StateCard.empty(
                activeSearch: _activeSearch,
                onRetry: _retry,
              );
            }

            return Column(
              children: [
                for (final training in trainings) ...[
                  _TrainingCard(
                    training: training,
                    onTap: () => _openTraining(training),
                  ),
                  if (training != trainings.last) const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
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
    return IronBookMobileSection(
      muted: true,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search class or trainer',
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: activeSearch.isEmpty ? 'Clear' : 'Clear search',
            onPressed: onClear,
            icon: const Icon(Icons.clear, size: 18),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: onSearch,
            icon: const Icon(Icons.search, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.training, required this.onTap});

  final GroupTraining training;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: IronBookMobileColors.slate200),
            boxShadow: [
              BoxShadow(
                color: IronBookMobileColors.slate900.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        training.name,
                        style: const TextStyle(
                          color: IronBookMobileColors.slate800,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IronBookTag(
                      label: training.availableSpots <= 3
                          ? '${training.availableSpots} left'
                          : training.category,
                      variant: training.availableSpots <= 3
                          ? IronBookTagVariant.warning
                          : IronBookTagVariant.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatDateTime(training.startsAt.toLocal())} / ${training.durationMinutes} min',
                  style: const TextStyle(
                    color: IronBookMobileColors.slate700,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Coach ${training.trainerName} / ${training.difficulty}',
                  style: const TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 12,
                  ),
                ),
                if (_hasText(training.description)) ...[
                  const SizedBox(height: 9),
                  Text(
                    training.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: IronBookMobileColors.slate600,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    IronBookTag(
                      label: '${training.enrolledCount}/${training.capacity}',
                      variant: IronBookTagVariant.success,
                    ),
                    const Spacer(),
                    IronBookMobileButton.primary(
                      onPressed: onTap,
                      label: 'View Details',
                      icon: Icons.arrow_forward,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  }) : loading = false;

  const _StateCard.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading group trainings',
      message = 'Please wait while center classes are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Group trainings could not be loaded',
      message: message,
      onRetry: onRetry,
    );
  }

  factory _StateCard.empty({
    required String activeSearch,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.fitness_center,
      title: activeSearch.isEmpty
          ? 'No available classes'
          : 'No matching classes',
      message: activeSearch.isEmpty
          ? 'This center has no future active group trainings with open capacity.'
          : 'No classes matched the current search.',
      onRetry: onRetry,
    );
  }

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, color: IronBookMobileColors.slate600, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            IronBookMobileButton.primary(
              onPressed: onRetry,
              label: 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
