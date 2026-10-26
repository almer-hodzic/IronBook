import 'package:flutter/material.dart';

import '../models/training_request.dart';
import '../models/paged_result.dart';
import '../widgets/paging_controls.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';

const _statuses = ['Pending', 'Approved', 'Rejected', 'Cancelled'];

class MyTrainingsScreen extends StatefulWidget {
  const MyTrainingsScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<MyTrainingsScreen> createState() => _MyTrainingsScreenState();
}

class _MyTrainingsScreenState extends State<MyTrainingsScreen> {
  List<TrainingRequestResult>? _trainings;
  PagedResult<TrainingRequestResult>? _page;
  int _pageNumber = 1;
  String? _status;
  String? _loadError;
  String? _cancelError;
  String? _success;
  int? _cancellingId;
  bool _loading = false;
  bool _confirming = false;

  bool get _busy => _loading || _confirming || _cancellingId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _cancelError = null;
    });
    try {
      final page = await loadAvailablePage(
        _pageNumber,
        (number) => widget.centerApiService.getMyTrainings(
          status: _status,
          pageNumber: number,
        ),
      );
      if (!mounted) return;
      setState(() {
        _trainings = page.items;
        _page = page;
        _pageNumber = page.pageNumber;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _filter(String? status) {
    if (_busy || status == _status) return;
    setState(() {
      _status = status;
      _pageNumber = 1;
      _success = null;
    });
    _load();
  }

  void _changePage(int number) {
    if (_busy) return;
    _pageNumber = number;
    _load();
  }

  Future<void> _cancel(TrainingRequestResult training) async {
    if (_busy || !_canCancel(training)) return;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel training?'),
        content: Text(
          'Cancel your training with ${training.trainerName} at ${training.centerName} '
          'on ${_sessionLabel(context, training.requestedStartAt)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep training'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel training'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;

    setState(() {
      _cancellingId = training.id;
      _cancelError = null;
      _success = null;
    });
    try {
      final updated = await widget.centerApiService.cancelMyTraining(
        training.id,
      );
      if (!mounted) return;
      setState(() {
        _trainings = _trainings!
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _cancellingId = null;
        _success = 'Training cancelled.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancellingId = null;
        _cancelError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => IronBookMobileShell(
    children: [
      IronBookMobileHeader(
        title: 'My Trainings',
        subtitle: 'Your requests across Iron Core Fitness centers.',
        onBack: () => Navigator.of(context).pop(),
      ),
      IronBookMobileSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in [null, ..._statuses])
                  ChoiceChip(
                    label: Text(status ?? 'All'),
                    selected: _status == status,
                    onSelected: _busy ? null : (_) => _filter(status),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            IronBookMobileButton.secondary(
              onPressed: _busy ? null : _load,
              label: _loadError == null ? 'Refresh' : 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
      if (_success != null)
        Semantics(
          liveRegion: true,
          child: IronBookTag(
            label: _success!,
            variant: IronBookTagVariant.success,
          ),
        ),
      if (_cancelError != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _cancelError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_loadError != null)
        IronBookMobileSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My trainings unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_loadError!),
            ],
          ),
        )
      else if (_trainings != null && _trainings!.isEmpty)
        IronBookMobileSection(
          child: Text(
            _status == null
                ? 'No training requests yet.'
                : 'No ${_status!.toLowerCase()} training requests.',
          ),
        )
      else if (_trainings != null)
        for (final training in _trainings!)
          IronBookMobileSection(
            key: ValueKey('training-${training.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  training.trainerName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  training.centerName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                IronBookTag(
                  label: training.status,
                  variant: _statusVariant(training.status),
                ),
                const SizedBox(height: 10),
                Text(
                  'Date/time: ${_sessionLabel(context, training.requestedStartAt)}',
                ),
                Text('Duration: ${training.durationMinutes} minutes'),
                const SizedBox(height: 10),
                Text(
                  'Fitness goal',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(_textOr(training.fitnessGoal, 'Not provided.')),
                const SizedBox(height: 10),
                Text('Note', style: Theme.of(context).textTheme.titleSmall),
                Text(_textOr(training.note, 'No note recorded.')),
                if (_canCancel(training)) ...[
                  const SizedBox(height: 12),
                  if (_cancellingId == training.id)
                    const LinearProgressIndicator(),
                  IronBookMobileButton.secondary(
                    onPressed: _busy ? null : () => _cancel(training),
                    label: _cancellingId == training.id
                        ? 'Cancelling...'
                        : 'Cancel training',
                    icon: Icons.cancel_outlined,
                  ),
                ],
              ],
            ),
          ),
      if (!_loading && _loadError == null && _page != null)
        PagingControls(
          pageNumber: _page!.pageNumber,
          totalPages: _page!.totalPages,
          busy: _busy,
          onPageChanged: _changePage,
        ),
    ],
  );
}

bool _canCancel(TrainingRequestResult training) =>
    training.status == 'Pending' || training.status == 'Approved';

IronBookTagVariant _statusVariant(String status) => switch (status) {
  'Approved' => IronBookTagVariant.success,
  'Pending' => IronBookTagVariant.warning,
  'Rejected' => IronBookTagVariant.danger,
  _ => IronBookTagVariant.neutral,
};

String _textOr(String? value, String fallback) =>
    value == null || value.trim().isEmpty ? fallback : value;

String _sessionLabel(BuildContext context, DateTime value) {
  // The API stores UTC times; SQL datetime2 can omit the zone when serialized.
  final utc = value.isUtc
      ? value
      : DateTime.utc(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
  final local = utc.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatMediumDate(local)} ${local.year}, '
      '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}
