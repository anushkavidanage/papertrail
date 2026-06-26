/// In-memory cache and coordinator for the user's receipts.
///
/// A single [ReceiptStore] instance is shared across the app. Screens listen to
/// it (via [ListenableBuilder]) and call [refresh], [save] and [delete], which
/// proxy to [PodService] and then notify listeners.
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

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/receipt.dart';
import 'notification_service.dart';
import 'pod_service.dart';

enum StoreStatus { idle, loading, ready, error }

class ReceiptStore extends ChangeNotifier {
  ReceiptStore._();
  static final ReceiptStore instance = ReceiptStore._();

  final PodService _pod = PodService.instance;

  List<Receipt> _receipts = [];
  StoreStatus _status = StoreStatus.idle;
  String? _error;
  bool _loadedOnce = false;

  List<Receipt> get receipts => List.unmodifiable(_receipts);
  StoreStatus get status => _status;
  String? get error => _error;
  bool get loadedOnce => _loadedOnce;

  /// Receipts ordered newest purchase first (the list is already sorted).
  List<Receipt> get recent => receipts.take(10).toList();

  /// Every distinct category currently in use, sorted alphabetically.
  List<String> get usedCategories {
    final set = <String>{};
    for (final r in _receipts) {
      set.addAll(r.categories);
    }
    final list = set.toList()..sort();
    return list;
  }

  double get totalAmount => _receipts.fold(0.0, (sum, r) => sum + r.amount);

  Receipt? byId(String id) {
    for (final r in _receipts) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// (Re)load all receipts from the Pod. [backdrop] is shown behind the
  /// security-key prompt if it appears.
  Future<void> refresh(BuildContext context, Widget backdrop) async {
    _status = StoreStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final ready = await _pod.ensureReady(context, backdrop);
      if (!ready) {
        _status = StoreStatus.error;
        _error = 'Unlock your Pod with your security key to view receipts.';
        notifyListeners();
        return;
      }
      _receipts = await _pod.loadReceipts();
      _loadedOnce = true;
      _status = StoreStatus.ready;
    } catch (e) {
      _status = StoreStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  /// Persist [receipt] to the Pod and update the in-memory list.
  Future<void> save(
    Receipt receipt, {
    String? attachmentPath,
    bool removeAttachment = false,
    Map<String, String> extraAttachmentPaths = const {},
    List<String> extraAttachmentIdsToDelete = const [],
  }) async {
    await _pod.saveReceipt(
      receipt,
      attachmentPath: attachmentPath,
      removeAttachment: removeAttachment,
      extraAttachmentPaths: extraAttachmentPaths,
      extraAttachmentIdsToDelete: extraAttachmentIdsToDelete,
    );
    _receipts.removeWhere((r) => r.id == receipt.id);
    _receipts.add(receipt);
    _receipts.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    _status = StoreStatus.ready;
    notifyListeners();
    // Fire-and-forget: reschedule (or cancel) the warranty reminder.
    unawaited(NotificationService.instance.scheduleWarrantyReminder(receipt));
  }

  /// Delete [receipt] from the Pod and the in-memory list.
  Future<void> delete(Receipt receipt) async {
    await _pod.deleteReceipt(receipt);
    _receipts.removeWhere((r) => r.id == receipt.id);
    notifyListeners();
    unawaited(NotificationService.instance.cancelWarrantyReminder(receipt.id));
  }

  /// Delete multiple receipts from the Pod and the in-memory list.
  Future<void> deleteMany(Iterable<Receipt> receipts) async {
    final ids = receipts.map((r) => r.id).toList();
    for (final r in receipts) {
      await _pod.deleteReceipt(r);
      _receipts.removeWhere((x) => x.id == r.id);
    }
    notifyListeners();
    for (final id in ids) {
      unawaited(NotificationService.instance.cancelWarrantyReminder(id));
    }
  }
}
