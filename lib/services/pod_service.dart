/// Thin wrapper around the `solidpod` API for Papertrail's storage needs.
///
/// Responsibilities:
///   * ensure the user is logged in and the security key is available,
///   * read / write / delete encrypted receipt Turtle files,
///   * upload / download / delete encrypted attachment blobs (photos, PDFs).
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:solidpod/solidpod.dart';
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import '../constants/app_config.dart';
import '../models/receipt.dart';
import 'receipt_serializer.dart';

/// Raised when a Pod operation is attempted while the user is not logged in.
class NotReadyException implements Exception {
  NotReadyException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PodService {
  PodService._();
  static final PodService instance = PodService._();

  /// Relative-to-data path of a receipt file.
  String _receiptPath(String id) => '$receiptsDir/$id.ttl';

  /// Relative-to-data path (no extension) of an attachment blob.
  String _attachmentPath(String id) => '$attachmentsDir/$id';

  /// Whether a Solid session is currently active.
  Future<bool> get isLoggedIn => isUserLoggedIn();

  /// The current user's WebID, or null when not logged in.
  Future<String?> get webId => getWebId();

  /// Ensure we are logged in and the encryption key is loaded.
  ///
  /// Returns true when the Pod is ready for encrypted reads/writes. [backdrop]
  /// is shown behind the security-key prompt if one is required.
  Future<bool> ensureReady(BuildContext context, Widget backdrop) async {
    if (!await isUserLoggedIn()) return false;
    if (!context.mounted) return false;
    await getKeyFromUserIfRequired(context, backdrop);
    return KeyManager.hasSecurityKey();
  }

  /// Best-effort creation of a container, ignoring "already exists" errors.
  Future<void> _ensureContainer(String relativeToRoot) async {
    try {
      var url = await getDirUrl(relativeToRoot);
      if (!url.endsWith('/')) url = '$url/';
      await createDir(url);
    } catch (_) {
      // The container most likely already exists; nothing to do.
    }
  }

  /// Load every receipt stored on the Pod, newest purchase first.
  ///
  /// Returns an empty list when the receipts container does not yet exist
  /// (e.g. the very first run before anything has been saved).
  Future<List<Receipt>> loadReceipts() async {
    if (!await isUserLoggedIn()) {
      throw NotReadyException('Please log in to your Pod first.');
    }

    final dataDir = await getDataDirPath();
    final containerUrl = await getDirUrl('$dataDir/$receiptsDir');

    List<String> fileNames;
    try {
      final contents = await getResourcesInContainer(containerUrl);
      fileNames = contents.files;
    } catch (_) {
      // Container not created yet -> no receipts.
      return [];
    }

    final receipts = <Receipt>[];
    for (final name in fileNames) {
      if (!name.endsWith('.ttl') || name.contains('.acl')) continue;
      try {
        final turtle = await readPod(_receiptPath(_stripTtl(name)));
        receipts.add(ReceiptSerializer.fromTurtle(turtle));
      } catch (e) {
        // Skip files that are not valid Papertrail receipts.
        debugPrint('Skipping unreadable receipt "$name": $e');
      }
    }

    receipts.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return receipts;
  }

  String _stripTtl(String name) =>
      name.endsWith('.ttl') ? name.substring(0, name.length - 4) : name;

  /// Save (create or update) a receipt.
  ///
  /// When [attachmentPath] is provided the file at that path is uploaded as the
  /// receipt's attachment (replacing any previous one). When [removeAttachment]
  /// is true and no new file is supplied, the existing attachment is deleted.
  Future<void> saveReceipt(
    Receipt receipt, {
    String? attachmentPath,
    bool removeAttachment = false,
  }) async {
    if (!await isUserLoggedIn()) {
      throw NotReadyException('Please log in to your Pod first.');
    }

    await _ensureContainer('${await getDataDirPath()}/$receiptsDir');

    if (attachmentPath != null) {
      await _ensureContainer('${await getDataDirPath()}/$attachmentsDir');
      // Remove any previous attachment so the new blob can be written fresh.
      await _deleteAttachmentSilently(receipt.id);
      await writeLargeFile(
        localFilePath: attachmentPath,
        remoteFilePath: _attachmentPath(receipt.id),
        encrypted: true,
      );
    } else if (removeAttachment) {
      await _deleteAttachmentSilently(receipt.id);
    }

    final turtle = ReceiptSerializer.toTurtle(receipt);
    await writePod(
      _receiptPath(receipt.id),
      turtle,
      encrypted: true,
      overwrite: true,
    );
  }

  /// Download the raw bytes of a receipt's attachment.
  Future<Uint8List> readAttachmentBytes(String id) {
    return readLargeFileAsBytes(remoteFilePath: _attachmentPath(id));
  }

  /// Permanently delete a receipt and its attachment (if any).
  Future<void> deleteReceipt(Receipt receipt) async {
    if (!await isUserLoggedIn()) {
      throw NotReadyException('Please log in to your Pod first.');
    }

    if (receipt.hasAttachment) {
      await _deleteAttachmentSilently(receipt.id);
    }

    final dataDir = await getDataDirPath();
    final fileUrl = await getFileUrl('$dataDir/${_receiptPath(receipt.id)}');
    await deleteFile(fileUrl: fileUrl);
  }

  Future<void> _deleteAttachmentSilently(String id) async {
    try {
      await deleteLargeFile(remoteFilePath: _attachmentPath(id));
    } catch (_) {
      // No existing attachment, or already removed.
    }
  }
}
