/// Home tab: a quick overview plus the most recently dated receipts.
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

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../widgets/locked_backdrop.dart';
import '../widgets/receipt_card.dart';
import 'receipt_detail_screen.dart';

class RecentReceiptsView extends StatelessWidget {
  const RecentReceiptsView({super.key});

  Future<void> _refresh(BuildContext context) =>
      ReceiptStore.instance.refresh(context, const LockedBackdrop());

  void _open(BuildContext context, Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailScreen(receiptId: receipt.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ReceiptStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.status == StoreStatus.loading && store.receipts.isEmpty) {
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
            // Bottom padding keeps the last card clear of the FAB.
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _OverviewHeader(receipts: store.receipts),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text(
                    'Recent receipts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
  const _OverviewHeader({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final colors = PapertrailColors.of(context);
    final text = Theme.of(context).textTheme;
    final onHero = colors.onHero;

    final total = receipts.fold(0.0, (sum, r) => sum + r.amount);
    final now = DateTime.now();
    final thisMonth = receipts
        .where(
          (r) =>
              r.purchaseDate.year == now.year &&
              r.purchaseDate.month == now.month,
        )
        .fold(0.0, (sum, r) => sum + r.amount);
    final activeWarranties = receipts
        .where((r) => r.hasWarranty && !r.isWarrantyExpired)
        .length;

    // Only label the totals with a currency when every receipt shares one;
    // summing mixed currencies into one labelled figure would mislead.
    final currencies = receipts.map((r) => r.currency).toSet();
    String money(double v) => currencies.length == 1
        ? formatMoney(v, currencies.single)
        : v.toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.heroGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.heroGradient.last.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: onHero,
              ),
              const SizedBox(width: 8),
              Text(
                'Tracked total',
                style: text.labelLarge?.copyWith(color: onHero),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(total),
              style: text.displaySmall?.copyWith(
                color: onHero,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(
                icon: Icons.receipt_long_outlined,
                label:
                    '${receipts.length} '
                    'receipt${receipts.length == 1 ? '' : 's'}',
              ),
              _HeroPill(
                icon: Icons.calendar_today_outlined,
                label: '${money(thisMonth)} this month',
              ),
              _HeroPill(
                icon: Icons.verified_user_outlined,
                label: '$activeWarranties under warranty',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A translucent stat pill on the hero card.
class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onHero = PapertrailColors.of(context).onHero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onHero.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: onHero),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: onHero),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long,
              size: 40,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text('No receipts yet', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Tap "Add receipt" to record your first purchase.\n'
            'Everything is stored privately in your own Solid Pod.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 36,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
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
