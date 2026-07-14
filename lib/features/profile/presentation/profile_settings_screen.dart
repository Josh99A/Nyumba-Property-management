import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../domain/user_settings.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  ThemePreference _themePreference = ThemePreference.system;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _rentReminders = true;
  bool _maintenanceUpdates = true;
  bool _loading = true;
  bool _saving = false;
  bool _savingAppearance = false;
  String? _appearanceMessage;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    UserSettings? saved;
    Object? loadError;
    try {
      saved = await ref
          .read(appDependenciesProvider)
          .userSettings
          .getByUserId(session.userId);
    } on Object catch (error) {
      loadError = error;
    }
    if (!mounted) return;
    setState(() {
      _nameController.text = saved?.displayName ?? session.displayName;
      _emailController.text = saved?.email ?? session.email;
      _phoneController.text = saved?.phone ?? session.phone;
      _themePreference = saved?.themePreference ?? ThemePreference.system;
      _emailNotifications = saved?.emailNotifications ?? true;
      _pushNotifications = saved?.pushNotifications ?? true;
      _rentReminders = saved?.rentReminders ?? true;
      _maintenanceUpdates = saved?.maintenanceUpdates ?? true;
      _loading = false;
    });
    ref
        .read(themePreferenceProvider.notifier)
        .load(saved?.themePreference ?? ThemePreference.system);
    if (loadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved settings could not be loaded on this device.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(appDependenciesProvider)
          .userSettings
          .save(
            UserSettings(
              userId: session.userId,
              displayName: _nameController.text,
              email: _emailController.text,
              phone: _phoneController.text,
              themePreference: _themePreference,
              emailNotifications: _emailNotifications,
              pushNotifications: _pushNotifications,
              rentReminders: _rentReminders,
              maintenanceUpdates: _maintenanceUpdates,
              updatedAt: DateTime.now().toUtc(),
              syncMetadata: const SyncMetadata.pending(),
            ),
          );
      ref
          .read(sessionControllerProvider.notifier)
          .updateProfile(
            displayName: saved.displayName,
            email: saved.email,
            phone: saved.phone,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Settings saved on this device and queued for confirmation.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings could not be saved. Your edits are intact.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectAppearance(ThemePreference preference) async {
    if (_themePreference == preference) return;
    final previous = _themePreference;
    setState(() {
      _themePreference = preference;
      _savingAppearance = true;
      _appearanceMessage = 'Saving on this device…';
    });
    ref.read(themePreferenceProvider.notifier).select(preference);

    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    try {
      final repository = ref.read(appDependenciesProvider).userSettings;
      final current = await repository.getByUserId(session.userId);
      await repository.save(
        UserSettings(
          userId: session.userId,
          displayName: current?.displayName ?? session.displayName,
          email: current?.email ?? session.email,
          phone: current?.phone ?? session.phone,
          themePreference: preference,
          emailNotifications:
              current?.emailNotifications ?? _emailNotifications,
          pushNotifications: current?.pushNotifications ?? _pushNotifications,
          rentReminders: current?.rentReminders ?? _rentReminders,
          maintenanceUpdates:
              current?.maintenanceUpdates ?? _maintenanceUpdates,
          updatedAt: DateTime.now().toUtc(),
          syncMetadata: const SyncMetadata.pending(),
        ),
      );
      if (!mounted || _themePreference != preference) return;
      ref.read(themePreferenceProvider.notifier).load(preference);
      setState(() {
        _savingAppearance = false;
        _appearanceMessage = 'Applied and saved on this device.';
      });
    } on Object {
      if (!mounted || _themePreference != preference) return;
      ref.read(themePreferenceProvider.notifier).load(previous);
      setState(() {
        _themePreference = previous;
        _savingAppearance = false;
        _appearanceMessage = 'Could not save this appearance setting.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appearance could not be saved. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (_loading || session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final horizontal = context.isCompact ? 18.0 : 30.0;
    return SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 44),
          children: [
            PageHeader(
              title: 'Profile settings',
              description:
                  'Manage your personal details, appearance, and notifications.',
              primaryAction: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: context.isCompact
                    ? Column(
                        children: [
                          _accountCard(session.role.name),
                          const SizedBox(height: 16),
                          _preferenceCards(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _accountCard(session.role.name),
                          ),
                          const SizedBox(width: 18),
                          Expanded(flex: 4, child: _preferenceCards()),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(String role) => NyumbaSurface(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NyumbaSectionHeader(
          title: 'Personal details',
          subtitle: 'These details identify you across your Nyumba workspace.',
        ),
        const SizedBox(height: 22),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) =>
              (value?.trim().length ?? 0) < 2 ? 'Enter your full name.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                ? null
                : 'Enter a valid email address.';
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+256 772 123 456',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: (value) {
            final normalized = (value ?? '').replaceAll(
              RegExp(r'[\s\-()]'),
              '',
            );
            final candidate = normalized.startsWith('0')
                ? '+256${normalized.substring(1)}'
                : normalized;
            return RegExp(r'^\+256\d{9}$').hasMatch(candidate)
                ? null
                : 'Use a valid Uganda phone number.';
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.nyumba.neutralTint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.nyumba.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.badge_outlined, color: context.nyumba.mutedInk),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account role',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      role[0].toUpperCase() + role.substring(1),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Roles are managed by an administrator.',
                child: Icon(
                  Icons.lock_outline,
                  color: context.nyumba.mutedInk,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _preferenceCards() => Column(
    children: [
      NyumbaSurface(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NyumbaSectionHeader(
              title: 'Appearance',
              subtitle: 'Choose how Nyumba looks on this device.',
            ),
            const SizedBox(height: 18),
            SegmentedButton<ThemePreference>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemePreference.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemePreference.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemePreference.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {_themePreference},
              onSelectionChanged: (value) => _selectAppearance(value.single),
            ),
            if (_appearanceMessage != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_savingAppearance)
                    const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _appearanceMessage!.startsWith('Applied')
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 17,
                      color: _appearanceMessage!.startsWith('Applied')
                          ? context.nyumba.sageDark
                          : context.nyumba.danger,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _appearanceMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      NyumbaSurface(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NyumbaSectionHeader(
              title: 'Notifications',
              subtitle: 'Select the updates you want to receive.',
            ),
            const SizedBox(height: 10),
            _settingSwitch(
              title: 'Email notifications',
              subtitle: 'Receive important account updates by email.',
              value: _emailNotifications,
              onChanged: (value) => setState(() => _emailNotifications = value),
            ),
            _settingSwitch(
              title: 'Push notifications',
              subtitle: 'Allow alerts on this device.',
              value: _pushNotifications,
              onChanged: (value) => setState(() => _pushNotifications = value),
            ),
            _settingSwitch(
              title: 'Rent reminders',
              subtitle: 'Upcoming and overdue rent notices.',
              value: _rentReminders,
              onChanged: (value) => setState(() => _rentReminders = value),
            ),
            _settingSwitch(
              title: 'Maintenance updates',
              subtitle: 'Status changes and new comments.',
              value: _maintenanceUpdates,
              onChanged: (value) => setState(() => _maintenanceUpdates = value),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _settingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}
