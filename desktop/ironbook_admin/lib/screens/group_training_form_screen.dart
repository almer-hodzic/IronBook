import 'package:flutter/material.dart';

import '../models/admin_center.dart';
import '../models/admin_group_training.dart';
import '../services/admin_center_api_service.dart';
import '../services/admin_group_training_api_service.dart';
import '../theme/ironbook_admin_colors.dart';
import '../widgets/admin_primitives.dart';
import 'admin_shell.dart';

const _categories = [
  'Strength',
  'Conditioning',
  'Recovery',
  'Performance',
  'FatLoss',
];
const _difficulties = ['Beginner', 'Intermediate', 'Advanced'];
const _statuses = ['Active', 'Inactive'];

class GroupTrainingFormScreen extends StatefulWidget {
  const GroupTrainingFormScreen({
    super.key,
    this.groupTrainingId,
    required this.groupTrainingApiService,
    required this.centerApiService,
  });

  final int? groupTrainingId;
  final AdminGroupTrainingApiService groupTrainingApiService;
  final AdminCenterApiService centerApiService;

  @override
  State<GroupTrainingFormScreen> createState() =>
      _GroupTrainingFormScreenState();
}

class _GroupTrainingFormScreenState extends State<GroupTrainingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _capacityController = TextEditingController(text: '12');
  final _descriptionController = TextEditingController();
  final _includesController = TextEditingController();
  final _whoForController = TextEditingController();

  Future<_GroupTrainingFormData>? _formDataFuture;
  List<AdminTrainerOption> _trainerOptions = const [];
  int? _selectedCenterId;
  int? _selectedTrainerId;
  String _category = _categories.first;
  String _difficulty = _difficulties[1];
  String _status = _statuses.first;
  bool _isSaving = false;
  bool _isLoadingTrainers = false;

  bool get _isEditing => widget.groupTrainingId != null;

  @override
  void initState() {
    super.initState();
    _formDataFuture = _loadFormData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startController.dispose();
    _durationController.dispose();
    _capacityController.dispose();
    _descriptionController.dispose();
    _includesController.dispose();
    _whoForController.dispose();
    super.dispose();
  }

  Future<_GroupTrainingFormData> _loadFormData() async {
    final centersFuture = widget.centerApiService.getCenters();
    final id = widget.groupTrainingId;

    final centers = await centersFuture;
    final activeCenters = centers.where((center) => center.isActive).toList();
    AdminGroupTraining? training;

    if (id != null) {
      training = await widget.groupTrainingApiService.getGroupTraining(id);
      _applyTraining(training);
    } else if (activeCenters.isNotEmpty) {
      _selectedCenterId = activeCenters.first.id;
      _startController.text = _formatDateTime(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
    }

    _trainerOptions = await widget.groupTrainingApiService.getTrainerOptions(
      centerId: _selectedCenterId,
    );
    if (_selectedTrainerId == null && _trainerOptions.isNotEmpty) {
      _selectedTrainerId = _trainerOptions.first.id;
    }

    return _GroupTrainingFormData(centers: activeCenters, training: training);
  }

  void _applyTraining(AdminGroupTraining training) {
    _nameController.text = training.name;
    _descriptionController.text = training.description ?? '';
    _includesController.text = training.includes ?? '';
    _whoForController.text = training.whoFor ?? '';
    _startController.text = _formatDateTime(training.startsAt.toLocal());
    _durationController.text = training.durationMinutes.toString();
    _capacityController.text = training.capacity.toString();
    _selectedCenterId = training.centerId;
    _selectedTrainerId = training.trainerProfileId;
    _category = training.category;
    _difficulty = training.difficulty;
    _status = training.status == 'Full' ? 'Active' : training.status;
  }

  Future<void> _loadTrainersForCenter(int centerId) async {
    setState(() {
      _isLoadingTrainers = true;
      _selectedCenterId = centerId;
      _selectedTrainerId = null;
    });

    try {
      final trainers = await widget.groupTrainingApiService.getTrainerOptions(
        centerId: centerId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _trainerOptions = trainers;
        _selectedTrainerId = trainers.isEmpty ? null : trainers.first.id;
      });
    } on AdminGroupTrainingApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingTrainers = false);
      }
    }
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final startsAt = _parseDateTime(_startController.text.trim());
    if (startsAt == null) {
      _showError('Start date must use yyyy-MM-dd HH:mm.');
      return;
    }

    final request = AdminGroupTrainingWriteRequest(
      name: _nameController.text.trim(),
      description: _optionalText(_descriptionController.text),
      centerId: _selectedCenterId!,
      trainerProfileId: _selectedTrainerId!,
      category: _category,
      difficulty: _difficulty,
      startsAt: startsAt,
      durationMinutes: int.parse(_durationController.text.trim()),
      capacity: int.parse(_capacityController.text.trim()),
      status: _status,
      includes: _optionalText(_includesController.text),
      whoFor: _optionalText(_whoForController.text),
    );

    setState(() => _isSaving = true);

    try {
      final id = widget.groupTrainingId;
      if (id == null) {
        await widget.groupTrainingApiService.createGroupTraining(request);
      } else {
        await widget.groupTrainingApiService.updateGroupTraining(id, request);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AdminGroupTrainingApiException catch (error) {
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
      title: _isEditing ? 'Edit Group Training' : 'Create Group Training',
      subtitle: _isEditing
          ? 'Update schedule, trainer, capacity, and availability.'
          : 'Create a real center-scoped class backed by the API.',
      actions: AdminButton.secondary(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        icon: Icons.arrow_back,
        label: 'Back to Memberships',
      ),
      child: FutureBuilder<_GroupTrainingFormData>(
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
              title: 'Group training form could not be loaded',
              message: 'No form data was returned.',
            );
          }

          return Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.training != null) ...[
                  _MetadataRow(training: data.training!),
                  const SizedBox(height: 14),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 680;
                    final fields = [
                      _nameField(),
                      _centerField(data.centers),
                      _trainerField(),
                      _selectField(
                        label: 'Category',
                        value: _category,
                        values: _categories,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                      _selectField(
                        label: 'Difficulty',
                        value: _difficulty,
                        values: _difficulties,
                        onChanged: (value) =>
                            setState(() => _difficulty = value),
                      ),
                      _selectField(
                        label: 'Status',
                        value: _status,
                        values: _statuses,
                        onChanged: (value) => setState(() => _status = value),
                      ),
                      _startField(),
                      _numberField(
                        label: 'Duration Minutes',
                        controller: _durationController,
                      ),
                      _numberField(
                        label: 'Capacity',
                        controller: _capacityController,
                      ),
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
                _textArea('Description', _descriptionController, 1000),
                const SizedBox(height: 14),
                _textArea('What Is Included', _includesController, 2000),
                const SizedBox(height: 14),
                _textArea('Who It Is For', _whoForController, 1000),
                const SizedBox(height: 18),
                Row(
                  children: [
                    AdminStatusChip(
                      label: data.training == null
                          ? 'New database row'
                          : 'API-loaded details',
                      variant: AdminStatusVariant.accent,
                    ),
                    const Spacer(),
                    AdminButton.secondary(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: Icons.close,
                      label: 'Cancel',
                    ),
                    const SizedBox(width: 8),
                    AdminButton.primary(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving ? null : Icons.save_outlined,
                      label: _isSaving ? 'Saving...' : 'Save Training',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _nameField() {
    return AdminFieldLabel(
      label: 'Training Name',
      child: TextFormField(
        controller: _nameController,
        maxLength: 150,
        decoration: const InputDecoration(hintText: 'e.g. Iron Strength'),
        validator: _validateRequired,
      ),
    );
  }

  Widget _centerField(List<AdminCenter> centers) {
    return AdminFieldLabel(
      label: 'Center',
      child: DropdownButtonFormField<int>(
        initialValue: _selectedCenterId,
        items: centers
            .map(
              (center) => DropdownMenuItem(
                value: center.id,
                child: Text('${center.name} / ${center.location}'),
              ),
            )
            .toList(),
        onChanged: _isSaving
            ? null
            : (value) {
                if (value != null) {
                  _loadTrainersForCenter(value);
                }
              },
        validator: (value) => value == null ? 'Center is required.' : null,
      ),
    );
  }

  Widget _trainerField() {
    return AdminFieldLabel(
      label: 'Trainer',
      child: DropdownButtonFormField<int>(
        initialValue: _selectedTrainerId,
        items: _trainerOptions
            .map(
              (trainer) => DropdownMenuItem(
                value: trainer.id,
                child: Text('${trainer.displayName} / ${trainer.email}'),
              ),
            )
            .toList(),
        onChanged: _isSaving || _isLoadingTrainers
            ? null
            : (value) => setState(() => _selectedTrainerId = value),
        validator: (value) => value == null ? 'Trainer is required.' : null,
        decoration: InputDecoration(
          hintText: _isLoadingTrainers
              ? 'Loading trainers...'
              : 'Select an active trainer',
        ),
      ),
    );
  }

  Widget _selectField({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return AdminFieldLabel(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: values
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: _isSaving
            ? null
            : (selected) {
                if (selected != null) {
                  onChanged(selected);
                }
              },
      ),
    );
  }

  Widget _startField() {
    return AdminFieldLabel(
      label: 'Start Date and Time',
      hint: 'Use yyyy-MM-dd HH:mm.',
      child: TextFormField(
        controller: _startController,
        decoration: const InputDecoration(hintText: '2026-10-08 18:00'),
        validator: (value) {
          if (_validateRequired(value) != null) {
            return 'Start date and time is required.';
          }
          return _parseDateTime(value!.trim()) == null
              ? 'Use yyyy-MM-dd HH:mm.'
              : null;
        },
      ),
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
  }) {
    return AdminFieldLabel(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        validator: _validatePositiveInt,
      ),
    );
  }

  Widget _textArea(String label, TextEditingController controller, int max) {
    return AdminFieldLabel(
      label: label,
      child: TextFormField(
        controller: controller,
        minLines: 3,
        maxLines: 6,
        maxLength: max,
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

  static String? _validatePositiveInt(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) {
      return 'Enter a whole number.';
    }
    if (parsed <= 0) {
      return 'Value must be greater than 0.';
    }
    return null;
  }

  static DateTime? _parseDateTime(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$')
        .firstMatch(value);
    if (match == null) {
      return null;
    }

    final parts = List.generate(
      5,
      (index) => int.parse(match.group(index + 1)!),
    );
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
  }

  static String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  static String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.training});

  final AdminGroupTraining training;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetadataPill(label: 'ID', value: training.id.toString()),
        _MetadataPill(
          label: 'Enrolled',
          value: '${training.enrolledCount}/${training.capacity}',
        ),
        AdminStatusChip(
          label: training.status,
          variant: training.status == 'Active'
              ? AdminStatusVariant.success
              : training.status == 'Full'
              ? AdminStatusVariant.warning
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
      title = 'Loading group training form',
      message = 'Please wait while training, center, and trainer data load.',
      action = null,
      loading = true;

  factory _FormStateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _FormStateCard(
      icon: Icons.error_outline,
      title: 'Group training form could not be loaded',
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

class _GroupTrainingFormData {
  const _GroupTrainingFormData({required this.centers, this.training});

  final List<AdminCenter> centers;
  final AdminGroupTraining? training;
}
