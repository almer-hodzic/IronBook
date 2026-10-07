import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/check_in_validation.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_check_in_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({
    super.key,
    required this.centerApiService,
    required this.checkInApiService,
  });

  final AdminCenterApiService centerApiService;
  final AdminCheckInApiService checkInApiService;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _tokenController = TextEditingController();
  final _scannerFocusNode = FocusNode();

  late Future<List<AdminCenter>> _centersFuture;
  List<AdminCenter> _activeCenters = const [];
  int? _selectedCenterId;
  bool _isValidating = false;
  CheckInValidationResult? _grantedResult;
  String? _deniedMessage;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _loadCenters();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusScanner());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  void _loadCenters() {
    _centersFuture = widget.centerApiService.getCenters().then((centers) {
      final activeCenters = centers
          .where((center) => center.isActive)
          .toList(growable: false);

      if (mounted) {
        setState(() {
          _activeCenters = activeCenters;
          if (_selectedCenterId == null ||
              !activeCenters.any((center) => center.id == _selectedCenterId)) {
            _selectedCenterId = activeCenters.isEmpty
                ? null
                : activeCenters.first.id;
          }
        });
      }

      return activeCenters;
    });
  }

  Future<void> _validateCurrentToken() async {
    if (_isValidating) {
      return;
    }

    final centerId = _selectedCenterId;
    final token = _tokenController.text.trim();

    setState(() {
      _inputError = null;
      _grantedResult = null;
      _deniedMessage = null;
    });

    if (centerId == null) {
      setState(() {
        _inputError = 'Select an active center before scanning.';
      });
      _focusScanner();
      return;
    }

    if (token.isEmpty) {
      setState(() {
        _inputError = 'Scan or paste a QR token before validating.';
      });
      _focusScanner();
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final result = await widget.checkInApiService.validateCheckIn(
        qrAccessToken: token,
        centerId: centerId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _grantedResult = result;
      });
    } on AdminCheckInApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deniedMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  void _resetForNextScan() {
    setState(() {
      _tokenController.clear();
      _inputError = null;
      _grantedResult = null;
      _deniedMessage = null;
    });
    _focusScanner();
  }

  void _focusScanner() {
    if (!mounted) {
      return;
    }

    _scannerFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Check-In',
      subtitle: 'Validate member QR access against the selected center.',
      actions: AdminStatusChip(
        label: _isValidating ? 'Validating' : 'Ready',
        variant: _isValidating
            ? AdminStatusVariant.warning
            : AdminStatusVariant.success,
      ),
      children: [
        FutureBuilder<List<AdminCenter>>(
          future: _centersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StatePanel.loading();
            }

            if (snapshot.hasError) {
              return _StatePanel.error(
                message: snapshot.error.toString(),
                onRetry: () {
                  setState(_loadCenters);
                  _focusScanner();
                },
              );
            }

            if (_activeCenters.isEmpty) {
              return const _StatePanel.empty();
            }

            return _CheckInWorkspace(
              centers: _activeCenters,
              selectedCenterId: _selectedCenterId,
              tokenController: _tokenController,
              scannerFocusNode: _scannerFocusNode,
              isValidating: _isValidating,
              inputError: _inputError,
              grantedResult: _grantedResult,
              deniedMessage: _deniedMessage,
              onCenterChanged: _isValidating
                  ? null
                  : (centerId) {
                      setState(() {
                        _selectedCenterId = centerId;
                        _inputError = null;
                        _grantedResult = null;
                        _deniedMessage = null;
                      });
                      _focusScanner();
                    },
              onValidate: _validateCurrentToken,
              onReset: _resetForNextScan,
            );
          },
        ),
      ],
    );
  }
}

class _CheckInWorkspace extends StatelessWidget {
  const _CheckInWorkspace({
    required this.centers,
    required this.selectedCenterId,
    required this.tokenController,
    required this.scannerFocusNode,
    required this.isValidating,
    required this.onCenterChanged,
    required this.onValidate,
    required this.onReset,
    this.inputError,
    this.grantedResult,
    this.deniedMessage,
  });

  final List<AdminCenter> centers;
  final int? selectedCenterId;
  final TextEditingController tokenController;
  final FocusNode scannerFocusNode;
  final bool isValidating;
  final ValueChanged<int?>? onCenterChanged;
  final VoidCallback onValidate;
  final VoidCallback onReset;
  final String? inputError;
  final CheckInValidationResult? grantedResult;
  final String? deniedMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final scannerPanel = _ScannerPanel(
          centers: centers,
          selectedCenterId: selectedCenterId,
          tokenController: tokenController,
          scannerFocusNode: scannerFocusNode,
          isValidating: isValidating,
          inputError: inputError,
          onCenterChanged: onCenterChanged,
          onValidate: onValidate,
          onReset: onReset,
        );
        final resultPanel = _ResultPanel(
          isValidating: isValidating,
          grantedResult: grantedResult,
          deniedMessage: deniedMessage,
          onReset: onReset,
        );

