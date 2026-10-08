import 'package:flutter/material.dart';

import '../models/trainer.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'trainer_details_screen.dart';

class TrainersScreen extends StatefulWidget {
  const TrainersScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final CenterApiService centerApiService;

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  late Future<List<Trainer>> _trainersFuture;
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
    _trainersFuture = widget.centerApiService.getTrainersForCenter(
      widget.centerId,
      search: _activeSearch,
    );
  }

  void _retry() {
    setState(() => _load(search: _activeSearch));
  }

  Future<void> _openTrainer(Trainer trainer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrainerDetailsScreen(
          centerId: widget.centerId,
          centerName: widget.centerName,
          trainerId: trainer.id,
          initialName: trainer.fullName,
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
      bottomNav: const IronBookBottomNav(activeLabel: 'Trainers'),
      children: [
        IronBookMobileHeader(
          title: 'Trainers',
          subtitle: 'Available trainers at ${widget.centerName}.',
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Coach Network'),
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
        FutureBuilder<List<Trainer>>(
          future: _trainersFuture,
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

            final trainers = snapshot.data ?? const <Trainer>[];
            if (trainers.isEmpty) {
              return _StateCard.empty(
                activeSearch: _activeSearch,
                onRetry: _retry,
              );
            }

            return Column(
              children: [
                for (final trainer in trainers) ...[
                  _TrainerCard(
                    trainer: trainer,
                    onTap: () => _openTrainer(trainer),
                  ),
                  if (trainer != trainers.last) const SizedBox(height: 10),
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
                hintText: 'Search trainer name or email',
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

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({required this.trainer, required this.onTap});

  final Trainer trainer;
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
                    _TrainerAvatar(name: trainer.fullName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trainer.fullName,
                            style: const TextStyle(
                              color: IronBookMobileColors.slate800,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            trainer.email,
                            style: const TextStyle(
                              color: IronBookMobileColors.slate500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const IronBookTag(label: 'Coach'),
                  ],
                ),
                if (_hasText(trainer.biography)) ...[
                  const SizedBox(height: 10),
                  Text(
                    trainer.biography!.trim(),
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
                      label: trainer.centerLocation,
                      variant: IronBookTagVariant.success,
                    ),
                    const Spacer(),
                    IronBookMobileButton.secondary(
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

class _TrainerAvatar extends StatelessWidget {
  const _TrainerAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.trim()[0].toUpperCase())
        .join();

    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronBookMobileColors.slate100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IronBookMobileColors.slate200),
      ),
      child: Text(
        initials.isEmpty ? 'TR' : initials,
        style: const TextStyle(
          color: IronBookMobileColors.slate700,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
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
      title = 'Loading trainers',
      message = 'Please wait while center trainers are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Trainers could not be loaded',
      message: message,
      onRetry: onRetry,
    );
  }

  factory _StateCard.empty({
    required String activeSearch,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.groups_outlined,
      title: activeSearch.isEmpty ? 'No available trainers' : 'No trainers',
      message: activeSearch.isEmpty
          ? 'This center has no active trainers assigned right now.'
          : 'No active trainers matched the current search.',
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
