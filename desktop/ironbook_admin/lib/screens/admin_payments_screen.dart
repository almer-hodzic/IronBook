import '../models/paged_result.dart';
import '../widgets/admin_paging_controls.dart';

import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_payment.dart';
import '../services/admin_payment_api_service.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key, required this.paymentApiService});
  final AdminPaymentApiService paymentApiService;
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
    actions: AdminButton.secondary(
      label: 'Refresh',
      icon: Icons.refresh,
      onPressed: _busy ? null : _load,
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