        if (!wide) {
          return Column(
            children: [scannerPanel, const SizedBox(height: 14), resultPanel],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: scannerPanel),
            const SizedBox(width: 14),
            Expanded(flex: 5, child: resultPanel),
          ],
        );
      },
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.centers,
    required this.selectedCenterId,
    required this.tokenController,
    required this.scannerFocusNode,
    required this.isValidating,
    required this.onCenterChanged,
    required this.onValidate,
    required this.onReset,
    this.inputError,
  });

  final List<AdminCenter> centers;
  final int? selectedCenterId;
  final TextEditingController tokenController;
  final FocusNode scannerFocusNode;
  final bool isValidating;
  final ValueChanged<int?>? onCenterChanged;
  final VoidCallback onValidate;
  final VoidCallback onReset;
  final String? inputError;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Scanner Input',
      action: AdminStatusChip(
        label: isValidating ? 'Processing' : 'USB Scanner Ready',
        variant: isValidating
            ? AdminStatusVariant.warning
            : AdminStatusVariant.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminFieldLabel(
            label: 'Center',
            hint: 'Only active centers can be used for access validation.',
            child: DropdownButtonFormField<int>(
              initialValue: selectedCenterId,
              items: [
                for (final center in centers)
                  DropdownMenuItem<int>(
                    value: center.id,
                    child: Text('${center.name} / ${center.location}'),
                  ),
              ],
              onChanged: isValidating ? null : onCenterChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.apartment, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'QR Token',
            hint:
                'Scan with a USB QR reader or paste a token for local testing.',
            child: TextField(
              controller: tokenController,
              focusNode: scannerFocusNode,
              enabled: !isValidating,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
                hintText: 'Waiting for QR scan...',
                errorText: inputError,
              ),
              onSubmitted: (_) => onValidate(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminButton.primary(
                onPressed: isValidating ? null : onValidate,
                icon: isValidating ? Icons.hourglass_empty : Icons.verified,
                label: isValidating ? 'Validating' : 'Validate Access',
              ),
              AdminButton.secondary(
                onPressed: isValidating ? null : onReset,
                icon: Icons.restart_alt,
                label: 'Clear',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _ScannerNote(),
        ],
      ),
    );
  }
}

class _ScannerNote extends StatelessWidget {
  const _ScannerNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.slate50,
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.keyboard_return,
              color: IronBookAdminColors.slate500,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'USB scanners usually type the QR value and press Enter. This screen sends only the opaque token and selected center to the API.',
                style: TextStyle(
                  color: IronBookAdminColors.slate500,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.isValidating,
    required this.onReset,
    this.grantedResult,
    this.deniedMessage,
  });

  final bool isValidating;
  final VoidCallback onReset;
  final CheckInValidationResult? grantedResult;
  final String? deniedMessage;

  @override
  Widget build(BuildContext context) {
    final result = grantedResult;
    final denied = deniedMessage;

    if (isValidating) {
      return const AdminPanel(
        title: 'Validation Result',
        child: SizedBox(
          height: 318,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (result != null) {
      return _AccessResultPanel.granted(result: result, onReset: onReset);
    }

    if (denied != null) {
      return _AccessResultPanel.denied(message: denied, onReset: onReset);
    }

    return const AdminPanel(
      title: 'Validation Result',
      child: SizedBox(height: 318, child: Center(child: _ReadyState())),
    );
  }
}

class _AccessResultPanel extends StatelessWidget {
  const _AccessResultPanel.granted({
    required CheckInValidationResult this._result,
    required this.onReset,
  }) : _message = null,
       _granted = true;

  const _AccessResultPanel.denied({
    required String this._message,
    required this.onReset,
  }) : _result = null,
       _granted = false;

  final CheckInValidationResult? _result;
  final String? _message;
  final VoidCallback onReset;
  final bool _granted;

  @override
  Widget build(BuildContext context) {
    final title = _granted ? 'Access Granted' : 'Access Denied';
    final color = _granted
        ? IronBookAdminColors.emerald700
        : IronBookAdminColors.rose700;
    final background = _granted
        ? IronBookAdminColors.emerald100
        : IronBookAdminColors.rose100;
    final border = _granted
        ? IronBookAdminColors.emerald200
        : IronBookAdminColors.rose200;
    final icon = _granted ? Icons.check_circle : Icons.cancel_outlined;

    return AdminPanel(
      title: 'Validation Result',
      action: AdminStatusChip(
        label: _granted ? 'Granted' : 'Denied',
        variant: _granted
            ? AdminStatusVariant.success
            : AdminStatusVariant.danger,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_granted && _result != null)
                _GrantedDetails(result: _result)
              else
                Text(
                  _message ?? 'Access validation was denied.',
                  style: const TextStyle(
                    color: IronBookAdminColors.rose700,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: AdminButton.primary(
                  onPressed: onReset,
                  icon: Icons.qr_code_scanner,
                  label: _granted ? 'Scan Next Member' : 'Scan Again',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrantedDetails extends StatelessWidget {
  const _GrantedDetails({required this.result});

  final CheckInValidationResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(label: 'Member', value: result.memberName),
        _DetailRow(label: 'Center', value: result.centerName),
        _DetailRow(label: 'Checked In', value: _formatDate(result.checkedInAt)),
        _DetailRow(label: 'CheckIn ID', value: result.checkInId.toString()),
        _DetailRow(
          label: 'Membership ID',
          value: result.membershipId.toString(),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdminRowCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: IronBookAdminColors.slate500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 2,
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: IronBookAdminColors.slate800,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: IronBookAdminColors.slate100,
            border: Border.all(color: IronBookAdminColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.qr_code_2,
            color: IronBookAdminColors.slate500,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Ready for scan',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Select a center and scan a member QR pass to validate access.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: IronBookAdminColors.slate500,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _StatePanel.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading centers',
      message = 'Please wait while active centers are loaded.',
      action = null,
      loading = true;

  factory _StatePanel.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Check-In could not load centers',
      message: message,
      action: AdminButton.primary(
        onPressed: onRetry,
        icon: Icons.refresh,
        label: 'Retry',
      ),
    );
  }

  const _StatePanel.empty()
    : icon = Icons.apartment_outlined,
      title = 'No active centers',
      message = 'Create or activate a center before using Check-In.',
      action = null,
      loading = false;

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: title,
      child: SizedBox(
        height: 320,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const CircularProgressIndicator()
                else
                  Icon(icon, size: 42, color: IronBookAdminColors.slate500),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
