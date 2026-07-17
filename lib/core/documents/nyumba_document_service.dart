import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../localization/app_language.dart';
import '../localization/app_localizations_adapter.dart';
import '../localization/generated/app_localizations.dart';
import '../localization/localization_formats.dart';

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
    this.language = AppLanguage.english,
  });

  final String title;
  final String number;
  final String recipient;
  final String property;
  final String unit;
  final int amountMinor;
  final DateTime date;
  final String status;
  final AppLanguage language;
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
    await initializeNyumbaLocalizationFormats();
    final copy = _PdfCopy(data.language);
    final localizedTitle = copy.translateAppCopy(data.title);
    final localizedStatus = copy.translateAppCopy(data.status);
    final isRtl = data.language == AppLanguage.arabic;

    final notoSansData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final notoArabicData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Variable.ttf',
    );
    final notoSans = pw.Font.ttf(notoSansData);
    final notoArabic = pw.Font.ttf(notoArabicData);
    final primaryFont = isRtl ? notoArabic : notoSans;
    final fallbackFont = isRtl ? notoSans : notoArabic;
    final document = pw.Document(
      title: '$localizedTitle ${data.number}',
      author: 'Nyumba Property Management',
      creator: 'Nyumba Property Management',
      theme: pw.ThemeData.withFont(
        base: primaryFont,
        bold: primaryFont,
        fontFallback: [fallbackFont],
      ),
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
    final numberLocale = data.language == AppLanguage.luganda
        ? 'en_UG'
        : data.language.intlLocale;
    final currency = NumberFormat.currency(
      locale: numberLocale,
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    final isReceipt = data.title.toLowerCase().contains('receipt');
    final isPaid = const {
      'paid',
      'received',
    }.contains(data.status.toLowerCase());

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
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
                      localizedTitle.toUpperCase(),
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
                    copy.issuedTo,
                    data.recipient,
                    muted,
                    ink,
                  ),
                ),
                pw.Expanded(
                  child: _pdfLabelValue(
                    copy.property,
                    '${data.property}\n${data.unit}',
                    muted,
                    ink,
                  ),
                ),
                pw.Expanded(
                  child: _pdfLabelValue(
                    copy.date,
                    DateFormat(
                      'd MMMM y',
                      data.language.intlLocale,
                    ).format(data.date),
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
                        isReceipt ? copy.paymentReceived : copy.rentDue,
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
                      color: isPaid
                          ? const PdfColor.fromInt(0xFFEAF3EC)
                          : const PdfColor.fromInt(0xFFFFF3E2),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      localizedStatus,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: isPaid ? sage : gold,
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
                    _pdfCell(copy.description, bold: true),
                    _pdfCell(copy.billingPeriod, bold: true),
                    _pdfCell(copy.amount, bold: true, alignEnd: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _pdfCell('${copy.monthlyRent} - ${data.unit}'),
                    _pdfCell(
                      DateFormat(
                        'MMMM y',
                        data.language.intlLocale,
                      ).format(data.date),
                    ),
                    _pdfCell(
                      currency.format(data.amountMinor / 100),
                      alignEnd: true,
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
                    copy.generatedBy,
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                  pw.Text(
                    copy.keepForRecords,
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

pw.Widget _pdfCell(String text, {bool bold = false, bool alignEnd = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: pw.Align(
      alignment: alignEnd
          ? pw.AlignmentDirectional.centerEnd
          : pw.AlignmentDirectional.centerStart,
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

final class _PdfCopy {
  _PdfCopy(AppLanguage language) : _copy = appLocalizationsFor(language);

  final AppLocalizations _copy;

  String get issuedTo => _copy.pdfIssuedTo;
  String get property => _copy.pdfProperty;
  String get date => _copy.pdfDate;
  String get paymentReceived => _copy.pdfPaymentReceived;
  String get rentDue => _copy.pdfRentDue;
  String get description => _copy.pdfDescription;
  String get billingPeriod => _copy.pdfBillingPeriod;
  String get amount => _copy.pdfAmount;
  String get monthlyRent => _copy.pdfMonthlyRent;
  String get generatedBy => _copy.pdfGeneratedBy;
  String get keepForRecords => _copy.pdfKeepForRecords;

  String translateAppCopy(String source) {
    final exact = switch (source) {
      'Receipt' => _copy.pdfReceipt,
      'Invoice' => _copy.pdfInvoice,
      'Lease' => _copy.pdfLease,
      'Notice' => _copy.pdfNotice,
      'Rent statement' => _copy.pdfRentStatement,
      'Payment record' => _copy.pdfPaymentRecord,
      'Tenant notice' => _copy.pdfTenantNotice,
      'Not yet issued' => _copy.pdfNotYetIssued,
      'Paid' => _copy.pdfPaid,
      'Due' => _copy.pdfDue,
      'Received' => _copy.pdfReceived,
      'Signed' => _copy.pdfSigned,
      'Draft' => _copy.pdfDraft,
      'Queued to send' => _copy.pdfQueuedToSend,
      'Awaiting confirmation' => _copy.pdfAwaitingConfirmation,
      _ => null,
    };
    if (exact != null) return exact;
    const noticePrefix = 'Tenant notice';
    if (source.startsWith(noticePrefix)) {
      return source.replaceFirst(noticePrefix, _copy.pdfTenantNotice);
    }
    final count = RegExp(r'^(\d+) recorded payments?$').firstMatch(source);
    if (count != null) {
      return _copy.pdfRecordedPayments(int.parse(count.group(1)!));
    }
    return source;
  }
}
