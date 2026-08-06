/// Backup and restore service for receipts and their attachments.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Graham Williams

library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/receipt.dart';
import 'pod_service.dart';

/// Result of a restore operation.

class RestoreResult {
  int receiptsRestored = 0;
  int attachmentsRestored = 0;
  int attachmentsFailed = 0;
  final List<String> errors = [];

  bool get hasErrors => errors.isNotEmpty;
}

/// Progress callback: (current, total, message).

typedef BackupProgress = void Function(int current, int total, String message);

/// Zero-padded timestamp string for filenames: YYYYMMDD_HHMM.

String _ts(DateTime t) =>
    '${t.year}'
    '${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}'
    '_${t.hour.toString().padLeft(2, '0')}'
    '${t.minute.toString().padLeft(2, '0')}';

/// Service for exporting and importing a full papertrail backup ZIP.
///
/// ZIP structure:
/// ```
/// receipts.json                       (list of all receipt records)
/// attachments/<receiptId>.<ext>       (primary attachment per receipt)
/// attachments/<receiptId>_e<id>.<ext> (extra attachments)
/// ```
///
/// Importing the ZIP into an empty Pod recreates every receipt and its
/// attachments exactly as they were when the backup was made.

class BackupService {
  BackupService._();

  // ── Export ───────────────────────────────────────────────────────────────

  /// Exports all receipts and their attachments to a single ZIP file.
  ///
  /// Returns true on success, false if the user cancelled the save dialog.
  static Future<bool> exportBackup(
    List<Receipt> receipts, {
    BackupProgress? onProgress,
  }) async {
    final archive = Archive();

    // ── 1. Receipts JSON ──────────────────────────────────────────────
    onProgress?.call(0, 1, 'Exporting receipts…');
    final receiptsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(receipts.map((r) => r.toJson()).toList());
    final jsonBytes = Uint8List.fromList(utf8.encode(receiptsJson));
    archive.addFile(ArchiveFile('receipts.json', jsonBytes.length, jsonBytes));

    // ── 2. Attachments ────────────────────────────────────────────────
    final total = receipts.length;
    for (var i = 0; i < receipts.length; i++) {
      final receipt = receipts[i];
      onProgress?.call(
        i + 1,
        total,
        'Exporting attachments ${i + 1}/$total: ${receipt.title}',
      );

      // Primary attachment.
      if (receipt.hasAttachment) {
        try {
          final bytes = await PodService.instance.readAttachmentBytes(
            receipt.id,
          );
          final zipPath =
              'attachments/${receipt.id}.${receipt.attachmentExtension}';
          archive.addFile(ArchiveFile(zipPath, bytes.length, bytes));
        } catch (e) {
          debugPrint('BackupService: primary attachment ${receipt.id}: $e');
        }
      }

      // Extra attachments.
      for (final extra in receipt.extraAttachments) {
        try {
          final bytes = await PodService.instance.readExtraAttachmentBytes(
            receipt.id,
            extra.id,
          );
          final zipPath =
              'attachments/${receipt.id}_e${extra.id}.${extra.extension}';
          archive.addFile(ArchiveFile(zipPath, bytes.length, bytes));
        } catch (e) {
          debugPrint(
            'BackupService: extra attachment ${receipt.id}/${extra.id}: $e',
          );
        }
      }
    }

    // ── 3. Save ZIP ───────────────────────────────────────────────────
    onProgress?.call(0, 1, 'Choosing save location…');
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final filename = 'papertrail_backup_${_ts(DateTime.now())}.zip';
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save Backup',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: zipBytes,
    );
    if (savePath == null) return false; // User cancelled.

    // On desktop, saveFile returns a path but does not write the bytes,
    // so write them ourselves. On mobile, bytes are written by the picker.
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(savePath).writeAsBytes(zipBytes);
    }
    return true;
  }

  // ── Import ─────────────────────────────────────────────────────────────

  /// Imports a backup ZIP, recreating every receipt and attachment on the Pod.
  static Future<RestoreResult> importBackup({
    BackupProgress? onProgress,
  }) async {
    final result = RestoreResult();

    // ── 1. Pick the ZIP ───────────────────────────────────────────────
    onProgress?.call(0, 1, 'Choosing backup file…');
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select Backup',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      result.errors.add('No file selected.');
      return result;
    }

    final fileBytes = picked.files.first.bytes;
    if (fileBytes == null) {
      result.errors.add('Could not read the selected file.');
      return result;
    }

    // ── 2. Decode the ZIP ─────────────────────────────────────────────
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(fileBytes);
    } catch (e) {
      result.errors.add('Not a valid ZIP archive: $e');
      return result;
    }

    // ── 3. Parse receipts.json ────────────────────────────────────────
    ArchiveFile? jsonFile;
    for (final f in archive.files) {
      if (f.name == 'receipts.json') {
        jsonFile = f;
        break;
      }
    }
    if (jsonFile == null) {
      result.errors.add('Backup is missing receipts.json.');
      return result;
    }

    late final List<dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(jsonFile.content as List<int>))
              as List<dynamic>;
    } catch (e) {
      result.errors.add('receipts.json is corrupt: $e');
      return result;
    }

    // Build a lookup of attachment files in the ZIP by their stem.
    final attachmentFiles = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.name.startsWith('attachments/') && f.isFile) {
        final base = f.name.substring('attachments/'.length);
        final stem = base.contains('.')
            ? base.substring(0, base.lastIndexOf('.'))
            : base;
        attachmentFiles[stem] = f;
      }
    }

    // ── 4. Recreate each receipt ──────────────────────────────────────
    final tmpDir = await getTemporaryDirectory();
    final total = decoded.length;
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      if (entry is! Map<String, dynamic>) continue;

      late final Receipt receipt;
      try {
        receipt = Receipt.fromJson(entry);
      } catch (e) {
        result.errors.add('Skipping malformed receipt entry: $e');
        continue;
      }

      onProgress?.call(
        i + 1,
        total,
        'Restoring ${i + 1}/$total: ${receipt.title}',
      );

      // Write primary attachment bytes to a temp file for upload.
      String? primaryPath;
      if (receipt.hasAttachment) {
        final f = attachmentFiles[receipt.id];
        if (f != null) {
          primaryPath = await _writeTemp(
            tmpDir,
            '${receipt.id}.${receipt.attachmentExtension}',
            f.content as List<int>,
          );
        }
      }

      // Write extra attachment bytes to temp files.
      final extraPaths = <String, String>{};
      for (final extra in receipt.extraAttachments) {
        final f = attachmentFiles['${receipt.id}_e${extra.id}'];
        if (f != null) {
          extraPaths[extra.id] = await _writeTemp(
            tmpDir,
            '${receipt.id}_e${extra.id}.${extra.extension}',
            f.content as List<int>,
          );
        }
      }

      try {
        await PodService.instance.saveReceipt(
          receipt,
          attachmentPath: primaryPath,
          extraAttachmentPaths: extraPaths,
        );
        result.receiptsRestored++;
        if (primaryPath != null) result.attachmentsRestored++;
        result.attachmentsRestored += extraPaths.length;
      } catch (e) {
        result.errors.add('Failed to restore "${receipt.title}": $e');
        result.attachmentsFailed++;
      }
    }

    return result;
  }

  /// Writes [bytes] to a temp file named [name] under [dir], returning its path.
  static Future<String> _writeTemp(
    Directory dir,
    String name,
    List<int> bytes,
  ) async {
    final file = File('${dir.path}/papertrail_restore_$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
