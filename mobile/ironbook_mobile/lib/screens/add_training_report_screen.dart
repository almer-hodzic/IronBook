import 'package:flutter/material.dart';

import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class AddTrainingReportScreen extends StatefulWidget {
  const AddTrainingReportScreen({
    super.key,
    required this.centerApiService,
    required this.trainingRequestId,
  });

  final CenterApiService centerApiService;
  final int trainingRequestId;

  @override
  State<AddTrainingReportScreen> createState() =>
      _AddTrainingReportScreenState();
}

class _AddTrainingReportScreenState extends State<AddTrainingReportScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<_ExerciseFormController> _exercises = [
    _ExerciseFormController(),
  ];
  late DateTime _trainingDate;
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _trainingDate = DateTime.now();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _addExercise() {
    setState(() {
      _exercises.add(_ExerciseFormController());
    });
  }

  void _removeExercise(int index) {
    if (_exercises.length <= 1) {
      return;
    }

    setState(() {
      _exercises.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    final exercises = <Map<String, Object?>>[];
    for (final exercise in _exercises) {
      final name = exercise.nameController.text.trim();
      final sets = int.tryParse(exercise.setsController.text);
      final reps = int.tryParse(exercise.repsController.text);
      final weightText = exercise.weightController.text.trim();
      final weight = weightText.isEmpty ? null : double.tryParse(weightText);

      exercises.add({
        'exerciseName': name,
        'sets': sets,
        'reps': reps,
        'weight': weight,
        'notes': exercise.notesController.text.trim().isEmpty
            ? null
            : exercise.notesController.text.trim(),
      });
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.centerApiService.createTrainingReport(
        trainingRequestId: widget.trainingRequestId,
        trainingDate: _trainingDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        exercises: exercises,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Training report saved.')));
      Navigator.of(context).pop(true);
    } on CenterApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Dashboard'),
      children: [
        IronBookMobileHeader(
          title: 'Add Training Report',
          subtitle: 'Record the completed coaching session.',
          onBack: () => Navigator.of(context).pop(),
        ),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IronBookMobileSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session details',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      value: _trainingDate,
                      onChanged: (value) => setState(() => _trainingDate = value),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Session notes',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              IronBookMobileSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Exercises',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IronBookMobileButton.secondary(
                          onPressed: _addExercise,
                          label: 'Add exercise',
                          icon: Icons.add,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._exercises.asMap().entries.map(
                      (entry) => _ExerciseEditor(
                        controller: entry.value,
                        index: entry.key,
                        isLast: entry.key == _exercises.length - 1,
                        onRemove: () => _removeExercise(entry.key),
                      ),
                    ),
                  ],
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 10),
                IronBookMobileSection(
                  muted: true,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: IronBookMobileColors.rose700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _submitError!,
                          style: const TextStyle(color: IronBookMobileColors.rose700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              IronBookMobileButton.primary(
                onPressed: _isSubmitting ? null : _submit,
                label: _isSubmitting ? 'Saving report...' : 'Save report',
                icon: Icons.save_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.onChanged,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(value.year - 1),
          lastDate: DateTime(value.year + 1),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Training date',
          border: OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
            ),
            const Icon(Icons.calendar_today_outlined),
          ],
        ),
      ),
    );
  }
}

class _ExerciseEditor extends StatelessWidget {
  const _ExerciseEditor({
    required this.controller,
    required this.index,
    required this.isLast,
    required this.onRemove,
  });

  final _ExerciseFormController controller;
  final int index;
  final bool isLast;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IronBookMobileColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IronBookMobileColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Exercise ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (index > 0)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove exercise',
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller.nameController,
            decoration: const InputDecoration(labelText: 'Exercise name'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter an exercise name.';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller.setsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sets'),
                  validator: _positiveIntegerValidator,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: controller.repsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reps'),
                  validator: _positiveIntegerValidator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller.weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight (optional)'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return null;
              }
              final parsed = double.tryParse(value);
              if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
                return 'Enter a valid weight.';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller.notesController,
            maxLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Exercise notes (optional)'),
          ),
        ],
      ),
    );
  }
}

String? _positiveIntegerValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter a number.';
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    return 'Enter a positive number.';
  }
  return null;
}

class _ExerciseFormController {
  final TextEditingController nameController = TextEditingController(text: '');
  final TextEditingController setsController = TextEditingController(text: '3');
  final TextEditingController repsController = TextEditingController(text: '10');
  final TextEditingController weightController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
}
