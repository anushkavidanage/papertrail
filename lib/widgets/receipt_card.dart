/// A compact card summarising a single receipt for use in lists.
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
import '../utils/formatting.dart';

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({
    super.key,
    required this.receipt,
    this.onTap,
    this.onLongPress,
    this.isSelected,
  });

  final Receipt receipt;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Non-null when the list is in selection mode. `true` = this card is
  /// selected, `false` = visible but not selected.
  final bool? isSelected;

  IconData get _attachmentIcon => switch (receipt.attachmentKind) {
    AttachmentKind.image => Icons.image_outlined,
    AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AttachmentKind.none => Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inSelectionMode = isSelected != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected == true
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: inSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: onTap != null ? (_) => onTap!() : null,
              )
            : CircleAvatar(
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
                    ...receipt.categories
                        .take(3)
                        .map(
                          (c) => _MiniChip(
                            label: c,
                            color: scheme.secondaryContainer,
                          ),
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
          style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary),
        ),
        isThreeLine: receipt.categories.isNotEmpty || receipt.hasWarranty,
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
          if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: 4)],
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
