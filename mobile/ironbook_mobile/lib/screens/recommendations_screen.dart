import 'package:flutter/material.dart';

import '../models/member_recommendations.dart';
import '../models/training_preferences.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'group_training_details_screen.dart';
import 'trainer_details_screen.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final CenterApiService centerApiService;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  late Future<MemberRecommendations> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecommendationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerId != widget.centerId ||
        oldWidget.centerApiService != widget.centerApiService) {
      _load();
    }
  }

  void _load() {
    _recommendationsFuture = widget.centerApiService
        .getRecommendationsForCenter(widget.centerId);
  }

  void _retry() => setState(_load);

  Future<void> _openTrainer(TrainerRecommendation trainer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrainerDetailsScreen(
          centerId: widget.centerId,
          centerName: widget.centerName,
          trainerId: trainer.id,
          initialName: trainer.name,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
    if (mounted) _retry();
  }

  Future<void> _openTraining(GroupTrainingRecommendation training) async {
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
    if (mounted) _retry();
  }

  @override
  Widget build(BuildContext context) => IronBookMobileShell(
    children: [
      IronBookMobileHeader(
        title: 'Recommendations',
        subtitle: widget.centerName,
        onBack: () => Navigator.of(context).pop(),
      ),
      FutureBuilder<MemberRecommendations>(
        future: _recommendationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return IronBookMobileSection(
              child: Column(
                children: [
                  Text(
                    'Recommendations unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error?.toString() ??
                        'No recommendations data was returned.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  IronBookMobileButton.primary(
                    onPressed: _retry,
                    label: 'Retry',
                    icon: Icons.refresh,
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IronBookTag(
                    label: data.isPersonalized
                        ? 'Personalized'
                        : 'Popular at this center',
                  ),
                  IronBookMobileButton.secondary(
                    onPressed: _retry,
                    label: 'Refresh',
                    icon: Icons.refresh,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Recommended trainers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (data.trainers.isEmpty)
                const IronBookMobileSection(
                  child: Text(
                    'No trainer recommendations available for this center.',
                  ),
                ),
              for (final trainer in data.trainers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IronBookMobileSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trainer.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (trainer.categories.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final category in trainer.categories)
                                IronBookTag(label: _categoryLabel(category)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Approved coaching requests: ${trainer.approvedCoachingRequestCount}',
                        ),
                        if (trainer.similarity != null)
                          _score(trainer.similarity!),
                        if (trainer.reasons.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _RecommendationReasons(
                            key: ValueKey('trainer-reasons-${trainer.id}'),
                            reasons: trainer.reasons,
                          ),
                        ],
                        const SizedBox(height: 8),
                        IronBookMobileButton.secondary(
                          onPressed: () => _openTrainer(trainer),
                          label: 'View trainer',
                          icon: Icons.person_outline,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Recommended group trainings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (data.groupTrainings.isEmpty)
                const IronBookMobileSection(
                  child: Text(
                    'No group training recommendations available for this center.',
                  ),
                ),
              for (final training in data.groupTrainings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IronBookMobileSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          training.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        IronBookTag(label: _categoryLabel(training.category)),
                        const SizedBox(height: 8),
                        Text('Trainer: ${training.trainerName}'),
                        Text(
                          'Session: ${_sessionLabel(context, training.startsAt)}',
                        ),
                        Text(
                          'Enrolled: ${training.enrollmentCount}/${training.capacity}',
                        ),
                        if (training.similarity != null)
                          _score(training.similarity!),
                        if (training.reasons.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _RecommendationReasons(
                            key: ValueKey('group-reasons-${training.id}'),
                            reasons: training.reasons,
                          ),
                        ],
                        const SizedBox(height: 8),
                        IronBookMobileButton.secondary(
                          onPressed: () => _openTraining(training),
                          label: 'View group training',
                          icon: Icons.fitness_center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _RecommendationReasons extends StatelessWidget {
  const _RecommendationReasons({super.key, required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final reason in reasons)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
}

Widget _score(double similarity) =>
    Text('Recommendation score: ${similarity.toStringAsFixed(3)}');

String _categoryLabel(String category) =>
    trainingPreferenceInterests[category] ?? category;

String _sessionLabel(BuildContext context, DateTime dateTime) {
  final local = dateTime.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatMediumDate(local)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}
