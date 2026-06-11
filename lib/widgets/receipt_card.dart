/// A compact card summarising a single receipt for use in lists.
library;

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../utils/formatting.dart';

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.receipt, this.onTap});

  final Receipt receipt;
  final VoidCallback? onTap;

  IconData get _attachmentIcon => switch (receipt.attachmentKind) {
        AttachmentKind.image => Icons.image_outlined,
        AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
        AttachmentKind.none => Icons.receipt_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(_attachmentIcon),
        ),
        title: Text(
          receipt.title.isEmpty ? '(untitled receipt)' : receipt.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                formatDate(receipt.purchaseDate),
                if (receipt.vendor.isNotEmpty) receipt.vendor,
              ].join('  •  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (receipt.categories.isNotEmpty || receipt.hasWarranty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...receipt.categories.take(3).map(
                          (c) => _MiniChip(label: c, color: scheme.secondaryContainer),
                        ),
                    if (receipt.hasWarranty)
                      _MiniChip(
                        label: receipt.isWarrantyExpired
                            ? 'Warranty expired'
                            : 'Under warranty',
                        color: receipt.isWarrantyExpired
                            ? scheme.errorContainer
                            : scheme.tertiaryContainer,
                        icon: Icons.verified_user_outlined,
                      ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Text(
          formatMoney(receipt.amount, receipt.currency),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        isThreeLine:
            receipt.categories.isNotEmpty || receipt.hasWarranty,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13),
            const SizedBox(width: 4),
          ],
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
