/// Receipts tab: searchable, filterable, sortable list of every stored receipt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../utils/csv_exporter.dart';
import '../utils/formatting.dart';
import '../widgets/locked_backdrop.dart';
import '../widgets/receipt_card.dart';
import 'receipt_detail_screen.dart';

enum _SortOption {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  String get label => switch (this) {
    dateDesc => 'Date (newest first)',
    dateAsc => 'Date (oldest first)',
    amountDesc => 'Amount (highest first)',
    amountAsc => 'Amount (lowest first)',
  };

  IconData get icon => switch (this) {
    dateDesc || dateAsc => Icons.calendar_today_outlined,
    amountDesc || amountAsc => Icons.attach_money_outlined,
  };
}

class AllReceiptsView extends StatefulWidget {
  const AllReceiptsView({super.key});

  @override
  State<AllReceiptsView> createState() => _AllReceiptsViewState();
}

class _AllReceiptsViewState extends State<AllReceiptsView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minCtrl = TextEditingController();
  final TextEditingController _maxCtrl = TextEditingController();

  String _query = '';
  String? _categoryFilter;
  _SortOption _sort = _SortOption.dateDesc;
  double? _minAmount;
  double? _maxAmount;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _exporting = false;

  // Bulk-selection state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _deletingMany = false;

  bool get _hasActiveFilter =>
      _query.trim().isNotEmpty ||
      _categoryFilter != null ||
      _minAmount != null ||
      _maxAmount != null ||
      _fromDate != null ||
      _toDate != null;

  @override
  void dispose() {
    _searchController.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      ReceiptStore.instance.refresh(context, const LockedBackdrop());

  List<Receipt> _apply(List<Receipt> all) {
    final q = _query.trim().toLowerCase();
    var result = all.where((r) {
      if (_categoryFilter != null && !r.categories.contains(_categoryFilter)) {
        return false;
      }
      if (_minAmount != null && r.amount < _minAmount!) return false;
      if (_maxAmount != null && r.amount > _maxAmount!) return false;
      if (_fromDate != null && r.purchaseDate.isBefore(_fromDate!))
        return false;
      if (_toDate != null && r.purchaseDate.isAfter(_toDateInclusive))
        return false;
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.vendor.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q) ||
          r.categories.any((c) => c.toLowerCase().contains(q)) ||
          r.flags.any((f) => f.toLowerCase().contains(q));
    }).toList();

    switch (_sort) {
      case _SortOption.dateDesc:
        result.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      case _SortOption.dateAsc:
        result.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
      case _SortOption.amountDesc:
        result.sort((a, b) => b.amount.compareTo(a.amount));
      case _SortOption.amountAsc:
        result.sort((a, b) => a.amount.compareTo(b.amount));
    }

    return result;
  }

  /// Returns a formatted total for [receipts], grouped by currency.
  /// Single currency → "AUD 1,234.56". Multiple → "AUD 500.00 + USD 200.00".
  String _filteredTotal(List<Receipt> receipts) {
    final totals = <String, double>{};
    for (final r in receipts) {
      totals[r.currency] = (totals[r.currency] ?? 0) + r.amount;
    }
    return totals.entries.map((e) => formatMoney(e.value, e.key)).join(' + ');
  }

  void _open(Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailScreen(receiptId: receipt.id),
      ),
    );
  }

  Future<void> _exportCsv(List<Receipt> receipts) async {
    setState(() => _exporting = true);
    try {
      final path = await exportReceiptsToCsv(receipts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: $path'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll(List<Receipt> receipts) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(receipts.map((r) => r.id));
    });
  }

  Future<void> _deleteSelected() async {
    final store = ReceiptStore.instance;
    final toDelete = store.receipts
        .where((r) => _selectedIds.contains(r.id))
        .toList();
    final count = toDelete.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receipts'),
        content: Text(
          'Permanently delete $count receipt${count == 1 ? '' : 's'}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingMany = true);
    try {
      await store.deleteMany(toDelete);
      if (!mounted) return;
      _exitSelectionMode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _deletingMany = false);
    }
  }

  Widget _selectionBar(BuildContext context, List<Receipt> filtered) {
    final count = _selectedIds.length;
    final allSelected =
        filtered.isNotEmpty && _selectedIds.length == filtered.length;
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Exit selection',
              onPressed: _exitSelectionMode,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$count selected',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: filtered.isEmpty
                  ? null
                  : allSelected
                  ? () => setState(() => _selectedIds.clear())
                  : () => _selectAll(filtered),
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
            _deletingMany
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: count == 0
                        ? 'Select receipts to delete'
                        : 'Delete $count receipt${count == 1 ? '' : 's'}',
                    onPressed: count == 0 ? null : _deleteSelected,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _sortButton(BuildContext context) {
    final active = _sort != _SortOption.dateDesc;
    return PopupMenuButton<_SortOption>(
      icon: Icon(
        Icons.swap_vert,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: 'Sort',
      onSelected: (opt) => setState(() => _sort = opt),
      itemBuilder: (_) => _SortOption.values
          .map(
            (opt) => PopupMenuItem<_SortOption>(
              value: opt,
              child: Row(
                children: [
                  Icon(opt.icon, size: 18),
                  const SizedBox(width: 10),
                  Text(opt.label),
                  if (_sort == opt) ...[
                    const Spacer(),
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _amountRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _minCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Min amount',
                border: const OutlineInputBorder(),
                isDense: true,
                // contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                suffixIcon: _minAmount != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _minCtrl.clear();
                          setState(() => _minAmount = null);
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _minAmount = double.tryParse(v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('–', style: theme.textTheme.bodyLarge),
          ),
          Expanded(
            child: TextField(
              controller: _maxCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Max amount',
                border: const OutlineInputBorder(),
                isDense: true,
                // contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                suffixIcon: _maxAmount != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _maxCtrl.clear();
                          setState(() => _maxAmount = null);
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _maxAmount = double.tryParse(v)),
            ),
          ),
        ],
      ),
    );
  }

  /// End-of-day boundary so the "to" date filter is inclusive.
  DateTime get _toDateInclusive => _toDate != null
      ? DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59)
      : DateTime(9999);

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? _toDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: _toDate ?? DateTime(2100),
      helpText: 'From date',
    );
    if (picked != null) setState(() => _fromDate = picked);
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? DateTime.now(),
      firstDate: _fromDate ?? DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'To date',
    );
    if (picked != null) setState(() => _toDate = picked);
  }

  Widget _dateRangeRow(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget datePill({
      required String label,
      required DateTime? value,
      required VoidCallback onTap,
      required VoidCallback? onClear,
    }) {
      final hasValue = value != null;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
              // contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              suffixIcon: hasValue
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      padding: EdgeInsets.zero,
                      onPressed: onClear,
                    )
                  : const Icon(Icons.calendar_today_outlined, size: 16),
            ),
            child: Text(
              hasValue ? formatDate(value) : '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasValue ? null : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          datePill(
            label: 'From date',
            value: _fromDate,
            onTap: _pickFromDate,
            onClear: () => setState(() => _fromDate = null),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('–', style: theme.textTheme.bodyLarge),
          ),
          datePill(
            label: 'To date',
            value: _toDate,
            onTap: _pickToDate,
            onClear: () => setState(() => _toDate = null),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ReceiptStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final categories = store.usedCategories;
        final filtered = _apply(store.receipts);

        return Column(
          children: [
            // Selection bar (replaces search/filter UI while in selection mode)
            if (_selectionMode)
              _selectionBar(context, filtered)
            else ...[
              // Search + sort + export row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Search receipts',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                        ),
                      ),
                    ),
                    _sortButton(context),
                    _exporting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download_outlined),
                            tooltip: filtered.isEmpty
                                ? 'No receipts to export'
                                : 'Export ${filtered.length} receipt${filtered.length == 1 ? '' : 's'} to CSV',
                            onPressed: filtered.isEmpty
                                ? null
                                : () => _exportCsv(filtered),
                          ),
                  ],
                ),
              ),
              // Amount range filter row
              _amountRow(context),
              // Date range filter row
              _dateRangeRow(context),
              // Category filter chips
              if (categories.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _categoryFilter == null,
                          onSelected: (_) =>
                              setState(() => _categoryFilter = null),
                        ),
                      ),
                      ...categories.map(
                        (c) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(c),
                            selected: _categoryFilter == c,
                            onSelected: (sel) => setState(
                              () => _categoryFilter = sel ? c : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Result count summary when any filter is active
              if (_hasActiveFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      filtered.isEmpty
                          ? 'No receipts match your filters.'
                          : '${filtered.length} receipt${filtered.length == 1 ? '' : 's'} · Total: ${_filteredTotal(filtered)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
            // Receipts list
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: filtered.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Text(
                              store.receipts.isEmpty
                                  ? 'No receipts yet.'
                                  : 'No receipts match your filters.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final receipt = filtered[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ReceiptCard(
                              receipt: receipt,
                              isSelected: _selectionMode
                                  ? _selectedIds.contains(receipt.id)
                                  : null,
                              onTap: _selectionMode
                                  ? () => _toggleSelection(receipt.id)
                                  : () => _open(receipt),
                              onLongPress: _selectionMode
                                  ? null
                                  : () => _enterSelectionMode(receipt.id),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
