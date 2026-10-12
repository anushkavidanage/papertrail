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
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import 'category_icon.dart';

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

  /// The leading icon: the first category's icon when it has one, else the
  /// kind of attachment.
  IconData get _leadingIcon {
    for (final c in receipt.categories) {
      final icon = categoryIcon(c);
      if (icon != null) return icon;
    }
    return switch (receipt.attachmentKind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.none => Icons.receipt_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final status = PapertrailColors.of(context);
    final inSelectionMode = isSelected != null;
    final selected = isSelected == true;
    final hasChips = receipt.categories.isNotEmpty || receipt.hasWarranty;

    final meta = [
      formatDate(receipt.purchaseDate),
      if (receipt.vendor.isNotEmpty) receipt.vendor,
    ].join('  ·  ');

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            crossAxisAlignment: hasChips
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (inSelectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: onTap != null ? (_) => onTap!() : null,
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _leadingIcon,
                    color: scheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.title.isEmpty
                          ? '(untitled receipt)'
                          : receipt.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (receipt.hasAttachment ||
                            receipt.extraAttachments.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.attach_file,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                            semanticLabel: 'Has attachment',
                          ),
                        ],
                      ],
                    ),
                    if (hasChips)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...receipt.categories
                                .take(3)
                                .map(
                                  (c) => _MiniChip(
                                    label: c,
                                    background: scheme.surfaceContainerHigh,
                                    foreground: scheme.onSurfaceVariant,
                                  ),
                                ),
                            if (receipt.hasWarranty)
                              receipt.isWarrantyExpired
                                  ? _MiniChip(
                                      label: 'Warranty expired',
                                      icon: Icons.gpp_bad_outlined,
                                      background: status.critical.container,
                                      foreground: status.critical.onContainer,
                                    )
                                  : _MiniChip(
                                      label: 'Under warranty',
                                      icon: Icons.verified_user_outlined,
                                      background: status.good.container,
                                      foreground: status.good.onContainer,
                                    ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatMoney(receipt.amount, receipt.currency),
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
