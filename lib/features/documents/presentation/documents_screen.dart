import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/documents/nyumba_document_service.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';

class _DocumentRecord {
  const _DocumentRecord({
    required this.type,
    required this.number,
    required this.recipient,
    required this.property,
    required this.unit,
    required this.amountMinor,
    required this.date,
    required this.status,
  });

  final String type;
  final String number;
  final String recipient;
  final String property;
  final String unit;
  final int amountMinor;
  final DateTime date;
  final String status;

  PrintableDocumentData get printable => PrintableDocumentData(
    title: type,
    number: number,
    recipient: recipient,
    property: property,
    unit: unit,
    amountMinor: amountMinor,
    date: date,
    status: status,
  );
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    this.documentService = const PdfDocumentService(),
  });

  final DocumentService documentService;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _filter = 'All';
  String? _busyDocument;
  final _documents = [
    _DocumentRecord(
      type: 'Receipt',
      number: 'RCT-2026-0184',
      recipient: 'Brian Okello',
      property: 'Sunset Apartments',
      unit: 'B4',
      amountMinor: 120000000,
      date: DateTime(2026, 7, 12),
      status: 'Paid',
    ),
    _DocumentRecord(
      type: 'Invoice',
      number: 'INV-2026-0226',
      recipient: 'Peter Ssemwanga',
      property: 'Greenview Court',
      unit: 'A1',
      amountMinor: 110000000,
      date: DateTime(2026, 7, 1),
      status: 'Due',
    ),
    _DocumentRecord(
      type: 'Receipt',
      number: 'RCT-2026-0183',
      recipient: 'Grace Namuli',
      property: 'Riverside Heights',
      unit: 'D1',
      amountMinor: 140000000,
      date: DateTime(2026, 7, 11),
      status: 'Paid',
    ),
    _DocumentRecord(
      type: 'Invoice',
      number: 'INV-2026-0225',
      recipient: 'Mary Nansubuga',
      property: 'Nyumbani Gardens',
      unit: 'C2',
      amountMinor: 130000000,
      date: DateTime(2026, 7, 1),
      status: 'Part paid',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final documents = _documents.where((document) {
      return _filter == 'All' || document.type == _filter;
    }).toList();
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
              NyumbaSurface(
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
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    if (documents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text('No documents in this category yet.'),
                        ),
                      )
                    else
                      for (final document in documents)
                        _DocumentRow(
                          document: document,
                          busy: _busyDocument == document.number,
                          onPrint: () => _print(document),
                          onShare: () => _share(document),
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

  Future<void> _print(_DocumentRecord document) async {
    setState(() => _busyDocument = document.number);
    try {
      await widget.documentService.print(document.printable);
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  Future<void> _share(_DocumentRecord document) async {
    setState(() => _busyDocument = document.number);
    try {
      await widget.documentService.share(document.printable);
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
              for (final item in const [
                (Icons.receipt_long_outlined, 'Rent invoice'),
                (Icons.handshake_outlined, 'Lease agreement'),
                (Icons.campaign_outlined, 'Tenant notice'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: context.nyumba.navyTint,
                    child: Icon(item.$1, color: context.nyumba.midnightNavy),
                  ),
                  title: Text(item.$2),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('${item.$2} draft created locally.'),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.busy,
    required this.onPrint,
    required this.onShare,
  });

  final _DocumentRecord document;
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
              color: document.type == 'Receipt'
                  ? context.nyumba.sageTint
                  : context.nyumba.navyTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              document.type == 'Receipt'
                  ? Icons.receipt_outlined
                  : Icons.description_outlined,
              color: document.type == 'Receipt'
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
                  '${document.type} · ${document.number}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${document.recipient} · ${document.unit} ${document.property}',
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
                label: document.status,
                tone: document.status == 'Paid'
                    ? BadgeTone.success
                    : BadgeTone.warning,
              ),
            ),
            Expanded(
              child: Text(
                '${document.date.day}/${document.date.month}/${document.date.year}',
              ),
            ),
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
              tooltip: 'Print ${document.number}',
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined),
            ),
            if (!context.isCompact)
              IconButton(
                tooltip: 'Share ${document.number}',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_outlined),
              ),
          ],
        ],
      ),
    );
  }
}
