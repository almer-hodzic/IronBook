import 'package:flutter/material.dart';

import '../models/trainer_client_details.dart';
import '../screens/add_training_report_screen.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class TrainerClientDetailsScreen extends StatefulWidget {
  const TrainerClientDetailsScreen({
    super.key,
    required this.centerApiService,
    required this.requestId,
  });

  final CenterApiService centerApiService;
  final int requestId;

  @override
  State<TrainerClientDetailsScreen> createState() =>
      _TrainerClientDetailsScreenState();
}

class _TrainerClientDetailsScreenState extends State<TrainerClientDetailsScreen> {
  late Future<TrainerClientDetails> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = widget.centerApiService.getTrainerClientDetails(
      widget.requestId,
    );
  }

  void _retry() {
    setState(() {
      _detailsFuture = widget.centerApiService.getTrainerClientDetails(
        widget.requestId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Dashboard'),
      children: [
        IronBookMobileHeader(
          title: 'Client Details',
          subtitle: 'Training request information.',
          onBack: () => Navigator.of(context).pop(),
        ),
        FutureBuilder<TrainerClientDetails>(
          future: _detailsFuture,
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

            final details = snapshot.data;
            if (details == null) {
              return const _StateCard.empty(
                title: 'Client details are unavailable',
                message: 'No approved coaching request was returned.',
              );
            }

            return _ClientDetailsSection(
              details: details,
              onTrainingReportAdded: _retry,
            );
          },
        ),
      ],
    );
  }
}

class _ClientDetailsSection extends StatelessWidget {
  const _ClientDetailsSection({
    required this.details,
    required this.onTrainingReportAdded,
  });

  final TrainerClientDetails details;
  final VoidCallback onTrainingReportAdded;

  @override
  Widget build(BuildContext context) {
    final date = details.requestedStartAt.toLocal();
    final dateLabel = '${_weekday(date.weekday)}, ${date.day} ${_month(date.month)}';
    final timeLabel = _formatTime(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IronBookMobileSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.memberName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Approved coaching request',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: IronBookMobileColors.slate500,
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Center',
                value: details.centerName,
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.access_time,
                label: 'Date & time',
                value: '$dateLabel, $timeLabel',
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: '${details.durationMinutes} minutes',
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.flag_outlined,
                label: 'Status',
                value: details.status,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IronBookMobileSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fitness goal',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                details.fitnessGoal?.trim().isNotEmpty == true
                    ? details.fitnessGoal!
                    : 'No fitness goal provided.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IronBookMobileSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Note',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                details.note?.trim().isNotEmpty == true
                    ? details.note!
                    : 'No additional note provided.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (details.status == 'Approved' && !details.hasTrainingReport)
          IronBookMobileButton.primary(
            onPressed: () async {
              final refreshed = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (context) => AddTrainingReportScreen(
                    centerApiService: context
                        .findAncestorStateOfType<_TrainerClientDetailsScreenState>()!
                        .widget
                        .centerApiService,
                    trainingRequestId: details.id,
                  ),
                ),
              );

              if (refreshed == true) {
                onTrainingReportAdded();
              }
            },
            label: 'Add Training Report',
            icon: Icons.assignment_add,
          ),
      ],
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : value.hour > 12 ? value.hour - 12 : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _weekday(int value) => switch (value) {
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        _ => 'Sun',
      };

  String _month(int value) => switch (value) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        _ => 'Dec',
      };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: IronBookMobileColors.slate500),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: IronBookMobileColors.slate500,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard._({
    this.message,
    this.onRetry,
    this.title,
    this.loading = false,
  });

  const _StateCard.loading() : this._(loading: true);

  const _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) : this._(
          title: 'Client details unavailable',
          message: message,
          onRetry: onRetry,
        );

  const _StateCard.empty({
    required String title,
    required String message,
  }) : this._(title: title, message: message);

  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return IronBookMobileSection(
      child: Column(
        children: [
          Icon(
            Icons.person_outline,
            size: 32,
            color: IronBookMobileColors.slate400,
          ),
          const SizedBox(height: 12),
          if (title != null)
            Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
