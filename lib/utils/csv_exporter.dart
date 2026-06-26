/// Exports a list of receipts to a UTF-8 CSV file on disk.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Anushka Vidanage

// Add the library directive as we have doc entries above. We publish the above
// meta doc lines in the docs.

library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/receipt.dart';

const _headers = [
  'Date',
  'Title',
  'Amount',
  'Currency',
  'Vendor',
  'Categories',
  'Flags',
  'Description',
  'Has Warranty',
  'Warranty Expiry',
  'Has Attachment',
  'Extra Files Count',
];

/// Wraps [s] in double-quotes and escapes internal quotes if the field
/// contains a comma, double-quote, or newline — standard RFC 4180.
String _escape(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _buildCsv(List<Receipt> receipts) {
  final buf = StringBuffer();
  buf.writeln(_headers.map(_escape).join(','));
  for (final r in receipts) {
    final row = [
      r.purchaseDate.toIso8601String().substring(0, 10),
      r.title,
      r.amount.toStringAsFixed(2),
      r.currency,
      r.vendor,
      r.categories.join('; '),
      r.flags.join('; '),
      r.description,
      r.hasWarranty ? 'Yes' : 'No',
      r.warrantyExpiry?.toIso8601String().substring(0, 10) ?? '',
      r.hasAttachment ? 'Yes' : 'No',
      r.extraAttachments.length.toString(),
    ];
    buf.writeln(row.map(_escape).join(','));
  }
  return buf.toString();
}

/// Resolves the directory to write the export file into.
///
/// Desktop (Windows / macOS / Linux): the user's Downloads folder.
/// Mobile (Android / iOS): the app's documents directory.
Future<Directory> _exportDirectory() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir;
  }
  return getApplicationDocumentsDirectory();
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// Writes [receipts] to a CSV file and returns the path of the saved file.
///
/// The file is UTF-8 with BOM so Excel opens it correctly on Windows without
/// requiring an import wizard.
Future<String> exportReceiptsToCsv(List<Receipt> receipts) async {
  final csv = _buildCsv(receipts);
  final dir = await _exportDirectory();
  final now = DateTime.now();
  final stamp =
      '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
  final file = File('${dir.path}/papertrail_$stamp.csv');
  // UTF-8 BOM prefix so Excel on Windows recognises the encoding automatically.
  await file.writeAsBytes([
    0xEF, 0xBB, 0xBF, // BOM
    ...utf8.encode(csv),
  ]);
  return file.path;
}
