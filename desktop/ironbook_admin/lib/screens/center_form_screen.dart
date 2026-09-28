import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../services/admin_center_api_service.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Center' : 'Add Center')),
      body: SafeArea(
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
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _FormError(
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
                    return const _FormError(
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
                    onActiveChanged: (value) =>
                        setState(() => _isActive = value),
                    onSave: _save,
                  );
                },
              ),
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
    final theme = Theme.of(context);
    final isEditing = center != null;

    return Container(
      color: const Color(0xFFF5F7FA),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFDDE3EA)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Center Details' : 'New Center',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isEditing
                          ? 'Update center information and active status.'
                          : 'Create a center record for the admin catalog.',
                    ),
                    if (center != null) ...[
                      const SizedBox(height: 18),
                      _MetadataRow(center: center!),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              border: OutlineInputBorder(),
                            ),
                            maxLength: 150,
                            validator: _validateRequired,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: locationController,
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder(),
                            ),
                            maxLength: 150,
                            validator: _validateRequired,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextFormField(
                            controller: capacityController,
                            decoration: const InputDecoration(
                              labelText: 'Capacity',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: _validateCapacity,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active center'),
                            subtitle: const Text(
                              'Inactive centers stay stored but are hidden from member browsing.',
                            ),
                            value: isActive,
                            onChanged: isSaving ? null : onActiveChanged,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: amenitiesController,
                      decoration: const InputDecoration(
                        labelText: 'Amenities',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 1000,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: isSaving ? null : onSave,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(isSaving ? 'Saving...' : 'Save Center'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.center});

  final AdminCenter center;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _MetadataPill(label: 'ID', value: center.id.toString()),
        _MetadataPill(
          label: 'Created',
          value: center.createdAt.toLocal().toString().split('.').first,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 16),
            const Text('Center details could not be loaded'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
