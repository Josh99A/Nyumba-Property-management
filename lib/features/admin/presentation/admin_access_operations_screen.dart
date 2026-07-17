import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import 'widgets/admin_components.dart';

class AdminAccessOperationsScreen extends ConsumerStatefulWidget {
  const AdminAccessOperationsScreen({super.key});

  @override
  ConsumerState<AdminAccessOperationsScreen> createState() =>
      _AdminAccessOperationsScreenState();
}

class _AdminAccessOperationsScreenState
    extends ConsumerState<AdminAccessOperationsScreen> {
  _AccessFilter _filter = _AccessFilter.all;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();
    final role = session.role;
    final visibleResources = _accessDefinitions
        .where((definition) {
          final operations = AuthorizationPolicy.operationsFor(
            role,
            definition.resource,
          );
          return _filter.includes(operations);
        })
        .toList(growable: false);
    final fullAccessCount = _accessDefinitions
        .where(
          (definition) =>
              AuthorizationPolicy.operationsFor(
                role,
                definition.resource,
              ).length ==
              CrudOperation.values.length,
        )
        .length;
    final limitedCount = _accessDefinitions.where((definition) {
      final operations = AuthorizationPolicy.operationsFor(
        role,
        definition.resource,
      );
      return operations.isNotEmpty &&
          operations.length < CrudOperation.values.length;
    }).length;
    final protectedCount =
        _accessDefinitions.length - fullAccessCount - limitedCount;

    return AdminPage(
      title: 'Access & operations',
      description:
          'See exactly what ${role.label} can create, read, update, and archive.',
      showsDemoData: false,
      children: [
        _RoleAccessHero(role: role),
        const SizedBox(height: 18),
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Full CRUD',
              value: '$fullAccessCount',
              caption: 'Resources with all four operations',
              icon: Icons.verified_user_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Limited access',
              value: '$limitedCount',
              caption: 'Read-only or controlled operations',
              icon: Icons.rule_folder_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Protected',
              value: '$protectedCount',
              caption: 'No permission for this role',
              icon: Icons.lock_outline_rounded,
              tone: context.nyumba.danger,
            ),
            AdminMetricCard(
              label: 'Policy source',
              value: 'RBAC',
              caption: 'Mirrored and rechecked by the server',
              icon: Icons.policy_outlined,
              tone: context.nyumba.midnightNavy,
            ),
          ],
        ),
        const SizedBox(height: 20),
        NyumbaSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.localized(
                'Filter resources',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final filter in _AccessFilter.values)
                    ChoiceChip(
                      label: Text.localized(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (visibleResources.isEmpty)
          const NyumbaSurface(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text.localized('No resources match this access filter.'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              const spacing = 14.0;
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final definition in visibleResources)
                    SizedBox(
                      width: cardWidth,
                      child: _ResourceAccessCard(
                        role: role,
                        definition: definition,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _RoleAccessHero extends StatelessWidget {
  const _RoleAccessHero({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = role == AppRole.superAdmin;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.nyumba.midnightNavy,
            context.nyumba.midnightNavy.withValues(alpha: .88),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isSuperAdmin
                  ? Icons.security_rounded
                  : Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  '${role.label} permissions',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text.localized(
                  isSuperAdmin
                      ? 'Full operational access, including privileged-role '
                            'management. Audit history remains read-only and '
                            'provider-confirmed money remains server-controlled.'
                      : 'Broad site operations are available. Admin and Super '
                            'Admin accounts remain protected, and audit history '
                            'is read-only.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .82),
                  ),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: isSuperAdmin
                ? 'Full site operations'
                : 'Almost all operations',
            tone: BadgeTone.success,
            icon: Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _ResourceAccessCard extends StatelessWidget {
  const _ResourceAccessCard({required this.role, required this.definition});

  final AppRole role;
  final _ResourceAccessDefinition definition;

  @override
  Widget build(BuildContext context) {
    final operations = AuthorizationPolicy.operationsFor(
      role,
      definition.resource,
    );
    final canOpen =
        definition.route != null && operations.contains(CrudOperation.read);
    return NyumbaSurface(
      key: ValueKey('access-${definition.resource.name}'),
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 218),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.nyumba.navyTint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    definition.icon,
                    color: context.nyumba.midnightNavy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.localized(
                        definition.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text.localized(
                        _scopeFor(role, definition.resource),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _AccessLevelBadge(operations: operations),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final operation in CrudOperation.values)
                  _OperationChip(
                    operation: operation,
                    allowed: operations.contains(operation),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (canOpen)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => context.go(definition.route!),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text.localized('Open workspace'),
                ),
              )
            else
              Text.localized(
                operations.isEmpty
                    ? 'This area is protected for ${role.label}.'
                    : 'Managed through controlled server operations.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessLevelBadge extends StatelessWidget {
  const _AccessLevelBadge({required this.operations});

  final Set<CrudOperation> operations;

  @override
  Widget build(BuildContext context) {
    if (operations.length == CrudOperation.values.length) {
      return const StatusBadge(label: 'Full CRUD', tone: BadgeTone.success);
    }
    if (operations.isEmpty) {
      return const StatusBadge(label: 'No access', tone: BadgeTone.neutral);
    }
    if (operations.length == 1 && operations.contains(CrudOperation.read)) {
      return const StatusBadge(label: 'Read only', tone: BadgeTone.info);
    }
    return const StatusBadge(label: 'Limited', tone: BadgeTone.warning);
  }
}

class _OperationChip extends StatelessWidget {
  const _OperationChip({required this.operation, required this.allowed});

  final CrudOperation operation;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final label = switch (operation) {
      CrudOperation.create => 'Create',
      CrudOperation.read => 'Read',
      CrudOperation.update => 'Update',
      CrudOperation.delete => 'Archive',
    };
    return Semantics(
      label: context.tr('$label ${allowed ? 'allowed' : 'not allowed'}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: allowed ? context.nyumba.sageTint : context.nyumba.neutralTint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: allowed ? context.nyumba.sageBorder : context.nyumba.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allowed ? Icons.check_rounded : Icons.lock_outline_rounded,
              size: 15,
              color: allowed
                  ? context.nyumba.sageDark
                  : context.nyumba.mutedInk,
            ),
            const SizedBox(width: 5),
            Text.localized(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: allowed
                    ? context.nyumba.sageDark
                    : context.nyumba.mutedInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AccessFilter {
  all('All resources'),
  full('Full CRUD'),
  limited('Limited'),
  protected('Protected');

  const _AccessFilter(this.label);

  final String label;

  bool includes(Set<CrudOperation> operations) => switch (this) {
    _AccessFilter.all => true,
    _AccessFilter.full => operations.length == CrudOperation.values.length,
    _AccessFilter.limited =>
      operations.isNotEmpty && operations.length < CrudOperation.values.length,
    _AccessFilter.protected => operations.isEmpty,
  };
}

class _ResourceAccessDefinition {
  const _ResourceAccessDefinition({
    required this.resource,
    required this.label,
    required this.icon,
    this.route,
  });

  final AppResource resource;
  final String label;
  final IconData icon;
  final String? route;
}

String _scopeFor(AppRole role, AppResource resource) {
  if (role == AppRole.superAdmin) return 'Platform-wide controlled scope';
  if (role == AppRole.admin) {
    if (resource == AppResource.adminAccount) return 'View privileged accounts';
    if (resource == AppResource.superAdminAccount) {
      return 'Reserved for Super Admin';
    }
    return 'Platform-wide operational scope';
  }
  if (role == AppRole.landlord) return 'Owned landlord portfolio only';
  if (role == AppRole.tenant) return 'Own tenant portal only';
  return resource == AppResource.publicListing
      ? 'Published public information'
      : 'Own account records only';
}

const _accessDefinitions = <_ResourceAccessDefinition>[
  _ResourceAccessDefinition(
    resource: AppResource.superAdminAccount,
    label: 'Super Admin accounts',
    icon: Icons.security_rounded,
    route: '/admin/users',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.adminAccount,
    label: 'Admin accounts',
    icon: Icons.admin_panel_settings_outlined,
    route: '/admin/users',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.userAccount,
    label: 'User accounts',
    icon: Icons.manage_accounts_outlined,
    route: '/admin/users',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.profile,
    label: 'Profiles & settings',
    icon: Icons.person_outline_rounded,
    route: '/settings',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.landlordAccount,
    label: 'Landlord accounts',
    icon: Icons.real_estate_agent_outlined,
    route: '/admin/users',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.landlordApproval,
    label: 'Landlord approvals',
    icon: Icons.verified_user_outlined,
    route: '/admin',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.subscription,
    label: 'Subscriptions',
    icon: Icons.workspace_premium_outlined,
    route: '/admin/subscriptions',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.planCatalog,
    label: 'Plan catalogue',
    icon: Icons.view_list_outlined,
    route: '/admin/subscriptions',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.property,
    label: 'Properties',
    icon: Icons.apartment_outlined,
    route: '/properties',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.unit,
    label: 'Rental spaces',
    icon: Icons.meeting_room_outlined,
    route: '/properties',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.tenantRecord,
    label: 'Tenant records',
    icon: Icons.people_outline_rounded,
    route: '/tenants',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.lease,
    label: 'Leases',
    icon: Icons.assignment_outlined,
    route: '/tenants',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.invoice,
    label: 'Invoices',
    icon: Icons.request_quote_outlined,
    route: '/finances',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.payment,
    label: 'Payments',
    icon: Icons.payments_outlined,
    route: '/finances',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.receipt,
    label: 'Receipts',
    icon: Icons.receipt_long_outlined,
    route: '/finances',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.maintenanceRequest,
    label: 'Maintenance requests',
    icon: Icons.build_outlined,
    route: '/maintenance',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.notice,
    label: 'Notices',
    icon: Icons.campaign_outlined,
    route: '/documents',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.document,
    label: 'Documents',
    icon: Icons.description_outlined,
    route: '/documents',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.privateListing,
    label: 'Private listings',
    icon: Icons.sell_outlined,
    route: '/listings',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.publicListing,
    label: 'Public listings',
    icon: Icons.public_outlined,
    route: '/listings',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.application,
    label: 'Rental applications',
    icon: Icons.assignment_ind_outlined,
    route: '/listings',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.contactRequest,
    label: 'Contact requests',
    icon: Icons.contact_mail_outlined,
    route: '/listings',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.report,
    label: 'Reports',
    icon: Icons.analytics_outlined,
    route: '/admin/reports',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.auditLog,
    label: 'Audit logs',
    icon: Icons.history_rounded,
    route: '/admin/reports',
  ),
  _ResourceAccessDefinition(
    resource: AppResource.platformConfiguration,
    label: 'Platform configuration',
    icon: Icons.settings_suggest_outlined,
  ),
  _ResourceAccessDefinition(
    resource: AppResource.backendOperation,
    label: 'Backend operations',
    icon: Icons.dns_outlined,
  ),
];
