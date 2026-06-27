/// Build and save a PDF summary of selected receipts.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.

library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/receipt.dart';
import '../screens/receipt_select_sheet.dart';
import '../screens/receipts_pdf_preview.dart';
import '../utils/formatting.dart';

/// Runs the full "view selected receipts as PDF" flow: prompt for a selection,
/// build the PDF, then open the on-screen preview. [onMessage] reports status
/// (e.g. save result or errors) back for display. [onBusy] toggles a busy
/// indicator around the build step.
///
/// Returns nothing; all feedback is via the callbacks.

Future<void> viewReceiptsAsPdf(
  BuildContext context, {
  required List<Receipt> receipts,
  required void Function(String message, {bool isError}) onMessage,
  required void Function(bool busy) onBusy,
}) async {
  if (receipts.isEmpty) {
    onMessage('There are no receipts to view.', isError: true);
    return;
  }

  final chosen = await showModalBottomSheet<List<Receipt>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ReceiptSelectSheet(allReceipts: receipts),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;

  onBusy(true);
  try {
    final pdfBytes = await buildReceiptsPdf(
      receipts: chosen,
      title: 'Papertrail Receipts',
    );
    final t = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    final pdfName =
        'papertrail_receipts_${t.year}${p(t.month)}${p(t.day)}_'
        '${p(t.hour)}${p(t.minute)}.pdf';
    onBusy(false);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptsPdfPreview(
          pdfBytes: pdfBytes,
          pdfName: pdfName,
          onSaveResult: onMessage,
        ),
      ),
    );
  } catch (e) {
    onBusy(false);
    onMessage('Could not build PDF: $e', isError: true);
  }
}

/// Builds a PDF table summarising [receipts] under [title].

Future<Uint8List> buildReceiptsPdf({
  required List<Receipt> receipts,
  required String title,
}) async {
  final now = DateTime.now();
  final dateStr =
      '${now.day.toString().padLeft(2, '0')}/'
      '${now.month.toString().padLeft(2, '0')}/'
      '${now.year}';

  final base = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  final italic = await PdfGoogleFonts.notoSansItalic();
  final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    ),
  );

  // Per-currency totals for the summary line.
  final totals = <String, double>{};
  for (final r in receipts) {
    totals[r.currency] = (totals[r.currency] ?? 0) + r.amount;
  }
  final totalText = totals.entries
      .map((e) => formatMoney(e.value, e.key))
      .join('  ·  ');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Generated $dateStr  ·  '
            '${receipts.length} receipt${receipts.length == 1 ? '' : 's'}'
            '${totalText.isEmpty ? '' : '  ·  Total $totalText'}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.Divider(),
          pw.SizedBox(height: 4),
        ],
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerLeft,
            4: pw.Alignment.centerLeft,
          },
          headers: ['Date', 'Title', 'Amount', 'Vendor', 'Categories'],
          data: [
            for (final r in receipts)
              [
                formatDate(r.purchaseDate),
                r.title,
                formatMoney(r.amount, r.currency),
                r.vendor,
                r.categories.join(', '),
              ],
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

/// Prompt for a filename and location, then write the PDF [bytes] there.
///
/// Returns a status message: the saved path, null if cancelled, or an error
/// string prefixed with 'error:'. On web, falls back to the share sheet.

Future<String?> saveReceiptsPdfAs(List<int> bytes, String defaultName) async {
  try {
    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: defaultName,
      );
      return null;
    }
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (savePath == null) return null; // Cancelled.
    await File(savePath).writeAsBytes(bytes);
    return 'Saved to $savePath';
  } catch (e, st) {
    debugPrint('[Save PDF] error: $e\n$st');
    return 'error:Save failed: $e';
  }
}
