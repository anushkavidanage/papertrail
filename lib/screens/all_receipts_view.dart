/// Receipts tab: searchable, filterable list of every stored receipt.
library;

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../widgets/locked_backdrop.dart';
import '../widgets/receipt_card.dart';
import 'receipt_detail_screen.dart';

class AllReceiptsView extends StatefulWidget {
  const AllReceiptsView({super.key});

  @override
  State<AllReceiptsView> createState() => _AllReceiptsViewState();
}

class _AllReceiptsViewState extends State<AllReceiptsView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _categoryFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      ReceiptStore.instance.refresh(context, const LockedBackdrop());

  List<Receipt> _apply(List<Receipt> all) {
    final q = _query.trim().toLowerCase();
    return all.where((r) {
      if (_categoryFilter != null && !r.categories.contains(_categoryFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.vendor.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q) ||
          r.categories.any((c) => c.toLowerCase().contains(q)) ||
          r.flags.any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  void _open(Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ReceiptDetailScreen(receiptId: receipt.id)),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                              () => _categoryFilter = sel ? c : null),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ReceiptCard(
                            receipt: filtered[i],
                            onTap: () => _open(filtered[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
