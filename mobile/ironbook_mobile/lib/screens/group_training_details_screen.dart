import 'package:flutter/material.dart';

import '../models/group_training.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class GroupTrainingDetailsScreen extends StatefulWidget {
  const GroupTrainingDetailsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.groupTrainingId,
    this.initialName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final int groupTrainingId;
  final String? initialName;
  final CenterApiService centerApiService;

  @override
  State<GroupTrainingDetailsScreen> createState() =>
      _GroupTrainingDetailsScreenState();
}

class _GroupTrainingDetailsScreenState
    extends State<GroupTrainingDetailsScreen> {
  late Future<GroupTraining> _trainingFuture;
  bool _isEnrolling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _trainingFuture = widget.centerApiService.getGroupTrainingForCenter(
      widget.centerId,
      widget.groupTrainingId,
    );
  }

  void _retry() {
    setState(_load);
  }

  Future<void> _enroll() async {
    setState(() => _isEnrolling = true);

    try {
      await widget.centerApiService.enrollGroupTraining(
        centerId: widget.centerId,
        groupTrainingId: widget.groupTrainingId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Enrollment confirmed.')));
      _retry();
    } on CenterApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isEnrolling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Classes'),
      children: [
        FutureBuilder<GroupTraining>(
          future: _trainingFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Group Training',
                subtitle: widget.centerName,
                children: const [_StateCard.loading()],
              );
            }

            if (snapshot.hasError) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Group Training',
                subtitle: widget.centerName,
                children: [
                  _StateCard.error(
                    message: snapshot.error.toString(),
                    onRetry: _retry,
                  ),
                ],
              );
            }

            final training = snapshot.data;
            if (training == null) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Group Training',
                subtitle: widget.centerName,
                children: const [
                  _StateCard(
                    icon: Icons.error_outline,
                    title: 'Class details are unavailable',
                    message: 'No class data was returned.',
                  ),
                ],
              );
            }

            return _DetailsScaffold(
              title: training.name,
              subtitle: training.centerName,
              children: [
                _HeroCard(training: training),
                _InfoCard(
                  icon: Icons.schedule,
                  title: 'Schedule',
                  body:
                      '${_formatDateTime(training.startsAt.toLocal())}\n${training.durationMinutes} minutes with ${training.trainerName}',
                ),
                if (_hasText(training.description))
                  _InfoCard(
                    icon: Icons.notes_outlined,
                    title: 'Overview',
                    body: training.description!.trim(),
                  ),
                if (_hasText(training.includes))
                  _InfoCard(
                    icon: Icons.check_circle_outline,
                    title: 'Includes',
                    body: training.includes!.trim(),
                    muted: true,
                  ),
                if (_hasText(training.whoFor))
                  _InfoCard(
                    icon: Icons.person_search_outlined,
                    title: 'Who It Is For',
                    body: training.whoFor!.trim(),
                  ),
                _EnrollmentCard(
                  training: training,
                  isEnrolling: _isEnrolling,
                  onEnroll: _enroll,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _DetailsScaffold extends StatelessWidget {
  const _DetailsScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IronBookMobileHeader(
          title: title,
          subtitle: subtitle,
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Class Details'),
        ),
        const SizedBox(height: 10),
        ..._withSpacing(children),
      ],
    );
  }

  static List<Widget> _withSpacing(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        spaced.add(const SizedBox(height: 10));
      }
      spaced.add(children[index]);
    }
    return spaced;
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.training});

  final GroupTraining training;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
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
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              IronBookTag(
                label: training.isEnrolled ? 'Joined' : training.category,
                variant: training.isEnrolled
                    ? IronBookTagVariant.success
                    : IronBookTagVariant.accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${training.difficulty} / ${training.availableSpots} spots left',
            style: const TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: training.capacity == 0
                ? 0
                : training.enrolledCount / training.capacity,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: IronBookMobileColors.slate200,
            color: IronBookMobileColors.emerald700,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: muted,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: IronBookMobileColors.emerald700, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate600,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentCard extends StatelessWidget {
  const _EnrollmentCard({
    required this.training,
    required this.isEnrolling,
    required this.onEnroll,
  });

  final GroupTraining training;
  final bool isEnrolling;
  final VoidCallback onEnroll;

  @override
  Widget build(BuildContext context) {
    final canEnroll =
        !training.isEnrolled &&
        training.status == 'Active' &&
        training.availableSpots > 0;

    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enrollment',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            training.isEnrolled
                ? 'You are enrolled in this class.'
                : 'Reserve your spot while capacity is available.',
            style: const TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          IronBookMobileButton.primary(
            onPressed: canEnroll && !isEnrolling ? onEnroll : null,
            label: isEnrolling
                ? 'Joining...'
                : training.isEnrolled
                ? 'Joined'
                : 'Join Training',
            icon: training.isEnrolled ? Icons.check_circle_outline : Icons.add,
          ),
        ],
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
      title = 'Loading group training',
      message = 'Please wait while class details are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Class details could not be loaded',
      message: message,
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
