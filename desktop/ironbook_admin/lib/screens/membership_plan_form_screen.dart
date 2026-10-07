import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_membership_plan.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_membership_plan_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class MembershipPlanFormScreen extends StatefulWidget {
  const MembershipPlanFormScreen({
    super.key,
    this.planId,
    required this.membershipPlanApiService,
    required this.centerApiService,
  });

  final int? planId;
  final AdminMembershipPlanApiService membershipPlanApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<MembershipPlanFormScreen> createState() =>
      _MembershipPlanFormScreenState();
}

class _MembershipPlanFormScreenState extends State<MembershipPlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _descriptionController = TextEditingController();
  final _benefitsController = TextEditingController();

  Future<_PlanFormData>? _formDataFuture;
  bool _isActive = true;
  bool _isSaving = false;
  int? _appliedPlanId;
  final Set<int> _selectedCenterIds = <int>{};

  bool get _isEditing => widget.planId != null;

  @override
  void initState() {
    super.initState();
    _formDataFuture = _loadFormData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _benefitsController.dispose();
    super.dispose();
  }

  Future<_PlanFormData> _loadFormData() async {
    final centersFuture = widget.centerApiService.getCenters();
    final planId = widget.planId;

    if (planId == null) {
      return _PlanFormData(centers: await centersFuture);
    }

    final results = await Future.wait<Object>([
      centersFuture,
      widget.membershipPlanApiService.getMembershipPlan(planId),
    ]);

    return _PlanFormData(
      centers: results[0] as List<AdminCenter>,
      plan: results[1] as AdminMembershipPlan,
    );
  }

  void _applyPlan(AdminMembershipPlan plan) {
    if (_appliedPlanId == plan.id) {
      return;
    }

    _appliedPlanId = plan.id;
    _nameController.text = plan.name;
    _priceController.text = plan.monthlyPrice.toStringAsFixed(2);
    _descriptionController.text = plan.description ?? '';
    _benefitsController.text = plan.benefits ?? '';
    _isActive = plan.isActive;
    _selectedCenterIds
      ..clear()
      ..addAll(plan.centers.map((center) => center.centerId));
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final request = AdminMembershipPlanWriteRequest(
      name: _nameController.text.trim(),
      description: _optionalText(_descriptionController.text),
      monthlyPrice: double.parse(_priceController.text.trim()),
      benefits: _optionalText(_benefitsController.text),
      isActive: _isActive,
      centerIds: _selectedCenterIds.toList()..sort(),
    );

    setState(() {
      _isSaving = true;
    });

    try {
      final planId = widget.planId;
      if (planId == null) {
        await widget.membershipPlanApiService.createMembershipPlan(request);
      } else {
        await widget.membershipPlanApiService.updateMembershipPlan(
          planId,
          request,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on AdminMembershipPlanApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } on AdminCenterApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormPage(
      title: _isEditing ? 'Edit Package' : 'Create New Package',
      subtitle: _isEditing
          ? 'Update plan pricing, status, and center availability.'
          : 'Create a real membership package and assign it to centers.',
      actions: AdminButton.secondary(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        icon: Icons.arrow_back,
        label: 'Back to Memberships',
      ),
      child: FutureBuilder<_PlanFormData>(
        future: _formDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _FormStateCard.loading();
          }

          if (snapshot.hasError) {
            return _FormStateCard.error(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _formDataFuture = _loadFormData();
                });
              },
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return const _FormStateCard(
              icon: Icons.error_outline,
              title: 'Package form could not be loaded',
              message: 'No form data was returned.',
            );
          }

          final plan = data.plan;
          if (plan != null) {
            _applyPlan(plan);
          }

          return _MembershipPlanFormBody(
            formKey: _formKey,
            nameController: _nameController,
            priceController: _priceController,
            descriptionController: _descriptionController,
            benefitsController: _benefitsController,
            centers: data.centers,
            selectedCenterIds: _selectedCenterIds,
            isActive: _isActive,
            isSaving: _isSaving,
            plan: plan,
            onActiveChanged: (value) => setState(() => _isActive = value),
            onCenterChanged: (centerId, selected) {
              setState(() {
                if (selected) {
                  _selectedCenterIds.add(centerId);
                } else {
                  _selectedCenterIds.remove(centerId);
                }
              });
            },
            onSave: _save,
          );
        },
      ),
    );
  }

  static String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MembershipPlanFormBody extends StatelessWidget {
  const _MembershipPlanFormBody({
    required this.formKey,
    required this.nameController,
    required this.priceController,
    required this.descriptionController,
    required this.benefitsController,
    required this.centers,
    required this.selectedCenterIds,
    required this.isActive,
    required this.isSaving,
    required this.onActiveChanged,
    required this.onCenterChanged,
    required this.onSave,
    this.plan,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController descriptionController;
  final TextEditingController benefitsController;
  final List<AdminCenter> centers;
  final Set<int> selectedCenterIds;
  final bool isActive;
  final bool isSaving;
  final ValueChanged<bool> onActiveChanged;
  final void Function(int centerId, bool selected) onCenterChanged;
  final VoidCallback onSave;
  final AdminMembershipPlan? plan;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (plan != null) ...[
            _MetadataRow(plan: plan!),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 680;
              if (!twoColumns) {
                return Column(children: _fieldRows());
              }

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _nameField()),
                      const SizedBox(width: 14),
                      SizedBox(width: 220, child: _priceField()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ActiveStatusCard(
                    isActive: isActive,
                    isSaving: isSaving,
                    onChanged: onActiveChanged,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'Short Package Description',
            child: TextFormField(
              controller: descriptionController,
              decoration: const InputDecoration(
                hintText: 'Describe the plan value and target member profile.',
              ),
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
            ),
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'Benefits',
            hint: 'One benefit per line works well for the mobile member view.',
            child: TextFormField(
              controller: benefitsController,
              decoration: const InputDecoration(
                hintText: 'Extended access\nGroup class access\nTrainer support',
              ),
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
            ),
          ),
          const SizedBox(height: 14),
          _CenterAssignmentsCard(
            centers: centers,
            selectedCenterIds: selectedCenterIds,
            isSaving: isSaving,
            onChanged: onCenterChanged,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              AdminStatusChip(
                label: plan == null ? 'New database row' : 'API-loaded details',
                variant: AdminStatusVariant.accent,
              ),
              const Spacer(),
              AdminButton.secondary(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                icon: Icons.close,
                label: 'Cancel',
              ),
              const SizedBox(width: 8),
              AdminButton.primary(
                onPressed: isSaving ? null : onSave,
                icon: isSaving ? null : Icons.save_outlined,
                label: isSaving ? 'Saving...' : 'Save Package',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _fieldRows() {
    return [
      _nameField(),
      const SizedBox(height: 14),
      _priceField(),
      const SizedBox(height: 14),
      _ActiveStatusCard(
        isActive: isActive,
        isSaving: isSaving,
        onChanged: onActiveChanged,
      ),
    ];
  }

  Widget _nameField() {
    return AdminFieldLabel(
      label: 'Package Name',
      child: TextFormField(
        controller: nameController,
        decoration: const InputDecoration(hintText: 'e.g. Standard'),
        maxLength: 150,
        validator: _validateRequired,
      ),
    );
  }

  Widget _priceField() {
    return AdminFieldLabel(
      label: 'Monthly Price',
      child: TextFormField(
        controller: priceController,
        decoration: const InputDecoration(hintText: '0.00'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: _validatePrice,
      ),
    );
  }

  static String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }

    return null;
  }

  static String? _validatePrice(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Monthly price is required.';
    }

    final parsed = double.tryParse(text);
    if (parsed == null) {
      return 'Monthly price must be a number.';
    }

    if (parsed < 0) {
      return 'Monthly price must be 0 or greater.';
    }

    return null;
  }
}

class _CenterAssignmentsCard extends StatelessWidget {
  const _CenterAssignmentsCard({
    required this.centers,
    required this.selectedCenterIds,
    required this.isSaving,
    required this.onChanged,
  });

  final List<AdminCenter> centers;
  final Set<int> selectedCenterIds;
  final bool isSaving;
  final void Function(int centerId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Center Availability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (centers.isEmpty)
            const Text(
              'No centers are available from the API.',
              style: TextStyle(
                color: IronBookAdminColors.slate500,
                fontSize: 12,
              ),
            )
          else
            for (final center in centers) ...[
              CheckboxListTile(
                value: selectedCenterIds.contains(center.id),
                onChanged: isSaving
                    ? null
                    : (value) => onChanged(center.id, value ?? false),
                title: Text(center.name),
                subtitle: Text(center.location),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (center != centers.last)
                const Divider(height: 1, color: IronBookAdminColors.border),
            ],
        ],
      ),
    );
  }
}

class _ActiveStatusCard extends StatelessWidget {
  const _ActiveStatusCard({
    required this.isActive,
    required this.isSaving,
    required this.onChanged,
  });

  final bool isActive;
  final bool isSaving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminRowCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active package',
                  style: TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Inactive packages stay stored but are hidden from member browsing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AdminStatusChip(
            label: isActive ? 'Active' : 'Inactive',
            variant: isActive
                ? AdminStatusVariant.success
                : AdminStatusVariant.neutral,
          ),
          const SizedBox(width: 12),
          Switch(value: isActive, onChanged: isSaving ? null : onChanged),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.plan});

  final AdminMembershipPlan plan;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetadataPill(label: 'ID', value: plan.id.toString()),
        _MetadataPill(
          label: 'Created',
          value: plan.createdAt.toLocal().toString().split('.').first,
        ),
        AdminStatusChip(
          label: plan.isActive ? 'Active' : 'Inactive',
          variant: plan.isActive
              ? AdminStatusVariant.success
              : AdminStatusVariant.neutral,
        ),
      ],
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IronBookAdminColors.slate100,
        border: Border.all(color: IronBookAdminColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$label: $value',
          style: const TextStyle(
            color: IronBookAdminColors.slate600,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FormStateCard extends StatelessWidget {
  const _FormStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _FormStateCard.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading package form',
      message = 'Please wait while package and center data are loaded.',
      action = null,
      loading = true;

  factory _FormStateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _FormStateCard(
      icon: Icons.error_outline,
      title: 'Package form could not be loaded',
      message: message,
      action: AdminButton.primary(
        onPressed: onRetry,
        icon: Icons.refresh,
        label: 'Retry',
      ),
    );
  }

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(icon, color: IronBookAdminColors.slate500, size: 42),
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
    );
  }
}

class _PlanFormData {
  const _PlanFormData({required this.centers, this.plan});

  final List<AdminCenter> centers;
  final AdminMembershipPlan? plan;
}
