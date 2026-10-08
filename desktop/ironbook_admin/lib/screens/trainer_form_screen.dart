import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_trainer.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_trainer_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

class TrainerFormScreen extends StatefulWidget {
  const TrainerFormScreen({
    super.key,
    this.trainerId,
    required this.trainerApiService,
    required this.centerApiService,
  });

  final int? trainerId;
  final AdminTrainerApiService trainerApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<TrainerFormScreen> createState() => _TrainerFormScreenState();
}

class _TrainerFormScreenState extends State<TrainerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _biographyController = TextEditingController();
  final Set<int> _selectedCenterIds = <int>{};

  Future<_TrainerFormData>? _formDataFuture;
  bool _isActive = true;
  bool _isSaving = false;

  bool get _isEditing => widget.trainerId != null;

  @override
  void initState() {
    super.initState();
    _formDataFuture = _loadFormData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _biographyController.dispose();
    super.dispose();
  }

  Future<_TrainerFormData> _loadFormData() async {
    final centersFuture = widget.centerApiService.getCenters();
    final trainerId = widget.trainerId;

    if (trainerId == null) {
      return _TrainerFormData(centers: await centersFuture);
    }

    final results = await Future.wait<Object>([
      centersFuture,
      widget.trainerApiService.getTrainer(trainerId),
    ]);

    final trainer = results[1] as AdminTrainer;
    _applyTrainer(trainer);

    return _TrainerFormData(
      centers: results[0] as List<AdminCenter>,
      trainer: trainer,
    );
  }

  void _applyTrainer(AdminTrainer trainer) {
    _firstNameController.text = trainer.firstName;
    _lastNameController.text = trainer.lastName;
    _emailController.text = trainer.email;
    _phoneController.text = trainer.phoneNumber ?? '';
    _biographyController.text = trainer.biography ?? '';
    _isActive = trainer.isActive;
    _selectedCenterIds
      ..clear()
      ..addAll(trainer.centers.map((center) => center.centerId));
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final request = AdminTrainerWriteRequest(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _optionalText(_phoneController.text),
      biography: _optionalText(_biographyController.text),
      isActive: _isActive,
      centerIds: _selectedCenterIds.toList()..sort(),
    );

    setState(() => _isSaving = true);

    try {
      final trainerId = widget.trainerId;
      if (trainerId == null) {
        await widget.trainerApiService.createTrainer(request);
      } else {
        await widget.trainerApiService.updateTrainer(trainerId, request);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AdminTrainerApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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
      title: _isEditing ? 'Trainer Profile' : 'Add Trainer',
      subtitle: _isEditing
          ? 'Edit trainer details and center assignments.'
          : 'Create a real trainer profile and assign centers.',
      actions: AdminButton.secondary(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        icon: Icons.arrow_back,
        label: 'Back to Trainers',
      ),
      child: FutureBuilder<_TrainerFormData>(
        future: _formDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _FormStateCard.loading();
          }

          if (snapshot.hasError) {
            return _FormStateCard.error(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _formDataFuture = _loadFormData()),
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return const _FormStateCard(
              icon: Icons.error_outline,
              title: 'Trainer form could not be loaded',
              message: 'No form data was returned.',
            );
          }

          return _TrainerFormBody(
            formKey: _formKey,
            firstNameController: _firstNameController,
            lastNameController: _lastNameController,
            emailController: _emailController,
            phoneController: _phoneController,
            biographyController: _biographyController,
            centers: data.centers,
            selectedCenterIds: _selectedCenterIds,
            isActive: _isActive,
            isSaving: _isSaving,
            trainer: data.trainer,
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

class _TrainerFormBody extends StatelessWidget {
  const _TrainerFormBody({
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    required this.biographyController,
    required this.centers,
    required this.selectedCenterIds,
    required this.isActive,
    required this.isSaving,
    required this.onActiveChanged,
    required this.onCenterChanged,
    required this.onSave,
    this.trainer,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController biographyController;
  final List<AdminCenter> centers;
  final Set<int> selectedCenterIds;
  final bool isActive;
  final bool isSaving;
  final ValueChanged<bool> onActiveChanged;
  final void Function(int centerId, bool selected) onCenterChanged;
  final VoidCallback onSave;
  final AdminTrainer? trainer;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trainer != null) ...[
            _TrainerProfileSummary(trainer: trainer!),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 680;
              final fields = [
                _textField('First Name', firstNameController, 100, true),
                _textField('Last Name', lastNameController, 100, true),
                _emailField(),
                _textField('Phone Number', phoneController, 50, false),
              ];

              if (!twoColumns) {
                return Column(children: _spaced(fields));
              }

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: fields
                    .map(
                      (field) => SizedBox(
                        width: (constraints.maxWidth - 14) / 2,
                        child: field,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          _ActiveStatusCard(
            isActive: isActive,
            isSaving: isSaving,
            onChanged: onActiveChanged,
          ),
          const SizedBox(height: 14),
          AdminFieldLabel(
            label: 'Biography',
            child: TextFormField(
              controller: biographyController,
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
                label: trainer == null ? 'New profile' : 'API-loaded profile',
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
                label: isSaving ? 'Saving...' : 'Save Trainer',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller,
    int maxLength,
    bool required,
  ) {
    return AdminFieldLabel(
      label: label,
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        validator: required ? _validateRequired : null,
      ),
    );
  }

  Widget _emailField() {
    return AdminFieldLabel(
      label: 'Email',
      child: TextFormField(
        controller: emailController,
        maxLength: 200,
        keyboardType: TextInputType.emailAddress,
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) {
            return 'Email is required.';
          }
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
            return 'Email format is invalid.';
          }
          return null;
        },
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> children) {
    final result = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        result.add(const SizedBox(height: 14));
      }
      result.add(children[index]);
    }
    return result;
  }

  static String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _TrainerProfileSummary extends StatelessWidget {
  const _TrainerProfileSummary({required this.trainer});

  final AdminTrainer trainer;

  @override
  Widget build(BuildContext context) {
    final centerText = trainer.centers.isEmpty
        ? 'No active centers assigned'
        : trainer.centers
              .map((center) => '${center.centerName} / ${center.location}')
              .join(', ');

    return AdminPanel(
      title: 'Profile Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trainer.displayName,
                  style: const TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AdminStatusChip(
                label: trainer.isActive ? 'Active' : 'Inactive',
                variant: trainer.isActive
                    ? AdminStatusVariant.success
                    : AdminStatusVariant.neutral,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            trainer.email,
            style: const TextStyle(
              color: IronBookAdminColors.slate500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            centerText,
            style: const TextStyle(
              color: IronBookAdminColors.slate600,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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
      title: 'Center Assignments',
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
                  'Active trainer',
                  style: TextStyle(
                    color: IronBookAdminColors.slate800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Inactive trainers remain stored but are excluded from Group Training trainer options.',
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

class _FormStateCard extends StatelessWidget {
  const _FormStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : loading = false;

  const _FormStateCard.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading trainer form',
      message = 'Please wait while trainer and center data are loaded.',
      action = null,
      loading = true;

  factory _FormStateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _FormStateCard(
      icon: Icons.error_outline,
      title: 'Trainer form could not be loaded',
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

class _TrainerFormData {
  const _TrainerFormData({required this.centers, this.trainer});

  final List<AdminCenter> centers;
  final AdminTrainer? trainer;
}
