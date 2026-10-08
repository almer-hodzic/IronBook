import 'package:flutter/material.dart';

import '../models/trainer.dart';
import '../models/training_request.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class TrainingRequestScreen extends StatefulWidget {
  const TrainingRequestScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.trainer,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final Trainer trainer;
  final CenterApiService centerApiService;

  @override
  State<TrainingRequestScreen> createState() => _TrainingRequestScreenState();
}

class _TrainingRequestScreenState extends State<TrainingRequestScreen> {
  late Future<List<TrainingAvailabilityDay>> _availabilityFuture;
  final _goalController = TextEditingController();
  final _noteController = TextEditingController();
  String? _selectedDate;
  TrainingAvailabilitySlot? _selectedSlot;
  TrainingRequestResult? _submittedRequest;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _goalController.text = 'Strength and conditioning';
    _load();
  }

  @override
  void dispose() {
    _goalController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _load() {
    _availabilityFuture = widget.centerApiService.getTrainerAvailability(
      centerId: widget.centerId,
      trainerId: widget.trainer.id,
    );
  }

  void _retry() {
    setState(() {
      _submittedRequest = null;
      _load();
    });
  }

  void _selectDate(TrainingAvailabilityDay day) {
    TrainingAvailabilitySlot? firstFreeSlot;
    for (final slot in day.slots) {
      if (slot.isAvailable) {
        firstFreeSlot = slot;
        break;
      }
    }

    if (firstFreeSlot == null) {
      return;
    }

    setState(() {
      _selectedDate = day.date;
      _selectedSlot = firstFreeSlot;
    });
  }

  void _selectSlot(TrainingAvailabilitySlot slot) {
    if (!slot.isAvailable) {
      return;
    }

    setState(() {
      _selectedDate = slot.date;
      _selectedSlot = slot;
    });
  }

  Future<void> _submit() async {
    final slot = _selectedSlot;
    if (slot == null || !slot.isAvailable || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = await widget.centerApiService.createTrainingRequest(
        centerId: widget.centerId,
        trainerId: widget.trainer.id,
        requestedStartAt: slot.startsAt,
        fitnessGoal: _goalController.text,
        note: _noteController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submittedRequest = request;
        _selectedSlot = null;
        _load();
      });
    } on CenterApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Trainers'),
      children: [
        IronBookMobileHeader(
          title: 'Training Request',
          subtitle: '${widget.trainer.fullName} at ${widget.centerName}.',
          onBack: () => Navigator.of(context).pop(_submittedRequest != null),
          trailing: const IronBookTag(label: 'Slot Setup'),
        ),
        _SummaryCard(trainer: widget.trainer, centerName: widget.centerName),
        FutureBuilder<List<TrainingAvailabilityDay>>(
          future: _availabilityFuture,
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

            final days = snapshot.data ?? const <TrainingAvailabilityDay>[];
            if (days.isEmpty) {
              return _StateCard.error(
                message: 'No availability was returned for this trainer.',
                onRetry: _retry,
              );
            }

            final selectedDate = _selectedDate ?? _firstAvailableDate(days);
            final selectedDay = days.firstWhere(
              (day) => day.date == selectedDate,
              orElse: () => days.first,
            );
            final selectedSlot = _selectedSlot?.date == selectedDay.date
                ? _selectedSlot
                : null;

            return Column(
              children: [
                if (_submittedRequest != null) ...[
                  _ConfirmationCard(request: _submittedRequest!),
                  const SizedBox(height: 10),
                ],
                _AvailabilityCard(
                  days: days,
                  selectedDay: selectedDay,
                  selectedSlot: selectedSlot,
                  onSelectDay: _selectDate,
                  onSelectSlot: _selectSlot,
                ),
                const SizedBox(height: 10),
                _RequestDetailsCard(
                  goalController: _goalController,
                  noteController: _noteController,
                ),
                const SizedBox(height: 10),
                _SubmitCard(
                  selectedSlot: selectedSlot,
                  isSubmitting: _isSubmitting,
                  onSubmit: _submit,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String? _firstAvailableDate(List<TrainingAvailabilityDay> days) {
    for (final day in days) {
      if (day.slots.any((slot) => slot.isAvailable)) {
        return day.date;
      }
    }

    return days.isEmpty ? null : days.first.date;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.trainer, required this.centerName});

  final Trainer trainer;
  final String centerName;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request Summary',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _SummaryLine(label: 'Trainer', value: trainer.fullName),
          _SummaryLine(label: 'Center', value: centerName),
          _SummaryLine(label: 'Location', value: trainer.centerLocation),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
        style: const TextStyle(
          color: IronBookMobileColors.slate600,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.days,
    required this.selectedDay,
    required this.selectedSlot,
    required this.onSelectDay,
    required this.onSelectSlot,
  });

  final List<TrainingAvailabilityDay> days;
  final TrainingAvailabilityDay selectedDay;
  final TrainingAvailabilitySlot? selectedSlot;
  final ValueChanged<TrainingAvailabilityDay> onSelectDay;
  final ValueChanged<TrainingAvailabilitySlot> onSelectSlot;

  @override
  Widget build(BuildContext context) {
    final openSlots = days.fold<int>(
      0,
      (total, day) =>
          total + day.slots.where((slot) => slot.isAvailable).length,
    );
    final busySlots = days.fold<int>(
      0,
      (total, day) =>
          total + day.slots.where((slot) => !slot.isAvailable).length,
    );

    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trainer Availability',
                      style: TextStyle(
                        color: IronBookMobileColors.slate800,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Green slots are free. Red slots are booked or unavailable.',
                      style: TextStyle(
                        color: IronBookMobileColors.slate500,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IronBookTag(
                label: '$openSlots Free',
                variant: IronBookTagVariant.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(label: 'Free', value: openSlots),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Metric(label: 'Booked', value: busySlots, danger: true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _DayButton(
                      day: day,
                      selected: day.date == selectedDay.date,
                      onTap: () => onSelectDay(day),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _Legend(color: IronBookMobileColors.emerald700, label: 'Free'),
              SizedBox(width: 12),
              _Legend(color: IronBookMobileColors.rose700, label: 'Booked'),
            ],
          ),
          const SizedBox(height: 12),
          for (final period in ['Morning', 'Midday', 'Evening']) ...[
            _PeriodSlots(
              period: period,
              slots: selectedDay.slots
                  .where((slot) => slot.period == period)
                  .toList(growable: false),
              selectedSlot: selectedSlot,
              onSelectSlot: onSelectSlot,
            ),
            if (period != 'Evening') const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final int value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronBookMobileColors.slate200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: IronBookMobileColors.slate500,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.toString(),
              style: TextStyle(
                color: danger
                    ? IronBookMobileColors.rose700
                    : IronBookMobileColors.emerald700,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final TrainingAvailabilityDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final openCount = day.slots.where((slot) => slot.isAvailable).length;
    final disabled = openCount == 0;

    return OutlinedButton(
      onPressed: disabled ? null : onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        backgroundColor: selected
            ? Colors.white
            : IronBookMobileColors.surfaceMuted,
        foregroundColor: disabled
            ? IronBookMobileColors.rose700
            : IronBookMobileColors.slate700,
        side: BorderSide(
          color: selected
              ? IronBookMobileColors.slate900
              : disabled
              ? IronBookMobileColors.rose100
              : IronBookMobileColors.slate200,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        children: [
          Text(day.dayLabel, style: const TextStyle(fontSize: 10)),
          Text(
            day.dateLabel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text(day.monthLabel, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: IronBookMobileColors.slate500,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PeriodSlots extends StatelessWidget {
  const _PeriodSlots({
    required this.period,
    required this.slots,
    required this.selectedSlot,
    required this.onSelectSlot,
  });

  final String period;
  final List<TrainingAvailabilitySlot> slots;
  final TrainingAvailabilitySlot? selectedSlot;
  final ValueChanged<TrainingAvailabilitySlot> onSelectSlot;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period.toUpperCase(),
          style: const TextStyle(
            color: IronBookMobileColors.slate500,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final slot in slots)
              _SlotButton(
                slot: slot,
                selected: selectedSlot?.startsAt == slot.startsAt,
                onTap: () => onSelectSlot(slot),
              ),
          ],
        ),
      ],
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final TrainingAvailabilitySlot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = !slot.isAvailable
        ? IronBookMobileColors.rose100
        : selected
        ? IronBookMobileColors.slate900
        : IronBookMobileColors.emerald100;
    final fg = !slot.isAvailable
        ? IronBookMobileColors.rose700
        : selected
        ? Colors.white
        : IronBookMobileColors.emerald700;
    final border = !slot.isAvailable
        ? IronBookMobileColors.rose100
        : selected
        ? IronBookMobileColors.slate900
        : const Color(0xFFA7F3D0);

    return OutlinedButton.icon(
      onPressed: slot.isAvailable ? onTap : null,
      icon: Icon(
        slot.isAvailable ? Icons.check_circle_outline : Icons.cancel_outlined,
        size: 16,
      ),
      label: Text(slot.time),
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RequestDetailsCard extends StatelessWidget {
  const _RequestDetailsCard({
    required this.goalController,
    required this.noteController,
  });

  final TextEditingController goalController;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request Details',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: goalController,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Fitness goal',
              prefixIcon: Icon(Icons.flag_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Note for trainer',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitCard extends StatelessWidget {
  const _SubmitCard({
    required this.selectedSlot,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TrainingAvailabilitySlot? selectedSlot;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canSubmit = selectedSlot?.isAvailable == true && !isSubmitting;

    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedSlot == null
                ? 'Select a free green slot to continue.'
                : 'Selected: ${selectedSlot!.date} at ${selectedSlot!.time}',
            style: const TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          IronBookMobileButton.primary(
            onPressed: canSubmit ? onSubmit : null,
            label: isSubmitting ? 'Submitting...' : 'Submit Request',
            icon: Icons.send_outlined,
          ),
        ],
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.request});

  final TrainingRequestResult request;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.check_circle_outline,
                color: IronBookMobileColors.emerald700,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Request Submitted',
                  style: TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IronBookTag(
                label: 'Pending',
                variant: IronBookTagVariant.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${request.trainerName} / ${_formatDateTime(request.requestedStartAt)}',
            style: const TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 12,
              height: 1.45,
            ),
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
      title = 'Loading availability',
      message = 'Please wait while trainer slots are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Availability could not be loaded',
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
  final local = value.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
