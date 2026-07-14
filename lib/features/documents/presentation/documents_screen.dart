import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/documents/nyumba_document_service.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/coming_soon.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../notices/application/notice_providers.dart';
import '../../notices/domain/notice.dart';
import '../application/document_providers.dart';
import '../domain/lease_document.dart';

const _demoLandlordId = 'demo-landlord-001';

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

  @override
  Widget build(BuildContext context) {
    final documentsValue = ref.watch(leaseDocumentsProvider);
    final notices = ref.watch(noticesProvider).value ?? const <Notice>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
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
                primaryAction: FilledButton.icon(
                  onPressed: () => _createDocument(context),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Create document'),
                ),
              ),
              const SizedBox(height: 24),
              documentsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load documents: $error'),
                  ),
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
          statusTone: document.statusLabel == 'Paid'
              ? BadgeTone.success
              : BadgeTone.warning,
          issuedAt: document.issuedAt,
          printable: PrintableDocumentData(
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
            entityType: OfflineEntityType.document,
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
                    label: Text(filter),
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
              child: Center(child: Text('No documents in this category yet.')),
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
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  Future<void> _share(_DocumentListEntry entry) async {
    setState(() => _busyDocument = entry.number);
    try {
      await widget.documentService.share(entry.printable);
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  void _createDocument(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create document',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const ComingSoon(
                message: 'Recurring invoices coming soon',
                child: ListTile(
                  enabled: false,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(Icons.receipt_long_outlined),
                  ),
                  title: Text('Rent invoice (coming soon)'),
                ),
              ),
              const ComingSoon(
                message: 'Lease templates coming soon',
                child: ListTile(
                  enabled: false,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(Icons.handshake_outlined)),
                  title: Text('Lease agreement (coming soon)'),
                ),
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
                title: const Text('Tenant notice'),
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

  Future<void> _createNotice() async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final body = TextEditingController();
    var audience = 'All tenants';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New tenant notice'),
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
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) => (value?.trim().length ?? 0) < 4
                        ? 'Give the notice a clear title'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: body,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Notice text',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 10
                        ? 'Write the notice content'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: audience,
                    decoration: const InputDecoration(labelText: 'Audience'),
                    items: const [
                      DropdownMenuItem(
                        value: 'All tenants',
                        child: Text('All tenants'),
                      ),
                      DropdownMenuItem(
                        value: 'Sunset Apartments',
                        child: Text('Sunset Apartments'),
                      ),
                      DropdownMenuItem(
                        value: 'Riverside Heights',
                        child: Text('Riverside Heights'),
                      ),
                      DropdownMenuItem(
                        value: 'Nyumbani Gardens',
                        child: Text('Nyumbani Gardens'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => audience = value);
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Queue notice'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      try {
        await ref.read(createNoticeProvider)(
          CreateNoticeInput(
            landlordId: _demoLandlordId,
            title: title.text.trim(),
            body: body.text.trim(),
            audience: audience,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notice queued locally. It sends after the next sync.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not queue the notice: $error')),
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
  final VoidCallback onPrint;
  final VoidCallback onShare;

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
                Text(entry.title, style: Theme.of(context).textTheme.titleSmall),
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
            SizedBox(width: 110, child: SyncStateBadge(status: entry.syncStatus)),
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Print ${entry.number}',
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined),
            ),
            if (!context.isCompact)
              IconButton(
                tooltip: 'Share ${entry.number}',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_outlined),
              ),
          ],
        ],
      ),
    );
  }
}
