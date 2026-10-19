import 'package:flutter/material.dart';

import '../models/training_preferences.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';

class TrainingPreferencesScreen extends StatefulWidget {
  const TrainingPreferencesScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<TrainingPreferencesScreen> createState() =>
      _TrainingPreferencesScreenState();
}

class _TrainingPreferencesScreenState extends State<TrainingPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  bool _hasPreferences = false;
  String? _loadError;
  String? _saveError;
  String? _goalError;
  String? _interestError;
  String? _goal;
  final Set<String> _interests = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final preferences = await widget.centerApiService
          .getTrainingPreferences();
      if (!mounted) return;
      setState(() {
        _goal = preferences?.primaryGoal;
        _interests
          ..clear()
          ..addAll(preferences?.interests ?? []);
        _hasPreferences = preferences != null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  void _selectInterest(String interest, bool selected) {
    setState(() {
      _saved = false;
      _saveError = null;
      if (selected && _interests.length >= 2) {
        _interestError =
            'Select at most two interests. Deselect one to choose another.';
        return;
      }
      if (selected) {
        _interests.add(interest);
      } else {
        _interests.remove(interest);
      }
      _interestError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saved = false;
      _saveError = null;
      _goalError = _goal == null ? 'Select a primary goal.' : null;
    });
    if (_goalError != null || _interests.length > 2) return;
    setState(() => _saving = true);
    try {
      final preferences = await widget.centerApiService.saveTrainingPreferences(
        TrainingPreferences(
          primaryGoal: _goal!,
          interests: _interests.toList(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _goal = preferences.primaryGoal;
        _interests
          ..clear()
          ..addAll(preferences.interests);
        _hasPreferences = true;
        _saved = true;
        _saving = false;
        _interestError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  Widget _error(String message) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      children: [
        IronBookMobileHeader(
          title: 'Training Preferences',
          subtitle: 'Choose your goal and optional training interests.',
          onBack: () => Navigator.of(context).pop(),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          IronBookMobileSection(
            child: Column(
              children: [
                Text(
                  'Preferences unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _error(_loadError!),
                const SizedBox(height: 12),
                IronBookMobileButton.primary(
                  onPressed: _load,
                  label: 'Retry',
                  icon: Icons.refresh,
                ),
              ],
            ),
          )
        else ...[
          if (!_hasPreferences)
            const IronBookMobileSection(
              muted: true,
              child: Text(
                'No training preferences saved yet. Choose a primary goal to get started.',
              ),
            ),
          IronBookMobileSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Primary goal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text('Choose one goal.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final goal in trainingPreferenceGoals)
                      ChoiceChip(
                        label: Text(goal),
                        selected: _goal == goal,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                _goal = goal;
                                _goalError = null;
                                _saved = false;
                                _saveError = null;
                              }),
                      ),
                  ],
                ),
                if (_goalError != null) _error(_goalError!),
              ],
            ),
          ),
          IronBookMobileSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Interests (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose up to two interests. ${_interests.length}/2 selected.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final interest in trainingPreferenceInterests.entries)
                      FilterChip(
                        label: Text(interest.value),
                        selected: _interests.contains(interest.key),
                        onSelected: _saving
                            ? null
                            : (selected) =>
                                  _selectInterest(interest.key, selected),
                      ),
                  ],
                ),
                if (_interestError != null) _error(_interestError!),
              ],
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
          if (_saveError != null) _error(_saveError!),
          if (_saved)
            Semantics(
              liveRegion: true,
              child: const IronBookTag(
                label: 'Training preferences saved.',
                variant: IronBookTagVariant.success,
              ),
            ),
          IronBookMobileButton.primary(
            onPressed: _saving ? null : _save,
            label: _saving ? 'Saving...' : 'Save preferences',
            icon: Icons.save_outlined,
          ),
        ],
      ],
    );
  }
}
