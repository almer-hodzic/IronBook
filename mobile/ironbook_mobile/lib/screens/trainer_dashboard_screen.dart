import 'package:flutter/material.dart';

import '../models/trainer_dashboard_request.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'trainer_client_details_screen.dart';

class TrainerDashboardScreen extends StatefulWidget {
  const TrainerDashboardScreen({
    super.key,
    required this.centerApiService,
  });

  final CenterApiService centerApiService;

  @override
  State<TrainerDashboardScreen> createState() => _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState extends State<TrainerDashboardScreen> {
  late Future<List<TrainerDashboardRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _requestsFuture = widget.centerApiService.getTrainerDashboardRequests();
  }

  void _retry() {
    setState(() {
      _requestsFuture = widget.centerApiService.getTrainerDashboardRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Dashboard'),
      children: [
        IronBookMobileHeader(
          title: 'Trainer Dashboard',
          subtitle: 'Your approved coaching requests.',
          trailing: const _StatusBadge(),
        ),
        FutureBuilder<List<TrainerDashboardRequest>>(
          future: _requestsFuture,
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

            final requests = snapshot.data ?? const <TrainerDashboardRequest>[];
            if (requests.isEmpty) {
              return _StateCard.empty(
                title: 'No approved requests',
                message: 'You have no approved coaching requests at the moment.',
                onRetry: _retry,
              );
            }

            return _RequestsSection(requests: requests);
          },
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: IronBookMobileColors.emerald100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 14, color: IronBookMobileColors.emerald700),
          const SizedBox(width: 4),
          Text(
            'Approved',
            style: const TextStyle(
              color: IronBookMobileColors.emerald700,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({required this.requests});

  final List<TrainerDashboardRequest> requests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${requests.length} approved request${requests.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...requests.map((request) => _RequestCard(request: request)),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final TrainerDashboardRequest request;

  @override
  Widget build(BuildContext context) {
    final dateFormat = _DateFormatter();
    final timeFormat = _TimeFormatter();
    final service = context.findAncestorStateOfType<_TrainerDashboardScreenState>()
        ?.widget
        .centerApiService;

    return InkWell(
      onTap: () {
        if (service == null) {
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => TrainerClientDetailsScreen(
              centerApiService: service,
              requestId: request.id,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: IronBookMobileSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: IronBookMobileColors.amber100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    color: IronBookMobileColors.amber700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.memberName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.centerName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IronBookTag(label: request.status, variant: IronBookTagVariant.success),
            ],
          ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.access_time,
              label: dateFormat.format(request.requestedStartAt),
              value: timeFormat.format(request.requestedStartAt),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.timer_outlined,
              label: '${request.durationMinutes} minutes',
              value: 'Session duration',
            ),
          ],
        ),
      ),
    );
  }
}

class _DateFormatter {
  String format(DateTime value) => '${_weekday(value.weekday)}, ${value.day} ${_month(value.month)}';

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

class _TimeFormatter {
  String format(DateTime value) => value.toLocal().format();
}

extension on DateTime {
  String format() {
    final hour = this.hour == 0 ? 12 : this.hour > 12 ? this.hour - 12 : this.hour;
    final minute = this.minute.toString().padLeft(2, '0');
    final period = this.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      children: [
        Icon(icon, size: 18, color: IronBookMobileColors.slate500),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: IronBookMobileColors.slate500,
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard._({
    this.title,
    this.message,
    this.onRetry,
    this.loading = false,
  });

  const _StateCard.loading() : this._(loading: true);

  const _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) : this._(
          title: 'Requests unavailable',
          message: message,
          onRetry: onRetry,
        );

  const _StateCard.empty({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) : this._(title: title, message: message, onRetry: onRetry);

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
            Icons.assignment_turned_in_outlined,
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
