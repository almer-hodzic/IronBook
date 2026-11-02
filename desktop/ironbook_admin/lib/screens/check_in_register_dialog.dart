import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_reports.dart';
import '../services/admin_check_in_api_service.dart';
import '../services/pdf_file_service.dart';
import '../widgets/admin_primitives.dart';

/// Report-only filters: no changes to the scanner's selected Center or QR data.
class CheckInRegisterDialog extends StatefulWidget {
  const CheckInRegisterDialog({
    super.key,
    required this.api,
    required this.centers,
    this.initialCenterId,
    this.files = const PdfFileService(),
  });

  final AdminCheckInApiService api;
  final Future<List<AdminCenter>> centers;
  final int? initialCenterId;
  final PdfFileService files;

  @override
  State<CheckInRegisterDialog> createState() => _CheckInRegisterDialogState();
}

class _CheckInRegisterDialogState extends State<CheckInRegisterDialog> {
  final _form = GlobalKey<FormState>();
  final _from = TextEditingController();
  final _to = TextEditingController();
  late int? _centerId = widget.initialCenterId;
  bool _exporting = false;
  bool _opening = false;
  String? _error;
  String? _notice;
  String? _path;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String? _dateError(String? input) {
    final value = input?.trim() ?? '';
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

  Future<void> _download() async {
    if (_exporting || _opening || !_form.currentState!.validate()) return;
    final filter = AdminReportFilter(
      centerId: _centerId,
      fromDate: _from.text.trim().isEmpty ? null : _from.text.trim(),
      toDate: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    setState(() {
      _exporting = true;
      _error = null;
      _notice = null;
      _path = null;
    });
    try {
      final download = await widget.api.downloadCheckInRegister(filter);
      if (!mounted) return;
      final path = await widget.files.save(download);
      if (!mounted) return;
      setState(() {
        _path = path;
        _notice = path == null
            ? 'PDF save cancelled.'
            : 'Check-In Register saved to $path';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AdminCheckInApiException || error is PdfFileException
            ? error.toString()
            : 'The Check-In Register could not be saved. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<void> _open() async {
    final path = _path;
    if (_opening || path == null) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.files.open(path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The PDF could not be opened. Open the saved file with a PDF viewer.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  void _clear() {
    _form.currentState!.reset();
    _from.clear();
    _to.clear();
    setState(() {
      _centerId = null;
      _error = null;
    });
  }

  Widget _dateField(String label, TextEditingController controller) =>
      TextFormField(
        key: Key('check-in-register-$label'),
        controller: controller,
        enabled: !_exporting,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'yyyy-MM-dd',
          suffixIcon: IconButton(
            tooltip: 'Choose $label',
            onPressed: _exporting ? null : () => _pickDate(controller),
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ),
        validator: (value) {
          final error = _dateError(value);
          if (error != null) return error;
          if (controller == _to &&
              _dateError(_from.text) == null &&
              _from.text.trim().isNotEmpty &&
              (value?.trim().isNotEmpty ?? false) &&
              _from.text.trim().compareTo(value!.trim()) > 0) {
            return 'To date must be on or after from date.';
          }
          return null;
        },
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Check-In Register'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export recorded check-ins. Dates include the entire selected UTC calendar day.',
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<AdminCenter>>(
                future: widget.centers,
                builder: (context, snapshot) {
                  final centers = snapshot.data ?? const <AdminCenter>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        key: ValueKey('check-in-register-center-$_centerId'),
                        initialValue: _centerId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Center'),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('All centers'),
                          ),
                          for (final center in centers)
                            DropdownMenuItem(
                              value: center.id,
                              child: Text(
                                '${center.name}${center.isActive ? '' : ' (inactive)'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (_centerId != null &&
                              !centers.any((center) => center.id == _centerId))
                            DropdownMenuItem(
                              value: _centerId,
                              child: Text('Center #$_centerId'),
                            ),
                        ],
                        onChanged: _exporting
                            ? null
                            : (value) => setState(() {
                                _centerId = value;
                              }),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Text('Loading Centers...'),
                      if (snapshot.hasError)
                        const Text(
                          'Center options could not be loaded. Close and retry loading Centers on Check-In.',
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _dateField('From Date', _from),
              const SizedBox(height: 12),
              _dateField('To Date', _to),
              const SizedBox(height: 12),
              AdminButton.secondary(
                label: 'Clear filters',
                onPressed: _exporting ? null : _clear,
              ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_notice!)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
              if (_path != null) ...[
                const SizedBox(height: 12),
                AdminButton.secondary(
                  label: _opening ? 'Opening PDF...' : 'Open PDF',
                  icon: Icons.open_in_new,
                  onPressed: _opening ? null : _open,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      AdminButton.primary(
        key: const Key('export-check-in-register'),
        label: _exporting ? 'Downloading PDF...' : 'Download PDF',
        icon: Icons.download,
        onPressed: _exporting || _opening ? null : _download,
      ),
    ],
  );
}
