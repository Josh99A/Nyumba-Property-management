import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../app/localization/locale_controller.dart';
import '../../../core/documents/nyumba_document_service.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../documents/application/document_providers.dart';
import '../../documents/domain/lease_document.dart';
import '../../finance/application/billing_providers.dart';
import '../../finance/domain/rent_payment.dart';
import '../../tenants/application/tenancy_providers.dart';
import 'widgets/tenant_components.dart';

class TenantDocumentsScreen extends ConsumerStatefulWidget {
  const TenantDocumentsScreen({
    super.key,
    this.documentService = const PdfDocumentService(),
  });

  final DocumentService documentService;

  @override
  ConsumerState<TenantDocumentsScreen> createState() =>
      _TenantDocumentsScreenState();
}

class _TenantDocumentsScreenState extends ConsumerState<TenantDocumentsScreen> {
  /// Locally raised document requests, newest first. These are view records
  /// until a document-request aggregate exists server-side.
  final List<_TenantDocument> _localRequests = [];

  /// Per-user view preferences keyed by document reference.
  final Map<String, bool> _favoriteOverrides = {};
  final Map<String, bool> _offlineOverrides = {};

  String _query = '';
  String _category = 'All';
  bool _favoritesOnly = false;

  String get _tenantId => ref.read(sessionControllerProvider)?.userId ?? '';

  _TenantDocument _applyOverrides(_TenantDocument document) {
    return document.copyWith(
      favorite: _favoriteOverrides[document.overrideKey],
      offline: _offlineOverrides[document.overrideKey],
    );
  }

  _TenantDocument _fromLeaseDocument(LeaseDocument document) {
    final category = switch (document.type) {
      LeaseDocumentType.lease => 'Lease',
      LeaseDocumentType.receipt => 'Receipts',
      LeaseDocumentType.notice => 'Notices',
      LeaseDocumentType.invoice => 'Statements',
    };
    return _applyOverrides(
      _TenantDocument(
        title: document.type == LeaseDocumentType.lease
            ? 'Signed tenancy agreement'
            : '${document.type.label} ${document.number}',
        reference: document.number,
        category: category,
        date: DateFormat('d MMM y').format(document.issuedAt.toLocal()),
        size: '—',
        status: document.statusLabel == 'Signed'
            ? 'Ready'
            : document.statusLabel,
        format: 'PDF',
        offline: true,
        favorite: document.type == LeaseDocumentType.lease,
        description:
            '${document.type.label} for ${document.unitLabel}, '
            '${document.propertyName}.',
        recipient: document.recipient,
        propertyName: document.propertyName,
        unitLabel: document.unitLabel,
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
      ),
    );
  }

