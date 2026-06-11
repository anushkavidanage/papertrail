/// Home tab: a quick overview plus the most recently dated receipts.
library;

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../widgets/locked_backdrop.dart';
import '../widgets/receipt_card.dart';
import 'receipt_detail_screen.dart';

class RecentReceiptsView extends StatelessWidget {
  const RecentReceiptsView({super.key});

  Future<void> _refresh(BuildContext context) =>
      ReceiptStore.instance.refresh(context, const LockedBackdrop());

  void _open(BuildContext context, Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receiptId: receipt.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ReceiptStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.status == StoreStatus.loading && !store.loadedOnce) {
          return const Center(child: CircularProgressIndicator());
        }
        if (store.status == StoreStatus.error && !store.loadedOnce) {
          return _ErrorState(
            message: store.error ?? 'Something went wrong.',
            onRetry: () => _refresh(context),
          );
        }

        final recent = store.recent;
        return RefreshIndicator(
          onRefresh: () => _refresh(context),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OverviewHeader(
                count: store.receipts.length,
                total: store.totalAmount,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Recent receipts',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (store.status == StoreStatus.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const _EmptyState()
              else
                ...recent.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ReceiptCard(
                      receipt: r,
                      onTap: () => _open(context, r),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Receipts',
                value: '$count',
                color: scheme.onPrimaryContainer,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _Stat(
                label: 'Tracked total',
                value: total.toStringAsFixed(2),
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.receipt_long,
              size: 72, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          const Text('No receipts yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Tap "Add receipt" to record your first purchase.\n'
            'Everything is stored privately in your own Solid Pod.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
