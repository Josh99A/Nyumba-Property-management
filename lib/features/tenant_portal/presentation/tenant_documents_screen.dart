import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/tenant_components.dart';

class TenantDocumentsScreen extends StatefulWidget {
  const TenantDocumentsScreen({super.key});

  @override
  State<TenantDocumentsScreen> createState() => _TenantDocumentsScreenState();
}

class _TenantDocumentsScreenState extends State<TenantDocumentsScreen> {
  final List<_TenantDocument> _documents = [..._seedDocuments];
  String _query = '';
  String _category = 'All';
  bool _favoritesOnly = false;

  List<_TenantDocument> get _filteredDocuments {
    final query = _query.trim().toLowerCase();
    return _documents.where((document) {
      final matchesQuery =
          query.isEmpty ||
          document.title.toLowerCase().contains(query) ||
          document.reference.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'All' || document.category == _category;
      final matchesFavorite = !_favoritesOnly || document.favorite;
      return matchesQuery && matchesCategory && matchesFavorite;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDocuments;
    final offlineCount = _documents
        .where((document) => document.offline)
        .length;
    return TenantPage(
      title: 'Documents',
      description: 'View, print, and keep important tenancy records together.',
      secondaryAction: OutlinedButton.icon(
        onPressed: () => showTenantMessage(
          context,
          '$offlineCount documents are stored for offline access.',
        ),
        icon: const Icon(Icons.offline_pin_outlined),
        label: const Text('Offline files'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _requestDocument,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Request document'),
      ),
      children: [
        TenantMetricGrid(
          children: [
            TenantMetricCard(
              label: 'Shared documents',
              value: '${_documents.length}',
              caption: 'From your landlord and property manager',
              icon: Icons.folder_copy_outlined,
              color: NyumbaColors.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Available offline',
              value: '$offlineCount',
              caption: 'Ready without a network connection',
              icon: Icons.offline_pin_outlined,
              color: NyumbaColors.sageDark,
            ),
            TenantMetricCard(
              label: 'Receipts',
              value:
                  '${_documents.where((item) => item.category == 'Receipts').length}',
              caption: 'Payment records for 2026',
              icon: Icons.receipt_long_outlined,
              color: NyumbaColors.terracottaDark,
            ),
            TenantMetricCard(
              label: 'Action required',
              value:
                  '${_documents.where((item) => item.status == 'Signature needed').length}',
              caption: 'Documents waiting for you',
              icon: Icons.draw_outlined,
              color: NyumbaColors.danger,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PinnedLeaseCard(
          document: _documents.first,
          onOpen: () => _showDocument(_documents.first),
        ),
        const SizedBox(height: 20),
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
                      decoration: const InputDecoration(
                        hintText: 'Search documents or references',
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
                    'Reports',
                  ])
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  FilterChip(
                    avatar: const Icon(Icons.star_outline_rounded, size: 18),
                    label: const Text('Starred'),
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
              child: Text(
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
                child: const Text('Clear filters'),
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
    final index = _documents.indexOf(document);
    if (index < 0) return;
    setState(() {
      _documents[index] = document.copyWith(favorite: !document.favorite);
    });
    showTenantMessage(
      context,
      document.favorite
          ? '${document.title} removed from starred documents.'
          : '${document.title} added to starred documents.',
    );
  }

  void _toggleOffline(_TenantDocument document) {
    final index = _documents.indexOf(document);
    if (index < 0) return;
    setState(() {
      _documents[index] = document.copyWith(offline: !document.offline);
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
          title: const Text('Request a document'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
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
                        label: Text(item),
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
                  decoration: const InputDecoration(
                    labelText: 'Note for your property manager (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.offline_pin_outlined,
                      color: NyumbaColors.sageDark,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
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
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (requested != true || !mounted) return;
    setState(() {
      _documents.insert(
        0,
        _TenantDocument(
          title: '$type request',
          reference: 'DOC-REQ-${_documents.length + 108}',
          category: 'Reports',
          date: 'Requested just now',
          size: 'Pending',
          status: 'Requested',
          format: 'REQUEST',
          offline: true,
          favorite: false,
          description:
              'Your property manager will prepare this document and share it here.',
        ),
      );
      _category = 'All';
    });
    showTenantMessage(context, '$type request saved and queued to sync.');
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
                padding: const EdgeInsets.fromLTRB(20, 17, 12, 14),
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
                          Text(
                            document.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${document.reference} • ${document.date}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
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
                      onPressed: () => showTenantMessage(
                        dialogContext,
                        '${document.title} saved for offline access.',
                      ),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                    ),
                    const SizedBox(width: 9),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showTenantMessage(
                          context,
                          '${document.title} is ready to print.',
                        );
                      },
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print'),
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
                    Text(
                      'Current tenancy agreement',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: .75),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Acacia Heights • Unit A-12',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1 Jan – 31 Dec 2026 • Signed by both parties',
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
            label: const Text('Open lease'),
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
                  const Tooltip(
                    message: 'Available offline',
                    child: Icon(
                      Icons.offline_pin_rounded,
                      size: 20,
                      color: NyumbaColors.sageDark,
                    ),
                  ),
                IconButton(
                  tooltip: document.favorite ? 'Remove star' : 'Star document',
                  onPressed: onFavorite,
                  icon: Icon(
                    document.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: document.favorite
                        ? NyumbaColors.terracottaGold
                        : NyumbaColors.mutedInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              document.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
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
            const Spacer(),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '${document.format} • ${document.size}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Document actions',
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
                      child: Text('Open document'),
                    ),
                    PopupMenuItem(
                      value: 'offline',
                      child: Text(
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
        color: Colors.white,
        border: Border.all(color: NyumbaColors.outline),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x12123A6F), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.home_work_rounded,
                color: NyumbaColors.midnightNavy,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'NYUMBA PROPERTY MANAGEMENT',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NyumbaColors.midnightNavy,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            document.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            document.reference,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          Text(document.description),
          const SizedBox(height: 18),
          const TenantInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Tenant',
            value: 'Brian Otieno',
          ),
          const SizedBox(height: 12),
          const TenantInfoRow(
            icon: Icons.home_outlined,
            label: 'Property',
            value: 'Acacia Heights • Unit A-12',
          ),
          const SizedBox(height: 12),
          TenantInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Document date',
            value: document.date,
          ),
          const SizedBox(height: 26),
          Container(height: 1, color: NyumbaColors.outline),
          const SizedBox(height: 13),
          Text(
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
  });

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

  _TenantDocument copyWith({bool? offline, bool? favorite}) {
    return _TenantDocument(
      title: title,
      reference: reference,
      category: category,
      date: date,
      size: size,
      status: status,
      format: format,
      offline: offline ?? this.offline,
      favorite: favorite ?? this.favorite,
      description: description,
    );
  }
}

const _seedDocuments = [
  _TenantDocument(
    title: 'Signed tenancy agreement',
    reference: 'LEASE-A12-2026',
    category: 'Lease',
    date: '1 Jan 2026',
    size: '1.8 MB',
    status: 'Ready',
    format: 'PDF',
    offline: true,
    favorite: true,
    description:
        'Signed tenancy agreement for Acacia Heights, Unit A-12, covering '
        'the period from 1 January to 31 December 2026.',
  ),
  _TenantDocument(
    title: 'Move-in inspection report',
    reference: 'INS-A12-010126',
    category: 'Reports',
    date: '1 Jan 2026',
    size: '860 KB',
    status: 'Ready',
    format: 'PDF',
    offline: true,
    favorite: false,
    description:
        'Condition report completed at handover, including room notes, '
        'meter readings, and the agreed photographic record.',
  ),
  _TenantDocument(
    title: 'July rent receipt',
    reference: 'NYB-RCP-00842',
    category: 'Receipts',
    date: '3 Jul 2026',
    size: '184 KB',
    status: 'Ready',
    format: 'PDF',
    offline: true,
    favorite: true,
    description:
        'Official receipt for KES 45,000 received via M-PESA for July 2026 rent.',
  ),
  _TenantDocument(
    title: 'June rent receipt',
    reference: 'NYB-RCP-00791',
    category: 'Receipts',
    date: '4 Jun 2026',
    size: '182 KB',
    status: 'Ready',
    format: 'PDF',
    offline: true,
    favorite: false,
    description:
        'Official receipt for KES 45,000 received via M-PESA for June 2026 rent.',
  ),
  _TenantDocument(
    title: 'Water interruption notice',
    reference: 'NOTICE-AC-0713',
    category: 'Notices',
    date: '13 Jul 2026',
    size: '220 KB',
    status: 'Ready',
    format: 'PDF',
    offline: false,
    favorite: false,
    description:
        'Notice of a planned water interruption on 15 July from 09:00 to '
        '14:00 while the property water tanks are cleaned.',
  ),
  _TenantDocument(
    title: 'House rules acknowledgement',
    reference: 'RULES-A12-2026',
    category: 'Lease',
    date: '10 Jul 2026',
    size: '320 KB',
    status: 'Signature needed',
    format: 'PDF',
    offline: true,
    favorite: false,
    description:
        'Updated property guidelines for visitors, quiet hours, shared '
        'facilities, waste collection, and security access.',
  ),
  _TenantDocument(
    title: '2026 rent statement',
    reference: 'STMT-A12-2026',
    category: 'Reports',
    date: '13 Jul 2026',
    size: '410 KB',
    status: 'Ready',
    format: 'PDF',
    offline: false,
    favorite: false,
    description:
        'Running statement of monthly rent invoices, payments, credits, and '
        'confirmed balances for the 2026 tenancy year.',
  ),
];
