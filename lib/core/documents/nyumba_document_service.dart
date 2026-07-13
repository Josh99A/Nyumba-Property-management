import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintableDocumentData {
  const PrintableDocumentData({
    required this.title,
    required this.number,
    required this.recipient,
    required this.property,
    required this.unit,
    required this.amountMinor,
    required this.date,
    required this.status,
  });

  final String title;
  final String number;
  final String recipient;
  final String property;
  final String unit;
  final int amountMinor;
  final DateTime date;
  final String status;
}

abstract interface class DocumentService {
  Future<Uint8List> generate(PrintableDocumentData data);
  Future<void> print(PrintableDocumentData data);
  Future<void> share(PrintableDocumentData data);
}

class PdfDocumentService implements DocumentService {
  const PdfDocumentService();

  @override
  Future<Uint8List> generate(PrintableDocumentData data) async {
    final document = pw.Document(
      title: '${data.title} ${data.number}',
      author: 'Nyumba Property Management',
      creator: 'Nyumba Property Management',
    );
    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load(
        'assets/branding/nyumba-horizontal.png',
      );
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } on Object {
      logo = null;
    }

    const navy = PdfColor.fromInt(0xFF123A6F);
    const sage = PdfColor.fromInt(0xFF5F8F6B);
    const gold = PdfColor.fromInt(0xFFC98B2E);
    const ivory = PdfColor.fromInt(0xFFF7F4ED);
    const ink = PdfColor.fromInt(0xFF17253A);
    const muted = PdfColor.fromInt(0xFF667085);
    final currency = NumberFormat.currency(
      locale: 'en_KE',
      symbol: 'KES ',
      decimalDigits: 0,
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Image(logo, width: 180, height: 60, fit: pw.BoxFit.contain)
                else
                  pw.Text(
                    'NYUMBA',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      data.title.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 21,
                        fontWeight: pw.FontWeight.bold,
                        color: navy,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      data.number,
                      style: const pw.TextStyle(color: muted),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Container(height: 4, color: navy),
            pw.SizedBox(height: 28),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _pdfLabelValue(
                    'Issued to',
                    data.recipient,
                    muted,
                    ink,
                  ),
                ),
                pw.Expanded(
                  child: _pdfLabelValue(
                    'Property',
                    '${data.property}\nUnit ${data.unit}',
                    muted,
                    ink,
                  ),
                ),
                pw.Expanded(
                  child: _pdfLabelValue(
                    'Date',
                    DateFormat('d MMMM y').format(data.date),
                    muted,
                    ink,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 34),
            pw.Container(
              padding: const pw.EdgeInsets.all(22),
              decoration: pw.BoxDecoration(
                color: ivory,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFE4E0D8),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        data.title == 'Receipt'
                            ? 'Payment received'
                            : 'Rent due',
                        style: const pw.TextStyle(fontSize: 11, color: muted),
                      ),
                      pw.SizedBox(height: 7),
                      pw.Text(
                        currency.format(data.amountMinor / 100),
                        style: pw.TextStyle(
                          fontSize: 27,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: pw.BoxDecoration(
                      color: data.status.toLowerCase() == 'paid'
                          ? const PdfColor.fromInt(0xFFEAF3EC)
                          : const PdfColor.fromInt(0xFFFFF3E2),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      data.status,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: data.status.toLowerCase() == 'paid'
                            ? sage
                            : gold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 26),
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(
                  color: PdfColor.fromInt(0xFFE4E0D8),
                ),
                bottom: const pw.BorderSide(
                  color: PdfColor.fromInt(0xFFE4E0D8),
                ),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: ivory),
                  children: [
                    _pdfCell('Description', bold: true),
                    _pdfCell('Billing period', bold: true),
                    _pdfCell('Amount', bold: true, alignRight: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _pdfCell('Monthly rent · Unit ${data.unit}'),
                    _pdfCell(DateFormat('MMMM y').format(data.date)),
                    _pdfCell(
                      currency.format(data.amountMinor / 100),
                      alignRight: true,
                    ),
                  ],
                ),
              ],
            ),
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 18),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColor.fromInt(0xFFE4E0D8)),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by Nyumba Property Management',
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                  pw.Text(
                    'Keep this document for your records.',
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  @override
  Future<void> print(PrintableDocumentData data) {
    return Printing.layoutPdf(
      name: '${data.title}-${data.number}.pdf',
      onLayout: (_) => generate(data),
    );
  }

  @override
  Future<void> share(PrintableDocumentData data) async {
    final bytes = await generate(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${data.title}-${data.number}.pdf',
    );
  }
}

pw.Widget _pdfLabelValue(
  String label,
  String value,
  PdfColor muted,
  PdfColor ink,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 10, color: muted)),
      pw.SizedBox(height: 5),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: ink,
          lineSpacing: 3,
        ),
      ),
    ],
  );
}

pw.Widget _pdfCell(String text, {bool bold = false, bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: pw.Align(
      alignment: alignRight
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ),
  );
}
