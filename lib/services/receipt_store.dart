/// In-memory cache and coordinator for the user's receipts.
///
/// A single [ReceiptStore] instance is shared across the app. Screens listen to
/// it (via [ListenableBuilder]) and call [refresh], [save] and [delete], which
/// proxy to [PodService] and then notify listeners.
library;

import 'package:flutter/widgets.dart';

import '../models/receipt.dart';
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

  double get totalAmount =>
      _receipts.fold(0.0, (sum, r) => sum + r.amount);

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
  }) async {
    await _pod.saveReceipt(
      receipt,
      attachmentPath: attachmentPath,
      removeAttachment: removeAttachment,
    );
    _receipts.removeWhere((r) => r.id == receipt.id);
    _receipts.add(receipt);
    _receipts.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    _status = StoreStatus.ready;
    notifyListeners();
  }

  /// Delete [receipt] from the Pod and the in-memory list.
  Future<void> delete(Receipt receipt) async {
    await _pod.deleteReceipt(receipt);
    _receipts.removeWhere((r) => r.id == receipt.id);
    notifyListeners();
  }
}
