import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../services/admin_center_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class CenterFormScreen extends StatefulWidget {
  const CenterFormScreen({
    super.key,
    this.centerId,
    required this.centerApiService,
  });

  final int? centerId;
  final AdminCenterApiService centerApiService;

  @override
  State<CenterFormScreen> createState() => _CenterFormScreenState();
}

class _CenterFormScreenState extends State<CenterFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _capacityController = TextEditingController(text: '0');
  final _amenitiesController = TextEditingController();
  final _notesController = TextEditingController();

  Future<AdminCenter>? _centerFuture;
  int? _appliedCenterId;
  bool _isActive = true;
  bool _isSaving = false;

  bool get _isEditing => widget.centerId != null;

  @override
  void initState() {
    super.initState();
    final centerId = widget.centerId;
    if (centerId != null) {
      _centerFuture = widget.centerApiService.getCenter(centerId);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    _amenitiesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _applyCenter(AdminCenter center) {
    if (_appliedCenterId == center.id) {
      return;
    }

    _appliedCenterId = center.id;
    _nameController.text = center.name;
    _locationController.text = center.location;
    _capacityController.text = center.capacity.toString();
    _amenitiesController.text = center.amenities ?? '';
    _notesController.text = center.notes ?? '';
    _isActive = center.isActive;
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final request = AdminCenterWriteRequest(
      name: _nameController.text.trim(),
      location: _locationController.text.trim(),
      capacity: int.parse(_capacityController.text.trim()),
      isActive: _isActive,
      amenities: _optionalText(_amenitiesController.text),
      notes: _optionalText(_notesController.text),
    );

    setState(() {
      _isSaving = true;
    });

    try {
      final centerId = widget.centerId;
      if (centerId == null) {
        await widget.centerApiService.createCenter(request);
      } else {
        await widget.centerApiService.updateCenter(centerId, request);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on AdminCenterApiException catch (error) {
      if (!mounted) {
        return;
      }

      _showError(error.message);
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
    final centerFuture = _centerFuture;

    return AdminFormPage(
      title: _isEditing ? 'Center Details' : 'Add New Center',
      subtitle: _isEditing ? 'Update center information and active status.' : 'Create a new center location with operational and service details.',
      actions: AdminButton.secondary(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        icon: Icons.arrow_back,
        label: 'Back to Centers',
      ),
      child: centerFuture == null
          ? _CenterFormBody(
              formKey: _formKey,
              nameController: _nameController,
              locationController: _locationController,
              capacityController: _capacityController,
              amenitiesController: _amenitiesController,
              notesController: _notesController,
              isActive: _isActive,
              isSaving: _isSaving,
              onActiveChanged: (value) => setState(() => _isActive = value),
              onSave: _save,
            )
          : FutureBuilder<AdminCenter>(
              future: centerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _FormStateCard.loading();
                }

                if (snapshot.hasError) {
                  return _FormStateCard.error(
                    message: snapshot.error.toString(),
                    onRetry: () {
                      setState(() {
                        _centerFuture = widget.centerApiService.getCenter(
                          widget.centerId!,
                        );
                      });
                    },
                  );
                }

                final center = snapshot.data;
                if (center == null) {
                  return const _FormStateCard(
                    icon: Icons.error_outline,
                    title: 'Center details could not be loaded',
                    message: 'No center data was returned.',
                  );
                }

                _applyCenter(center);

                return _CenterFormBody(
                  formKey: _formKey,
                  nameController: _nameController,
                  locationController: _locationController,
                  capacityController: _capacityController,
                  amenitiesController: _amenitiesController,
                  notesController: _notesController,
                  isActive: _isActive,
                  isSaving: _isSaving,
                  center: center,
                  onActiveChanged: (value) => setState(() => _isActive = value),
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

class _CenterFormBody extends StatelessWidget {
  const _CenterFormBody({
    required this.formKey,
    required this.nameController,
    required this.locationController,
    required this.capacityController,
    required this.amenitiesController,
    required this.notesController,
    required this.isActive,
    required this.isSaving,
    required this.onActiveChanged,
    required this.onSave,
    this.center,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController locationController;
  final TextEditingController capacityController;
  final TextEditingController amenitiesController;
  final TextEditingController notesController;
  final bool isActive;
  final bool isSaving;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onSave;
  final AdminCenter? center;

  @override
  Widget build(BuildContext context) {
    final isEditing = center != null;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (center != null) ...[
            _MetadataRow(center: center!),
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
                      Expanded(child: _locationField()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 220, child: _capacityField()),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _ActiveStatusCard(
                          isActive: isActive,
                          isSaving: isSaving,
                          onChanged: onActiveChanged,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'Amenities / Services',
            child: TextFormField(
              controller: amenitiesController,
              decoration: const InputDecoration(
                hintText: 'Strength zone, recovery lounge, group studio...',
              ),
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
            ),
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'Operational Note / Description',
            child: TextFormField(
              controller: notesController,
              decoration: const InputDecoration(
                hintText: 'Short center summary or operational notes.',
              ),
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              AdminStatusChip(
                label: isEditing ? 'API-loaded details' : 'New database row',
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
                label: isSaving ? 'Saving...' : 'Save Center',
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
      _locationField(),
      const SizedBox(height: 14),
      _capacityField(),
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
      label: 'Center Name',
      child: TextFormField(
        controller: nameController,
        decoration: const InputDecoration(hintText: 'Enter center name'),
        maxLength: 150,
        validator: _validateRequired,
      ),
    );
  }

  Widget _locationField() {
    return AdminFieldLabel(
      label: 'Location',
      child: TextFormField(
        controller: locationController,
        decoration: const InputDecoration(hintText: 'City or neighborhood'),
        maxLength: 150,
        validator: _validateRequired,
      ),
    );
  }

  Widget _capacityField() {
    return AdminFieldLabel(
      label: 'Capacity',
      hint: 'Use 0 when capacity is not configured.',
      child: TextFormField(
        controller: capacityController,
        decoration: const InputDecoration(hintText: '0'),
        keyboardType: TextInputType.number,
        validator: _validateCapacity,
      ),
    );
  }

  static String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }

    return null;
  }

  static String? _validateCapacity(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Capacity is required.';
    }

    final parsed = int.tryParse(text);
    if (parsed == null) {
      return 'Capacity must be a whole number.';
    }

    if (parsed < 0) {
      return 'Capacity must be 0 or greater.';
    }

    return null;
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
                  'Active center',
                  style: TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Inactive centers stay stored but are hidden from member browsing.',
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
  const _MetadataRow({required this.center});

  final AdminCenter center;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetadataPill(label: 'ID', value: center.id.toString()),
        _MetadataPill(
          label: 'Created',
          value: center.createdAt.toLocal().toString().split('.').first,
        ),
        AdminStatusChip(
          label: center.isActive ? 'Active' : 'Inactive',
          variant: center.isActive
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
      title = 'Loading center details',
      message = 'Please wait while the center is loaded from the API.',
      action = null,
      loading = true;

  factory _FormStateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _FormStateCard(
      icon: Icons.error_outline,
      title: 'Center details could not be loaded',
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
