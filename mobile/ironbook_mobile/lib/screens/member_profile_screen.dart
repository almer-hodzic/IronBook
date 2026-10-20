import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';

class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key, required this.centerApiService});
  final CenterApiService centerApiService;

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  MemberProfile? _profile;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _success = null;
    });
    try {
      final profile = await widget.centerApiService.getMemberProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
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

  void _edit() {
    final profile = _profile!;
    _firstName.text = profile.firstName;
    _lastName.text = profile.lastName;
    _email.text = profile.email;
    _phone.text = profile.phoneNumber ?? '';
    setState(() {
      _editing = true;
      _saveError = null;
      _success = null;
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.centerApiService.updateMemberProfile(
        firstName: _firstName.text,
        lastName: _lastName.text,
        email: _email.text,
        phoneNumber: _phone.text,
      );
      if (!mounted) return;
      if (saved.id != _profile!.id) {
        throw const CenterApiException(
          'The API returned an unexpected member profile.',
        );
      }
      setState(() {
        _profile = saved;
        _editing = false;
        _saving = false;
        _success = 'Profile saved successfully.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  String? _required(String? value, String label, int limit) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '$label is required.';
    if (trimmed.length > limit) {
      return '$label must be at most $limit characters.';
    }
    return null;
  }

  Widget _field(
    String label,
    String key,
    TextEditingController controller, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: Key(key),
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboardType,
        validator: validator,
        textCapitalization: keyboardType == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return IronBookMobileShell(
      children: [
        IronBookMobileHeader(
          title: 'Member Profile',
          subtitle: 'Your account details',
          onBack: _saving ? null : () => Navigator.of(context).pop(),
        ),
        if (_loading)
          const IronBookMobileSection(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          IronBookMobileSection(
            child: Column(
              children: [
                Text(_loadError!),
                const SizedBox(height: 12),
                IronBookMobileButton.secondary(
                  label: 'Retry',
                  onPressed: _load,
                ),
              ],
            ),
          )
        else if (profile != null) ...[
          if (_success != null)
            Semantics(liveRegion: true, child: Text(_success!)),
          IronBookMobileSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IronBookTag(
                  label: profile.isActive
                      ? 'Account active'
                      : 'Account inactive',
                  variant: profile.isActive
                      ? IronBookTagVariant.success
                      : IronBookTagVariant.neutral,
                ),
                const SizedBox(height: 14),
                _detail(
                  'Created date',
                  MaterialLocalizations.of(context)
                      .formatFullDate(profile.createdAt),
                ),
                if (_editing)
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _field(
                          'First name',
                          'profile-first-name',
                          _firstName,
                          validator: (value) =>
                              _required(value, 'First name', 100),
                        ),
                        _field(
                          'Last name',
                          'profile-last-name',
                          _lastName,
                          validator: (value) =>
                              _required(value, 'Last name', 100),
                        ),
                        _field(
                          'Email',
                          'profile-email',
                          _email,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final requiredError = _required(
                              value,
                              'Email',
                              200,
                            );
                            if (requiredError != null) return requiredError;
                            if (!RegExp(r'^[^\s@]+@[^\s@]+$')
                                .hasMatch(value!.trim())) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        _field(
                          'Phone number (optional)',
                          'profile-phone',
                          _phone,
                          keyboardType: TextInputType.phone,
                          validator: (value) => (value?.trim().length ?? 0) > 50
                              ? 'Phone number must be at most 50 characters.'
                              : null,
                        ),
                        if (_saveError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_saveError!),
                            ),
                          ),
                        if (_saving)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: CircularProgressIndicator(),
                          ),
                        IronBookMobileButton.primary(
                          label: _saving ? 'Saving...' : 'Save changes',
                          onPressed: _saving ? null : _save,
                        ),
                        const SizedBox(height: 10),
                        IronBookMobileButton.secondary(
                          label: 'Cancel edit',
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _editing = false;
                                  _saveError = null;
                                }),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _detail('First name', profile.firstName),
                  _detail('Last name', profile.lastName),
                  _detail('Email', profile.email),
                  _detail(
                    'Phone number',
                    profile.phoneNumber?.isNotEmpty == true
                        ? profile.phoneNumber!
                        : 'Not provided',
                  ),
                  IronBookMobileButton.primary(
                    label: 'Edit profile',
                    icon: Icons.edit_outlined,
                    onPressed: _edit,
                  ),
                  const SizedBox(height: 10),
                  IronBookMobileButton.secondary(
                    label: 'Refresh',
                    icon: Icons.refresh,
                    onPressed: _load,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
