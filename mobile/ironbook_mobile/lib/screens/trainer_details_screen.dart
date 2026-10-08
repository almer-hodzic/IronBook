import 'package:flutter/material.dart';

import '../models/trainer.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'training_request_screen.dart';

class TrainerDetailsScreen extends StatefulWidget {
  const TrainerDetailsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.trainerId,
    this.initialName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final int trainerId;
  final String? initialName;
  final CenterApiService centerApiService;

  @override
  State<TrainerDetailsScreen> createState() => _TrainerDetailsScreenState();
}

class _TrainerDetailsScreenState extends State<TrainerDetailsScreen> {
  late Future<Trainer> _trainerFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _trainerFuture = widget.centerApiService.getTrainerForCenter(
      widget.centerId,
      widget.trainerId,
    );
  }

  void _retry() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Trainers'),
      children: [
        FutureBuilder<Trainer>(
          future: _trainerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Trainer Profile',
                subtitle: widget.centerName,
                children: const [_StateCard.loading()],
              );
            }

            if (snapshot.hasError) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Trainer Profile',
                subtitle: widget.centerName,
                children: [
                  _StateCard.error(
                    message: snapshot.error.toString(),
                    onRetry: _retry,
                  ),
                ],
              );
            }

            final trainer = snapshot.data;
            if (trainer == null) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Trainer Profile',
                subtitle: widget.centerName,
                children: const [
                  _StateCard(
                    icon: Icons.error_outline,
                    title: 'Trainer details are unavailable',
                    message: 'No trainer data was returned.',
                  ),
                ],
              );
            }

            return _DetailsScaffold(
              title: 'Trainer Profile',
              subtitle: 'Trainer at ${trainer.centerName}.',
              children: [
                _ProfileCard(trainer: trainer),
                if (_hasText(trainer.biography))
                  _InfoCard(
                    icon: Icons.notes_outlined,
                    title: 'Biography',
                    body: trainer.biography!.trim(),
                  ),
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  title: 'Assigned Center',
                  body: '${trainer.centerName}\n${trainer.centerLocation}',
                  muted: true,
                ),
                _InfoCard(
                  icon: Icons.mail_outline,
                  title: 'Contact',
                  body: _contactBody(trainer),
                ),
                _TrainingRequestActionCard(
                  trainer: trainer,
                  centerId: widget.centerId,
                  centerName: widget.centerName,
                  centerApiService: widget.centerApiService,
                  onRequestSubmitted: _retry,
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

  static String _contactBody(Trainer trainer) {
    final phone = trainer.phoneNumber?.trim();
    if (phone == null || phone.isEmpty) {
      return trainer.email;
    }

    return '${trainer.email}\n$phone';
  }
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
          trailing: const IronBookTag(label: 'Coach'),
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.trainer});

  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: IronBookMobileColors.slate100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: IronBookMobileColors.slate200),
            ),
            child: const Icon(
              Icons.person_outline,
              color: IronBookMobileColors.slate700,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trainer.fullName,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${trainer.firstName} ${trainer.lastName}',
                  style: const TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                IronBookTag(
                  label: trainer.centerLocation,
                  variant: IronBookTagVariant.success,
                ),
              ],
            ),
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

class _TrainingRequestActionCard extends StatelessWidget {
  const _TrainingRequestActionCard({
    required this.trainer,
    required this.centerId,
    required this.centerName,
    required this.centerApiService,
    required this.onRequestSubmitted,
  });

  final Trainer trainer;
  final int centerId;
  final String centerName;
  final CenterApiService centerApiService;
  final VoidCallback onRequestSubmitted;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Training Request',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick an exact free time slot and submit a request for this trainer.',
            style: TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          IronBookMobileButton.primary(
            onPressed: () async {
              final submitted = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (context) => TrainingRequestScreen(
                    centerId: centerId,
                    centerName: centerName,
                    trainer: trainer,
                    centerApiService: centerApiService,
                  ),
                ),
              );

              if (submitted == true) {
                onRequestSubmitted();
              }
            },
            label: 'Start Training Request',
            icon: Icons.event_available_outlined,
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(
                Icons.check_circle_outline,
                color: IronBookMobileColors.slate500,
                size: 15,
              ),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Pending requests reserve their selected slot.',
                  style: TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
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
      title = 'Loading trainer',
      message = 'Please wait while trainer details are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Trainer details could not be loaded',
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