  _TenantDocument _fromPayment(RentPayment payment) {
    // A receipt exists only once the server issued its number. Until then this
    // row is a record of what the landlord entered, not proof of a receipt, and
    // must not claim to be an official one.
    final issued = payment.hasIssuedReceipt;
    final reference = payment.receiptNumber ?? 'Not yet issued';
    return _applyOverrides(
      _TenantDocument(
        title: 'Rent receipt — ${payment.period}',
        reference: reference,
        // Unissued payments share the placeholder reference, so view
        // preferences key on the payment itself.
        keyOverride: payment.id,
        category: 'Receipts',
        date: DateFormat('d MMM y').format(payment.paidOn.toLocal()),
        size: '—',
        status: issued ? 'Ready' : 'Awaiting confirmation',
        format: 'PDF',
        offline: true,
        favorite: false,
        description: issued
            ? 'Official receipt for '
                  '${formatTenantUgx(payment.amountMinor ~/ 100)} received via '
                  '${payment.method} for ${payment.period} rent.'
            : '${formatTenantUgx(payment.amountMinor ~/ 100)} recorded via '
                  '${payment.method} for ${payment.period} rent. The official '
                  'receipt is issued once this payment is confirmed.',
        recipient: payment.tenantName,
        propertyName: payment.propertyName,
        unitLabel: payment.unitLabel,
        // No printable artifact until the server issues the receipt: printing
        // an unconfirmed payment would hand a tenant an official-looking
        // document asserting something the server has not agreed to.
        printable: issued
            ? PrintableDocumentData(
                language: ref.read(localePreferenceProvider),
                title: 'Receipt',
                number: reference,
                recipient: payment.tenantName,
                property: payment.propertyName,
                unit: payment.unitLabel,
                amountMinor: payment.amountMinor,
                date: payment.paidOn,
                status: 'Received',
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leaseDocuments =
        ref.watch(tenantLeaseDocumentsProvider(_tenantId)).value ??
        const <LeaseDocument>[];
    final tenancy = ref.watch(myTenancyProvider(_tenantId)).value;
    final payments = tenancy == null
        ? const <RentPayment>[]
        : ref.watch(tenancyPaymentsProvider(tenancy.id)).value ??
              const <RentPayment>[];
    final documents = <_TenantDocument>[
      ..._localRequests.map(_applyOverrides),
      ...leaseDocuments.map(_fromLeaseDocument),
      ...payments.map(_fromPayment),
    ];

    final query = _query.trim().toLowerCase();
    final filtered = documents.where((document) {
      final matchesQuery =
          query.isEmpty ||
          document.title.toLowerCase().contains(query) ||
          document.reference.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'All' || document.category == _category;
      final matchesFavorite = !_favoritesOnly || document.favorite;
      return matchesQuery && matchesCategory && matchesFavorite;
    }).toList();
    final offlineCount = documents.where((document) => document.offline).length;
    // Only a real lease document may occupy the pinned lease hero. Falling
    // back to an arbitrary first document rendered, say, a clearance-letter
    // request under an "Open lease" button.
    final pinnableLeases = documents.where(
      (document) => document.category == 'Lease',
    );
    final pinned = pinnableLeases.isEmpty ? null : pinnableLeases.first;
    return TenantPage(
      title: 'Documents',
      description: 'View, print, and keep important tenancy records together.',
      secondaryAction: OutlinedButton.icon(
        onPressed: () => showTenantMessage(
          context,
          '$offlineCount documents are stored for offline access.',
        ),
        icon: const Icon(Icons.offline_pin_outlined),
        label: const Text.localized('Offline files'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _requestDocument,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text.localized('Request document'),
      ),
      children: [
        TenantMetricGrid(
          children: [
            TenantMetricCard(
              label: 'Shared documents',
              value: '${documents.length}',
              caption: 'From your landlord and property manager',
              icon: Icons.folder_copy_outlined,
              color: context.nyumba.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Available offline',
              value: '$offlineCount',
              caption: 'Ready without a network connection',
              icon: Icons.offline_pin_outlined,
              color: context.nyumba.sageDark,
            ),
            TenantMetricCard(
              label: 'Receipts',
              value:
                  '${documents.where((item) => item.category == 'Receipts').length}',
              caption: 'Payment records for ${DateTime.now().year}',
              icon: Icons.receipt_long_outlined,
              color: context.nyumba.terracottaDark,
            ),
            TenantMetricCard(
              label: 'Action required',
              value:
                  '${documents.where((item) => item.status == 'Signature needed').length}',
              caption: 'Documents waiting for you',
              icon: Icons.draw_outlined,
              color: context.nyumba.danger,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (pinned != null) ...[
          _PinnedLeaseCard(
            document: pinned,
            onOpen: () => _showDocument(pinned),
          ),
          const SizedBox(height: 20),
        ],
        NyumbaSurface(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 640
                        ? constraints.maxWidth
                        : 320,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: context.tr('Search documents or references'),
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  for (final category in const [
                    'All',
                    'Lease',
                    'Receipts',
                    'Notices',
                    'Statements',
                    'Reports',
                  ])
                    ChoiceChip(
                      label: Text.localized(category),
                      selected: _category == category,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  FilterChip(
                    avatar: const Icon(Icons.star_outline_rounded, size: 18),
                    label: const Text.localized('Starred'),
                    selected: _favoritesOnly,
                    onSelected: (value) =>
                        setState(() => _favoritesOnly = value),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text.localized(
                '${filtered.length} document${filtered.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const StatusBadge(
              label: 'Private to your tenancy',
              tone: BadgeTone.info,
              icon: Icons.lock_outline_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          NyumbaSurface(
            child: TenantEmptyState(
              title: 'No documents match',
              message: 'Try another search, category, or starred filter.',
              icon: Icons.folder_off_outlined,
              action: OutlinedButton(
                onPressed: _clearFilters,
                child: const Text.localized('Clear filters'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              const spacing = 14.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final document in filtered)
                    SizedBox(
                      width: width,
                      child: _DocumentCard(
                        document: document,
                        onOpen: () => _showDocument(document),
                        onFavorite: () => _toggleFavorite(document),
                        onOffline: () => _toggleOffline(document),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _category = 'All';
      _favoritesOnly = false;
    });
  }

  void _toggleFavorite(_TenantDocument document) {
    setState(() {
      _favoriteOverrides[document.overrideKey] = !document.favorite;
    });
    showTenantMessage(
      context,
      document.favorite
          ? '${document.title} removed from starred documents.'
          : '${document.title} added to starred documents.',
    );
  }

  void _toggleOffline(_TenantDocument document) {
    setState(() {
      _offlineOverrides[document.overrideKey] = !document.offline;
    });
    showTenantMessage(
      context,
      document.offline
          ? '${document.title} will use online access only.'
          : '${document.title} saved for offline access.',
    );
  }

  Future<void> _requestDocument() async {
    final noteController = TextEditingController();
    var type = 'Rent clearance letter';
    final requested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Request a document'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.localized(
                  'Document type',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in const [
                      'Rent clearance letter',
                      'Payment statement',
                      'Lease copy',
                      'Other',
                    ])
                      ChoiceChip(
                        label: Text.localized(item),
                        selected: type == item,
                        showCheckmark: false,
                        onSelected: (_) => setDialogState(() => type = item),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'Note for your property manager (optional)',
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.offline_pin_outlined,
                      color: context.nyumba.sageDark,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text.localized(
                        'The request saves locally and will send to your '
                        'property manager when connected.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text.localized('Send request'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (requested != true || !mounted) return;
    setState(() {
      _localRequests.insert(
        0,
        _TenantDocument(
          title: '$type request',
          reference: 'DOC-REQ-${_localRequests.length + 108}',
          category: 'Reports',
          date: 'Requested just now',
          size: 'Pending',
          status: 'Requested',
          format: 'REQUEST',
          offline: true,
          favorite: false,
          description:
              'Your property manager will prepare this document and share it here.',
          recipient: 'Current tenant',
          propertyName: 'Current tenancy',
          unitLabel: '—',
        ),
      );
      _category = 'All';
    });
    showTenantMessage(context, '$type request saved on this device.');
  }

  Future<void> _showDocument(_TenantDocument document) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 17, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _documentColor(
                          document.category,
                        ).withValues(alpha: .11),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        _documentIcon(document.category),
                        color: _documentColor(document.category),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.localized(
                            document.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text.localized(
                            '${document.reference} • ${document.date}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Close'),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: document.format == 'REQUEST'
                      ? _RequestPreview(document: document)
                      : _DocumentPreview(document: document),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: document.printable == null
                          ? null
                          : () => _shareDocument(document),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text.localized('Download / share'),
                    ),
                    const SizedBox(width: 9),
                    FilledButton.icon(
                      onPressed: document.printable == null
                          ? null
                          : () => _printDocument(document),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text.localized('Print'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareDocument(_TenantDocument document) async {
    try {
      await widget.documentService.share(document.printable!);
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not share the document: $error');
      }
    }
  }

  Future<void> _printDocument(_TenantDocument document) async {
    try {
      await widget.documentService.print(document.printable!);
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not print the document: $error');
      }
    }
  }
}

class _PinnedLeaseCard extends StatelessWidget {
  const _PinnedLeaseCard({required this.document, required this.onOpen});

  final _TenantDocument document;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Brand-fixed navy: the card keeps white foregrounds in both themes,
        // so the theme-aware palette (light blue in dark mode) cannot be used.
        gradient: const LinearGradient(
          colors: [NyumbaColors.navyDark, NyumbaColors.midnightNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.localized(
                      document.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: .75),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.localized(
                      '${document.propertyName} • ${document.unitLabel}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text.localized(
                      '${document.date} • ${document.status}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: NyumbaColors.terracottaGold,
              foregroundColor: Colors.white,
            ),
            onPressed: onOpen,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text.localized('Open lease'),
          );
          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 18), action],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onOpen,
    required this.onFavorite,
    required this.onOffline,
  });

  final _TenantDocument document;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onOffline;

  @override
  Widget build(BuildContext context) {
    final color = _documentColor(document.category);
    return NyumbaSurface(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 215),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_documentIcon(document.category), color: color),
                ),
                const Spacer(),
                if (document.offline)
                  Tooltip(
                    message: 'Available offline',
                    child: Icon(
                      Icons.offline_pin_rounded,
                      size: 20,
                      color: context.nyumba.sageDark,
                    ),
                  ),
                IconButton(
                  tooltip: context.tr(
                    document.favorite ? 'Remove star' : 'Star document',
                  ),
                  onPressed: onFavorite,
                  icon: Icon(
                    document.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: document.favorite
                        ? context.nyumba.terracottaGold
                        : context.nyumba.mutedInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text.localized(
              document.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text.localized(
              '${document.reference} • ${document.date}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                StatusBadge(label: document.category, tone: BadgeTone.info),
                if (document.status != 'Ready')
                  TenantStatusBadge(status: document.status),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text.localized(
                  '${document.format} • ${document.size}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: context.tr('Document actions'),
                  onSelected: (value) {
                    if (value == 'offline') {
                      onOffline();
                    } else {
                      onOpen();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Text.localized('Open document'),
                    ),
                    PopupMenuItem(
                      value: 'offline',
                      child: Text.localized(
                        document.offline
                            ? 'Remove offline copy'
                            : 'Make available offline',
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.document});

  final _TenantDocument document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: Border.all(color: context.nyumba.outline),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x12123A6F), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.home_work_rounded,
                color: context.nyumba.midnightNavy,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.localized(
                  'NYUMBA PROPERTY MANAGEMENT',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.nyumba.midnightNavy,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text.localized(
            document.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text.localized(
            document.reference,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          Text.localized(document.description),
          const SizedBox(height: 18),
          TenantInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Tenant',
            value: document.recipient,
          ),
          const SizedBox(height: 12),
          TenantInfoRow(
            icon: Icons.home_outlined,
            label: 'Property',
            value: '${document.propertyName} · ${document.unitLabel}',
          ),
          const SizedBox(height: 12),
          TenantInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Document date',
            value: document.date,
          ),
          const SizedBox(height: 26),
          Container(height: 1, color: context.nyumba.outline),
          const SizedBox(height: 13),
          Text.localized(
            'Verified digital copy • ${document.reference}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RequestPreview extends StatelessWidget {
  const _RequestPreview({required this.document});

  final _TenantDocument document;

  @override
  Widget build(BuildContext context) {
    return TenantEmptyState(
      title: 'Document request sent',
      message: document.description,
      icon: Icons.mark_email_read_outlined,
      action: const TenantStatusBadge(status: 'Pending'),
    );
  }
}

Color _documentColor(String category) => switch (category) {
  'Lease' => NyumbaColors.midnightNavy,
  'Receipts' => NyumbaColors.sageDark,
  'Notices' => NyumbaColors.terracottaDark,
  _ => NyumbaColors.navyDark,
};

IconData _documentIcon(String category) => switch (category) {
  'Lease' => Icons.description_outlined,
  'Receipts' => Icons.receipt_long_outlined,
  'Notices' => Icons.campaign_outlined,
  _ => Icons.assessment_outlined,
};

class _TenantDocument {
  const _TenantDocument({
    required this.title,
    required this.reference,
    required this.category,
    required this.date,
    required this.size,
    required this.status,
    required this.format,
    required this.offline,
    required this.favorite,
    required this.description,
    required this.recipient,
    required this.propertyName,
    required this.unitLabel,
    this.printable,
    this.keyOverride,
  });

  /// Stable identity for per-user view preferences when the displayed
  /// reference is not unique (unissued receipts share a placeholder).
  final String? keyOverride;

  String get overrideKey => keyOverride ?? reference;

  final String title;
  final String reference;
  final String category;
  final String date;
  final String size;
  final String status;
  final String format;
  final bool offline;
  final bool favorite;
  final String description;
  final String recipient;
  final String propertyName;
  final String unitLabel;
  final PrintableDocumentData? printable;

  _TenantDocument copyWith({bool? offline, bool? favorite}) {
    return _TenantDocument(
      title: title,
      reference: reference,
      keyOverride: keyOverride,
      category: category,
      date: date,
      size: size,
      status: status,
      format: format,
      offline: offline ?? this.offline,
      favorite: favorite ?? this.favorite,
      description: description,
      recipient: recipient,
      propertyName: propertyName,
      unitLabel: unitLabel,
      printable: printable,
    );
  }
}
