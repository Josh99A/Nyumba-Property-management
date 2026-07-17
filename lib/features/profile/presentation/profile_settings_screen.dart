import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../app/localization/locale_controller.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/language_menu_button.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../application/profile_use_cases.dart';
import '../domain/user_settings.dart';

// Transactional application email has no provider/SMTP adapter yet. Firebase
// Auth's verification and reset templates are a separate service.
const _emailDeliveryConfigured = false;

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
  bool _emailNotifications = false;
  bool _pushNotifications = true;
  bool _rentReminders = true;
  bool _maintenanceUpdates = true;
  bool _loading = true;
  bool _saving = false;
  bool _savingAppearance = false;
  String? _appearanceMessage;
  bool _appearanceSaveSucceeded = false;

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
      saved = await ref.read(loadUserSettingsProvider)(session.userId);
    } on Object catch (error) {
      loadError = error;
    }
    if (!mounted) return;
    setState(() {
      _nameController.text = saved?.displayName ?? session.displayName;
      _emailController.text = saved?.email ?? session.email;
      _phoneController.text = saved?.phone ?? session.phone;
      _themePreference = saved?.themePreference ?? ThemePreference.system;
      _emailNotifications =
          _emailDeliveryConfigured && (saved?.emailNotifications ?? false);
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
          content: Text.localized(
            'Saved settings could not be loaded on this device.',
          ),
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
      final saved = await ref.read(saveUserSettingsProvider)(
        UserSettings(
          userId: session.userId,
          displayName: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          themePreference: _themePreference,
          language: ref.read(localePreferenceProvider),
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
          content: Text.localized(
            'Settings saved on this device and queued for confirmation.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text.localized(error.message)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Settings could not be saved. Your edits are intact.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectAppearance(ThemePreference preference) async {
    if (_themePreference == preference) return;
    final copy = AppLocalizations.of(context)!;
    final previous = _themePreference;
    setState(() {
      _themePreference = preference;
      _savingAppearance = true;
      _appearanceSaveSucceeded = false;
      _appearanceMessage = copy.appearanceSavingOnDevice;
    });
    ref.read(themePreferenceProvider.notifier).select(preference);

    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    try {
      final current = await ref.read(loadUserSettingsProvider)(session.userId);
      await ref.read(saveUserSettingsProvider)(
        UserSettings(
          userId: session.userId,
          displayName: current?.displayName ?? session.displayName,
          email: current?.email ?? session.email,
          phone: current?.phone ?? session.phone,
          themePreference: preference,
          language: ref.read(localePreferenceProvider),
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
        _appearanceSaveSucceeded = true;
        _appearanceMessage = AppLocalizations.of(
          context,
        )!.appearanceAppliedOnDevice;
      });
    } on Object catch (error) {
      if (!mounted || _themePreference != preference) return;
      ref.read(themePreferenceProvider.notifier).load(previous);
      // A validation message names what actually blocked the save; the generic
      // line taught us nothing when an empty phone number was silently vetoing
      // theme changes for every account created without one.
      final reason = error is FormatException && error.message.isNotEmpty
          ? error.message
          : AppLocalizations.of(context)!.appearanceSaveTryAgain;
      setState(() {
        _themePreference = previous;
        _savingAppearance = false;
        _appearanceSaveSucceeded = false;
        _appearanceMessage = AppLocalizations.of(context)!.appearanceSaveFailed;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text.localized(reason)));
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
          padding: EdgeInsetsDirectional.fromSTEB(
            horizontal,
            28,
            horizontal,
            44,
          ),
          children: [
            PageHeader(
              title: 'Profile settings',
              description:
                  'Manage your personal details, appearance, language, and notifications.',
              primaryAction: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text.localized(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: context.isCompact
                    ? Column(
                        children: [
                          _accountCard(session.role.label),
                          const SizedBox(height: 16),
                          _preferenceCards(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _accountCard(session.role.label),
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
          decoration: InputDecoration(
            labelText: context.tr('Full name'),
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
          decoration: InputDecoration(
            labelText: context.tr('Email address'),
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
          decoration: InputDecoration(
            labelText: context.tr('Phone number'),
            hintText: context.tr('+256 772 123 456'),
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
                    Text.localized(
                      'Account role',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text.localized(
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
                  label: Text.localized('System'),
                ),
                ButtonSegment(
                  value: ThemePreference.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text.localized('Light'),
                ),
                ButtonSegment(
                  value: ThemePreference.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text.localized('Dark'),
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
                      _appearanceSaveSucceeded
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 17,
                      color: _appearanceSaveSucceeded
                          ? context.nyumba.sageDark
                          : context.nyumba.danger,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.localized(
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
        padding: const EdgeInsets.all(22),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NyumbaSectionHeader(
              title: 'Language',
              subtitle: 'Choose the language used throughout Nyumba.',
            ),
            SizedBox(height: 18),
            LanguageMenuButton(expanded: true),
          ],
        ),
      ),
      const SizedBox(height: 18),
      NyumbaSurface(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 22, 22, 10),
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
              subtitle: _emailDeliveryConfigured
                  ? 'Receive important account updates by email.'
                  : AppLocalizations.of(context)!.emailDeliveryNotConfigured,
              value: _emailNotifications,
              onChanged: _emailDeliveryConfigured
                  ? (value) => setState(() => _emailNotifications = value)
                  : null,
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
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text.localized(title, style: Theme.of(context).textTheme.titleSmall),
    subtitle: Text.localized(subtitle),
    value: value,
    onChanged: onChanged,
  );
}
