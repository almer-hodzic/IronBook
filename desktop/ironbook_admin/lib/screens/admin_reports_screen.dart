import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_reports.dart';
import '../services/admin_reports_api_service.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, required this.reportsApiService});
  final AdminReportsApiService reportsApiService;
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _form = GlobalKey<FormState>();
  final _from = TextEditingController();
  final _to = TextEditingController();
  int? _centerId;
  AdminReportFilter _applied = const AdminReportFilter();
  bool _loading = true;
  String? _error;
  AdminReportSummary? _summary;
  List<AdminCenterActivity> _activity = [];
  List<AdminCenter> _centers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.reportsApiService.getSummary(_applied),
        widget.reportsApiService.getCenterActivity(_applied),
        widget.reportsApiService.getFilterCenters(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as AdminReportSummary;
        _activity = results[1] as List<AdminCenterActivity>;
        _centers = results[2] as List<AdminCenter>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String? _dateError(String? text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        parsed == null ||
        parsed.year < 1 ||
        _date(parsed) != value) {
      return 'Use a valid date: yyyy-MM-dd.';
    }
    return null;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  void _apply() {
    if (_loading || !_form.currentState!.validate()) return;
    _applied = AdminReportFilter(
      fromDate: _from.text.trim().isEmpty ? null : _from.text.trim(),
      toDate: _to.text.trim().isEmpty ? null : _to.text.trim(),
      centerId: _centerId,
    );
    _load();
  }

  void _clear() {
    _form.currentState!.reset();
    _from.clear();
    _to.clear();
    setState(() {
      _centerId = null;
    });
    _applied = const AdminReportFilter();
    _load();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateError(controller.text) == null
          ? DateTime.tryParse(controller.text.trim()) ?? DateTime.now()
          : DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected != null && mounted) controller.text = _date(selected);
  }

  Widget _dateField(String label, TextEditingController controller) => SizedBox(
    width: 220,
    child: TextFormField(
      key: Key('reports-$label'),
      controller: controller,
      enabled: !_loading,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'yyyy-MM-dd',
        suffixIcon: IconButton(
          tooltip: 'Choose $label',
          onPressed: _loading ? null : () => _pickDate(controller),
          icon: const Icon(Icons.calendar_today_outlined),
        ),
      ),
      validator: (value) {
        final error = _dateError(value);
        if (error != null) return error;
        if (label == 'To date' &&
            _dateError(_from.text) == null &&
            _from.text.trim().isNotEmpty &&
            (value?.trim().isNotEmpty ?? false) &&
            DateTime.parse(_from.text.trim())
                .isAfter(DateTime.parse(value!.trim()))) {
          return 'To date must be on or after from date.';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return AdminPage(
      title: 'Reports',
      subtitle: 'Recorded membership, payment and training activity.',
      actions: AdminButton.secondary(
        label: 'Refresh',
        icon: Icons.refresh,
        onPressed: _loading ? null : _load,
      ),
      children: [
        AdminPanel(
          title: 'Filters',
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dateField('From date', _from),
                    _dateField('To date', _to),
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('reports-center-$_centerId'),
                        initialValue: _centerId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Center'),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('All centers'),
                          ),
                          for (final center in _centers)
                            DropdownMenuItem(
                              value: center.id,
                              child: Text(
                                '${center.name}${center.isActive ? '' : ' (inactive)'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) => setState(() {
                                _centerId = value;
                              }),
                      ),
                    ),
                    AdminButton.primary(
                      label: 'Apply filters',
                      onPressed: _loading ? null : _apply,
                    ),
                    AdminButton.secondary(
                      label: 'Clear filters',
                      onPressed: _loading ? null : _clear,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dates are inclusive. Apply filters to update results. Refresh uses the last applied filters.\n'
                  'Active members are global. Member, membership and payment dates filter creation dates; '
                  'other activity uses session/check-in dates. Active memberships must also be valid today.',
                ),
              ],
            ),
          ),
        ),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          AdminPanel(
            title: 'Reports unavailable',
            child: Column(
              children: [
                Text(_error!),
                const SizedBox(height: 12),
                AdminButton.secondary(label: 'Retry', onPressed: _load),
              ],
            ),
          )
        else if (summary != null) ...[
          AdminPanel(
            title: 'Summary',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('As of ${summary.asOfUtc.toLocal()}'),
                if (summary.metrics.values.every((value) => value == 0))
                  const Text('No activity matches the applied filters.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in summary.metrics.entries)
                      SizedBox(
                        width: 240,
                        child: AdminRowCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AdminReportSummary.labels[entry.key]!),
                              const SizedBox(height: 6),
                              Text(
                                entry.key.endsWith('Amount')
                                    ? entry.value.toStringAsFixed(2)
                                    : entry.value.toString(),
                                key: Key('metric-${entry.key}'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          AdminPanel(
            title: 'Active center activity',
            child: _activity.isEmpty
                ? const Text('No active centers match the applied filters.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Center')),
                        DataColumn(
                          label: Text('Active memberships'),
                          numeric: true,
                        ),
                        DataColumn(label: Text('Check-ins'), numeric: true),
                        DataColumn(
                          label: Text('Upcoming groups'),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text('Pending coaching'),
                          numeric: true,
                        ),
                      ],
                      rows: [
                        for (final row in _activity)
                          DataRow(
                            cells: [
                              DataCell(Text(row.centerName)),
                              DataCell(Text('${row.activeMemberships}')),
                              DataCell(Text('${row.checkIns}')),
                              DataCell(Text('${row.upcomingGroupTrainings}')),
                              DataCell(Text('${row.pendingCoachingRequests}')),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}
