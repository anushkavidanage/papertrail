/// On-screen PDF preview for selected receipts, with save and print.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.

library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:printing/printing.dart';

import '../services/receipts_pdf.dart';

// ignore_for_file: use_build_context_synchronously

/// Shows [pdfBytes] in an on-screen preview. Sharing is replaced with an
/// explicit Save action that prompts for a filename; printing stays available.
///
/// [onSaveResult] reports the save outcome message back to the caller so it
/// can show a banner.

class ReceiptsPdfPreview extends StatelessWidget {
  const ReceiptsPdfPreview({
    super.key,
    required this.pdfBytes,
    required this.pdfName,
    required this.onSaveResult,
  });

  final Uint8List pdfBytes;
  final String pdfName;
  final void Function(String message, {bool isError}) onSaveResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipts PDF')),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        pdfFileName: pdfName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowSharing: false,
        actions: [
          PdfPreviewAction(
            icon: const Icon(Icons.save_alt),
            onPressed: (ctx, build, pageFormat) async {
              final bytes = await build(pageFormat);
              final msg = await saveReceiptsPdfAs(bytes, pdfName);
              if (msg == null) return;
              if (msg.startsWith('error:')) {
                onSaveResult(msg.substring(6), isError: true);
              } else {
                onSaveResult(msg);
              }
            },
          ),
        ],
      ),
    );
  }
}
