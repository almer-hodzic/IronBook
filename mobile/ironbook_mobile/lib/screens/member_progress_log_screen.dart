import 'package:flutter/material.dart';

import '../models/member_progress_log.dart';
import '../models/paged_result.dart';
import '../widgets/paging_controls.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';

class MemberProgressLogScreen extends StatefulWidget {
  const MemberProgressLogScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<MemberProgressLogScreen> createState() =>
      _MemberProgressLogScreenState();
}

class _MemberProgressLogScreenState extends State<MemberProgressLogScreen> {
  late Future<PagedResult<MemberProgressLog>> _reportsFuture;
  int _pageNumber = 1;
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _filterError;

  @override
  void initState() {
    super.initState();
    _reportsFuture = widget.centerApiService.getMemberProgressLog();
  }

  void _load({bool resetPage = false}) {
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      setState(() => _filterError = 'From date cannot be after To date.');
      return;
    }
    setState(() {
      _filterError = null;
      if (resetPage) _pageNumber = 1;
      _reportsFuture = loadAvailablePage(
        _pageNumber,
        (number) => widget.centerApiService.getMemberProgressLog(
          fromDate: _fromDate,
          toDate: _toDate,
          pageNumber: number,
        ),
      );
    });
  }

  Future<void> _pickDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (from ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (from) {
        _fromDate = selected;
      } else {
        _toDate = selected;
      }
    });
    _load(resetPage: true);
  }

  void _clear() {
    _fromDate = null;
    _toDate = null;
    _load(resetPage: true);
  }

  Widget _dateFilter({required bool from}) {
    final date = from ? _fromDate : _toDate;
    final label = from ? 'From' : 'To';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IronBookMobileButton.secondary(
          onPressed: () => _pickDate(from: from),
          icon: Icons.calendar_today_outlined,
          label: '$label: ${date == null ? 'Any date' : _dateLabel(date)}',
        ),
        if (date != null)
          IconButton(
            tooltip: 'Clear $label date',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              if (from) {
                _fromDate = null;
              } else {
                _toDate = null;
              }
              _load(resetPage: true);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      children: [
        IronBookMobileHeader(
          title: 'Progress Log',
          subtitle: 'Your training reports, newest first.',
          onBack: () => Navigator.of(context).pop(),
        ),
        IronBookMobileSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Training dates',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [_dateFilter(from: true), _dateFilter(from: false)],
              ),
              if (_filterError != null)
                Text(
                  _filterError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (_fromDate != null || _toDate != null)
                    IronBookMobileButton.secondary(
                      onPressed: _clear,
                      label: 'Clear filters',
                    ),
                  IronBookMobileButton.secondary(
                    onPressed: _load,
                    label: 'Refresh',
                    icon: Icons.refresh,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_filterError == null)
          FutureBuilder<PagedResult<MemberProgressLog>>(
            future: _reportsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return IronBookMobileSection(
                  child: Column(
                    children: [
                      Text(
                        'Progress log unavailable',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      IronBookMobileButton.primary(
                        onPressed: _load,
                        label: 'Retry',
                        icon: Icons.refresh,
                      ),
                    ],
                  ),
                );
              }
              final page = snapshot.requireData;
              _pageNumber = page.pageNumber;
              final reports = page.items;
              final controls = PagingControls(
                pageNumber: page.pageNumber,
                totalPages: page.totalPages,
                onPageChanged: (number) {
                  _pageNumber = number;
                  _load();
                },
              );
              if (reports.isEmpty) {
                return Column(
                  children: [
                    IronBookMobileSection(
                      child: Text(
                        _fromDate != null || _toDate != null
                            ? 'No training reports match these dates.'
                            : 'No training reports yet. Your trainer reports will appear here.',
                      ),
                    ),
                    controls,
                  ],
                );
              }
              return Column(
                children: [
                  for (final report in reports)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReportCard(report: report),
                    ),
                  controls,
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final MemberProgressLog report;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IronBookTag(label: _dateLabel(report.trainingDate)),
          const SizedBox(height: 10),
          Text(
            report.trainerName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(report.centerName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text('Report notes', style: Theme.of(context).textTheme.titleSmall),
          Text(_notes(report.reportNotes)),
          const SizedBox(height: 12),
          Text('Exercises', style: Theme.of(context).textTheme.titleSmall),
          if (report.exercises.isEmpty) const Text('No exercises recorded.'),
          for (final exercise in report.exercises) ...[
            const Divider(height: 20),
            Text(
              exercise.exerciseName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('Sets: ${exercise.sets}  •  Reps: ${exercise.reps}'),
            Text(
              'Weight: ${exercise.weight == null ? 'Not recorded' : '${exercise.weight}'}',
            ),
            Text('Notes: ${_notes(exercise.notes)}'),
          ],
        ],
      ),
    );
  }
}

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

String _notes(String? value) =>
    value == null || value.trim().isEmpty ? 'No notes recorded.' : value;
