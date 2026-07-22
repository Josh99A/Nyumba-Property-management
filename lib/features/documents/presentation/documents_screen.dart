import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/localization/locale_controller.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/documents/nyumba_document_service.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../auth/application/session_controller.dart';
import '../../notices/application/notice_providers.dart';
import '../../notices/domain/notice.dart';
import '../../portfolio/domain/property.dart';
import '../../tenants/application/tenancy_providers.dart';
import '../../tenants/domain/tenancy.dart';
import '../application/document_providers.dart';
import '../domain/lease_document.dart';

/// One row of the unified documents list: either a generated document or a
/// tenant notice, with its printable projection and honest sync state.
final class _DocumentListEntry {
  const _DocumentListEntry({
    required this.typeLabel,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusTone,
    required this.issuedAt,
    required this.printable,
    required this.syncStatus,
    required this.icon,
    required this.iconTint,
  });

  final String typeLabel;
  final String number;
  final String title;
  final String subtitle;
  final String statusLabel;
  final BadgeTone statusTone;
  final DateTime issuedAt;
  final PrintableDocumentData printable;
  final AggregateSyncStatus syncStatus;
  final IconData icon;
  final bool iconTint;
}

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({
    super.key,
    this.documentService = const PdfDocumentService(),
  });

  final DocumentService documentService;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _filter = 'All';
  String? _busyDocument;

  String get _landlordId => ref.read(sessionControllerProvider)?.userId ?? '';

  @override
  Widget build(BuildContext context) {
    final documentsValue = ref.watch(leaseDocumentsProvider);
    final tenancies = ref.watch(tenanciesProvider).value ?? const <Tenancy>[];
    final notices = ref.watch(noticesProvider).value ?? const <Notice>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.pageGutter,
        26,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Documents',
                description:
                    'Print and share invoices, receipts, leases, and notices.',
                primaryAction: AsyncActionButton.filled(
                  onPressed: () => _createDocument(context, tenancies),
                  showBusyIndicator: false,
                  icon: const Icon(Icons.note_add_outlined),
                  child: const Text.localized('Create document'),
                ),
              ),
              const SizedBox(height: 24),
              documentsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaStatusMessage.fromError(
                  error,
                  localizations: appLocalizationsOf(context),
                  subject: appLocalizationsOf(context).statusSubjectDocuments,
                  onRetry: () => ref.invalidate(leaseDocumentsProvider),
                ),
                data: (documents) => _buildLoaded(
                  context,
                  _mergeEntries(documents, notices, outbox),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_DocumentListEntry> _mergeEntries(
    List<LeaseDocument> documents,
    List<Notice> notices,
    List<OutboxEntry> outbox,
  ) {
    final entries = <_DocumentListEntry>[
      for (final document in documents)
        _DocumentListEntry(
          typeLabel: document.type.label,
          number: document.number,
          title: '${document.type.label} · ${document.number}',
          subtitle:
              '${document.recipient} · ${document.unitLabel} '
              '${document.propertyName}',
          statusLabel: document.statusLabel,
          statusTone: switch (document.statusLabel.toLowerCase()) {
            'paid' || 'signed' => BadgeTone.success,
            final value when value.contains('awaiting') => BadgeTone.info,
            _ => BadgeTone.warning,
          },
          issuedAt: document.issuedAt,
          printable: PrintableDocumentData(
            language: ref.read(localePreferenceProvider),
            title: document.type.label,
            number: document.number,
            recipient: document.recipient,
            property: document.propertyName,
            unit: document.unitLabel,
            amountMinor: document.amountMinor,
            date: document.issuedAt,
            status: document.statusLabel,
          ),
          syncStatus: resolveAggregateSyncStatus(
            entityType: OfflineEntityType.leaseDocument,
            entityId: document.id,
            outbox: outbox,
            syncMetadata: document.syncMetadata,
          ),
          icon: document.type == LeaseDocumentType.receipt
              ? Icons.receipt_outlined
              : Icons.description_outlined,
          iconTint: document.type == LeaseDocumentType.receipt,
        ),
      for (final notice in notices)
        _DocumentListEntry(
          typeLabel: 'Notice',
          number: notice.reference,
          title: 'Notice · ${notice.title}',
          subtitle: '${notice.reference} · ${notice.audience}',
          statusLabel: notice.status == NoticeStatus.queued
              ? 'Queued to send'
              : 'Draft',
          statusTone: BadgeTone.info,
          issuedAt: notice.createdAt,
          printable: PrintableDocumentData(
            language: ref.read(localePreferenceProvider),
            title: 'Tenant notice — ${notice.title}',
            number: notice.reference,
            recipient: notice.audience,
            property: notice.audience,
            unit: '—',
            amountMinor: 0,
            date: notice.createdAt,
            status: notice.status == NoticeStatus.queued
                ? 'Queued to send'
                : 'Draft',
          ),
          syncStatus: resolveAggregateSyncStatus(
            entityType: OfflineEntityType.notice,
            entityId: notice.id,
            outbox: outbox,
            syncMetadata: notice.syncMetadata,
          ),
          icon: Icons.campaign_outlined,
          iconTint: false,
        ),
    ];
    entries.sort((left, right) => right.issuedAt.compareTo(left.issuedAt));
    return entries;
  }

  Widget _buildLoaded(BuildContext context, List<_DocumentListEntry> entries) {
    final filtered = entries.where((entry) {
      return _filter == 'All' || entry.typeLabel == _filter;
    }).toList();
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in const [
                  'All',
                  'Invoice',
                  'Receipt',
                  'Lease',
                  'Notice',
                ])
                  ChoiceChip(
                    label: Text.localized(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
          const Divider(),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text.localized('No documents in this category yet.'),
              ),
            )
          else
            for (final entry in filtered)
              _DocumentRow(
                entry: entry,
                busy: _busyDocument == entry.number,
                onPrint: () => _print(entry),
                onShare: () => _share(entry),
              ),
        ],
      ),
    );
  }

  Future<void> _print(_DocumentListEntry entry) async {
    setState(() => _busyDocument = entry.number);
    try {
      await widget.documentService.print(entry.printable);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text.localized('Could not print ${entry.number}: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  Future<void> _share(_DocumentListEntry entry) async {
    setState(() => _busyDocument = entry.number);
    try {
      await widget.documentService.share(entry.printable);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text.localized('Could not share ${entry.number}: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  Future<void> _createDocument(BuildContext context, List<Tenancy> tenancies) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.localized(
                'Create document',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_long_outlined),
                ),
                title: const Text.localized('Rent invoice'),
                subtitle: const Text.localized(
                  'Create a local draft awaiting sync',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  _createGeneratedDocument(
                    type: LeaseDocumentType.invoice,
                    tenancies: tenancies,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.handshake_outlined),
                ),
                title: const Text.localized('Lease agreement'),
                subtitle: const Text.localized(
                  'Generate an unsigned local draft',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  _createGeneratedDocument(
                    type: LeaseDocumentType.lease,
                    tenancies: tenancies,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: context.nyumba.navyTint,
                  child: Icon(
                    Icons.campaign_outlined,
                    color: context.nyumba.midnightNavy,
                  ),
                ),
                title: const Text.localized('Tenant notice'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  _createNotice();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGeneratedDocument({
    required LeaseDocumentType type,
    required List<Tenancy> tenancies,
  }) async {
    if (tenancies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Add a tenancy before creating a tenant document.',
          ),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    var selected = tenancies.first;
    final amount = TextEditingController(
      text: type == LeaseDocumentType.invoice
          ? (selected.monthlyRentMinor ~/ 100).toString()
          : '',
    );
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text.localized('Create ${type.label.toLowerCase()} draft'),
          content: SizedBox(
            width: 470,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Tenancy>(
                    initialValue: selected,
                    decoration: InputDecoration(
                      labelText: context.tr('Tenancy'),
                    ),
                    items: [
                      for (final tenancy in tenancies)
                        DropdownMenuItem(
                          value: tenancy,
                          child: Text(
                            '${tenancy.tenantName} · ${tenancy.unitLabel}, '
                            '${tenancy.propertyName}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selected = value;
                        if (type == LeaseDocumentType.invoice) {
                          amount.text = (value.monthlyRentMinor ~/ 100)
                              .toString();
                        }
                      });
                    },
                  ),
                  if (type == LeaseDocumentType.invoice) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Invoice amount (UGX)'),
                      ),
                      validator: (value) {
                        final parsed = int.tryParse(
                          (value ?? '').replaceAll(',', '').trim(),
                        );
                        return parsed == null || parsed <= 0
                            ? context.tr('Enter a valid amount')
                            : null;
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text.localized(
                    'This creates a local draft and queues it for server '
                    'confirmation. It is not yet issued or signed.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text.localized('Save draft'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      try {
        final amountMajor = type == LeaseDocumentType.invoice
            ? int.parse(amount.text.replaceAll(',', '').trim())
            : 0;
        await ref.read(createLeaseDocumentProvider)(
          CreateLeaseDocumentInput(
            landlordId: _landlordId,
            tenantId: selected.tenantUserId,
            type: type,
            recipient: selected.tenantName,
            propertyName: selected.propertyName,
            unitLabel: selected.unitLabel,
            amountMinor: amountMajor * 100,
            statusLabel: 'Draft · awaiting confirmation',
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text.localized(
                '${type.label} draft saved locally and queued to sync.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('Could not create the document: $error'),
              ),
            ),
          );
        }
      }
    }
    amount.dispose();
  }

  Future<void> _createNotice() async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final body = TextEditingController();
    var audienceId = '';
    Property? selectedProperty;
    final allTenantsLabel = context.tr('All tenants');
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final propertiesValue = ref.watch(portfolioPropertiesProvider);
          final properties =
              propertiesValue.value
                  ?.where((property) => !property.isArchived)
                  .toList(growable: false) ??
              const <Property>[];
          final portfolioResolved = propertiesValue.hasValue;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text.localized('New tenant notice'),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: title,
                        decoration: InputDecoration(
                          labelText: context.tr('Title'),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 4
                            ? context.tr('Give the notice a clear title')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: body,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: context.tr('Notice text'),
                          alignLabelWithHint: true,
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 10
                            ? context.tr('Write the notice content')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      if (!portfolioResolved && propertiesValue.isLoading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                        Text.localized('Loading properties…'),
                      ] else if (!portfolioResolved &&
                          propertiesValue.hasError) ...[
                        Text.localized(
                          'Properties could not be loaded. Try again before queuing this notice.',
                          style: TextStyle(color: context.nyumba.danger),
                        ),
                        const SizedBox(height: 10),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: audienceId,
                        decoration: InputDecoration(
                          labelText: context.tr('Audience'),
                        ),
                        // Only this landlord's own properties can be addressed; a
                        // fixed list would offer estates they do not own.
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text.localized('All tenants'),
                          ),
                          for (final property in properties)
                            DropdownMenuItem(
                              value: property.id,
                              child: Text(property.name),
                            ),
                        ],
                        onChanged: !portfolioResolved
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    audienceId = value;
                                    selectedProperty = null;
                                    for (final property in properties) {
                                      if (property.id == value) {
                                        selectedProperty = property;
                                        break;
                                      }
                                    }
                                  });
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text.localized('Cancel'),
                ),
                FilledButton(
                  onPressed: !portfolioResolved
                      ? null
                      : () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(context, true);
                          }
                        },
                  child: const Text.localized('Queue notice'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (created == true) {
      try {
        await ref.read(createNoticeProvider)(
          CreateNoticeInput(
            landlordId: _landlordId,
            title: title.text.trim(),
            body: body.text.trim(),
            audience: selectedProperty?.name ?? allTenantsLabel,
            audienceType: selectedProperty == null
                ? NoticeAudienceType.allActiveTenants
                : NoticeAudienceType.property,
            audienceId: selectedProperty?.id,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text.localized(
                'Notice queued locally. It sends after the next sync.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('Could not queue the notice: $error')),
            ),
          );
        }
      }
    }
    title.dispose();
    body.dispose();
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.entry,
    required this.busy,
    required this.onPrint,
    required this.onShare,
  });

  final _DocumentListEntry entry;
  final bool busy;
  final Future<void> Function() onPrint;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: entry.iconTint
                  ? context.nyumba.sageTint
                  : context.nyumba.navyTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              entry.icon,
              color: entry.iconTint
                  ? context.nyumba.sageDark
                  : context.nyumba.midnightNavy,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!context.isCompact) ...[
            Expanded(
              child: StatusBadge(
                label: entry.statusLabel,
                tone: entry.statusTone,
              ),
            ),
            Expanded(
              child: Text(
                '${entry.issuedAt.toLocal().day}/'
                '${entry.issuedAt.toLocal().month}/'
                '${entry.issuedAt.toLocal().year}',
              ),
            ),
            SizedBox(
              width: 110,
              child: SyncStateBadge(status: entry.syncStatus),
            ),
          ],
          AsyncActionIconButton(
            busy: busy,
            tooltip: context.tr('Print ${entry.number}'),
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
          ),
          if (!context.isCompact)
            AsyncActionIconButton(
              // Print and share run through the same document service, so
              // whichever one is working locks the other out too.
              enabled: !busy,
              tooltip: context.tr('Share ${entry.number}'),
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
    );
  }
}
