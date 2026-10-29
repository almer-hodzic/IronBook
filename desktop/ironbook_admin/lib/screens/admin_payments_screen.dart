import '../models/paged_result.dart';
import '../widgets/admin_paging_controls.dart';

import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_payment.dart';
import '../services/admin_payment_api_service.dart';
import '../services/payment_register_file_service.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({
    super.key,
    required this.paymentApiService,
    this.paymentRegisterFiles = const PaymentRegisterFileService(),
  });
  final AdminPaymentApiService paymentApiService;
  final PaymentRegisterFileService paymentRegisterFiles;
  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  final _search = TextEditingController();
  String? _status;
  String? _method;
  int? _centerId;
  AdminPaymentFilter _applied = const AdminPaymentFilter();
  List<AdminPayment> _payments = [];
  PagedResult<AdminPayment>? _paymentPage;
  int _pageNumber = 1;
  List<AdminCenter> _centers = [];
  bool _loading = true;
  int? _confirmingId;
  String? _error;
  String? _actionError;
  String? _notice;
  bool _exporting = false;
  bool _openingPdf = false;
  String? _exportError;
  String? _exportNotice;
  String? _savedPdfPath;
  bool get _busy => _loading || _confirmingId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<Object>([
        loadAvailablePage(
          _pageNumber,
          (number) => widget.paymentApiService.getPayments(
            _applied,
            pageNumber: number,
          ),
        ),
        widget.paymentApiService.getCenters(),
      ]);
      if (!mounted) return;
      setState(() {
        _paymentPage = result[0] as PagedResult<AdminPayment>;
        _payments = _paymentPage!.items;
        _pageNumber = _paymentPage!.pageNumber;
        _centers = result[1] as List<AdminCenter>;
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

  void _apply() {
    if (_busy) return;
    _pageNumber = 1;
    _applied = AdminPaymentFilter(
      search: _search.text,
      status: _status,
      paymentMethod: _method,
      centerId: _centerId,
    );
    setState(() {
      _notice = null;
      _actionError = null;
    });
    _load();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _status = null;
      _method = null;
      _centerId = null;
    });
    _apply();
  }

  Future<void> _confirm(AdminPayment payment) async {
    if (_busy || !payment.canConfirm) return;
    setState(() {
      _confirmingId = payment.id;
      _actionError = null;
      _notice = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm reception payment?'),
        content: Text(
          'Confirm receipt of ${payment.amount.toStringAsFixed(2)} from ${payment.memberName} '
          'for ${payment.membershipPlanName} at ${payment.centerName}.\n\n'
          'The existing membership will become active. Its original dates will stay unchanged.\n'
          'Membership dates: ${_date(payment.membershipStartDate)} – ${_date(payment.membershipEndDate)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() {
        _confirmingId = null;
      });
      return;
    }
    try {
      await widget.paymentApiService.confirmReception(payment.id);
      if (!mounted) return;
      setState(() {
        _notice = 'Payment confirmed. Membership activated.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _confirmingId = null;
        });
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (_exporting || _busy) return;
    final filters = _applied;
    setState(() {
      _exporting = true;
      _exportError = null;
      _exportNotice = null;
      _savedPdfPath = null;
    });
    try {
      final download = await widget.paymentApiService.downloadPaymentRegister(
        filters,
      );
      if (!mounted) return;
      final path = await widget.paymentRegisterFiles.save(download);
      if (!mounted) return;
      setState(() {
        _savedPdfPath = path;
        _exportNotice = path == null
            ? 'PDF save cancelled.'
            : 'Payment Register saved to $path';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exportError =
            error is AdminPaymentApiException ||
                error is PaymentRegisterFileException
            ? error.toString()
            : 'The Payment Register could not be saved. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<void> _openPdf() async {
    final path = _savedPdfPath;
    if (_openingPdf || path == null) return;
    setState(() {
      _openingPdf = true;
      _exportError = null;
    });
    try {
      await widget.paymentRegisterFiles.open(path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _exportError = 'The PDF could not be opened. Open the saved file with a PDF viewer.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingPdf = false;
        });
      }
    }
  }

  Widget _filter<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> changed,
  ) => SizedBox(
    width: label == 'Center' ? 270 : 210,
    child: DropdownButtonFormField<T>(
      key: ValueKey('payment-$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: _busy ? null : changed,
    ),
  );

  String _date(DateTime value) =>
      MaterialLocalizations.of(context).formatFullDate(value.toLocal());

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Payments',
    subtitle: 'Review checkout payments and confirm reception payments.',
    actions: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AdminButton.secondary(
          key: const Key('download-payment-register'),
          label: _exporting ? 'Downloading PDF...' : 'Download PDF',
          icon: Icons.download,
          onPressed: _busy || _exporting || _openingPdf ? null : _downloadPdf,
        ),
        AdminButton.secondary(
          label: 'Refresh',
          icon: Icons.refresh,
          onPressed: _busy ? null : _load,
        ),
      ],
    ),
    children: [
      AdminPanel(
        title: 'Payment filters',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('payment-search'),
                controller: _search,
                enabled: !_busy,
                onSubmitted: (_) => _apply(),
                decoration: const InputDecoration(
                  labelText: 'Member name or email',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _filter<String>(
              'Status',
              _status,
              [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All statuses'),
                ),
                const DropdownMenuItem(
                  value: 'PendingReception',
                  child: Text('Pending reception'),
                ),
                const DropdownMenuItem(
                  value: 'Completed',
                  child: Text('Completed'),
                ),
              ],
              (value) => setState(() {
                _status = value;
              }),
            ),
            _filter<String>(
              'Payment method',
              _method,
              [
                const DropdownMenuItem(value: null, child: Text('All methods')),
                const DropdownMenuItem(value: 'Card', child: Text('Card')),
                const DropdownMenuItem(
                  value: 'Reception',
                  child: Text('Reception'),
                ),
              ],
              (value) => setState(() {
                _method = value;
              }),
            ),
            _filter<int>(
              'Center',
              _centerId,
              [
                const DropdownMenuItem(value: null, child: Text('All centers')),
                for (final center in _centers)
                  DropdownMenuItem(
                    value: center.id,
                    child: Text(
                      '${center.name}${center.isActive ? '' : ' (inactive)'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              (value) => setState(() {
                _centerId = value;
              }),
            ),
            AdminButton.primary(
              label: 'Apply filters',
              onPressed: _busy ? null : _apply,
            ),
            AdminButton.secondary(
              label: 'Clear filters',
              onPressed: _busy ? null : _clear,
            ),
          ],
        ),
      ),
      const Text(
        'Newest payments first. Apply filters to update results; refresh repeats the applied filters. '
        'Dates are checkout record dates; the model does not store a separate confirmation date.',
      ),
      if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
      if (_exportNotice != null || _exportError != null)
        AdminPanel(
          title: 'Payment Register',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_exportNotice != null)
                Semantics(liveRegion: true, child: Text(_exportNotice!)),
              if (_exportError != null)
                Semantics(liveRegion: true, child: Text(_exportError!)),
              if (_savedPdfPath != null) ...[
                const SizedBox(height: 8),
                AdminButton.secondary(
                  label: _openingPdf ? 'Opening PDF...' : 'Open PDF',
                  icon: Icons.open_in_new,
                  onPressed: _openingPdf ? null : _openPdf,
                ),
              ],
            ],
          ),
        ),
      if (_actionError != null)
        AdminPanel(
          title: 'Payment not confirmed',
          child: Semantics(liveRegion: true, child: Text(_actionError!)),
        ),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_error != null)
        AdminPanel(
          title: 'Payments unavailable',
          child: Column(
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              AdminButton.secondary(
                label: 'Retry',
                onPressed: _busy ? null : _load,
              ),
            ],
          ),
        )
      else if (_payments.isEmpty)
        const AdminPanel(
          title: 'Payments',
          child: Text('No payments match the applied filters.'),
        )
      else
        AdminPanel(
          title: 'Membership payments',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Payment / membership')),
                DataColumn(label: Text('Member')),
                DataColumn(label: Text('Center')),
                DataColumn(label: Text('Membership plan')),
                DataColumn(label: Text('Amount'), numeric: true),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Payment status')),
                DataColumn(label: Text('Membership status')),
                DataColumn(label: Text('Created date')),
                DataColumn(label: Text('Action')),
              ],
              rows: [
                for (final payment in _payments)
                  DataRow(
                    cells: [
                      DataCell(
                        Text('#${payment.id} / #${payment.membershipId}'),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(payment.memberName),
                            Text(
                              payment.memberEmail,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(payment.centerName)),
                      DataCell(Text(payment.membershipPlanName)),
                      DataCell(Text(payment.amount.toStringAsFixed(2))),
                      DataCell(Text(payment.paymentMethod)),
                      DataCell(
                        AdminStatusChip(
                          label: payment.paymentStatus == 'PendingReception'
                              ? 'Pending reception'
                              : payment.paymentStatus,
                          variant: payment.paymentStatus == 'Completed'
                              ? AdminStatusVariant.success
                              : AdminStatusVariant.warning,
                        ),
                      ),
                      DataCell(Text(payment.membershipStatus)),
                      DataCell(Text(_date(payment.createdAt))),
                      DataCell(
                        payment.canConfirm
                            ? AdminButton.primary(
                                key: Key('confirm-payment-${payment.id}'),
                                label: _confirmingId == payment.id
                                    ? 'Confirming...'
                                    : 'Confirm Payment',
                                onPressed: _busy
                                    ? null
                                    : () => _confirm(payment),
                              )
                            : const Text('—'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      if (!_loading && _error == null && _paymentPage != null)
        AdminPagingControls(
          page: _paymentPage!,
          enabled: !_busy,
          onPageChanged: (number) {
            _pageNumber = number;
            _load();
          },
        ),
    ],
  );
}
