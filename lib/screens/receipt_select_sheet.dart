/// Bottom sheet to choose which receipts to include in a PDF view.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.

library;

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../utils/formatting.dart';

/// Lets the user pick a subset of [allReceipts] to view as a PDF. Returns the
/// selected receipts, or null if cancelled. Initially all are selected.

class ReceiptSelectSheet extends StatefulWidget {
  const ReceiptSelectSheet({super.key, required this.allReceipts});

  final List<Receipt> allReceipts;

  @override
  State<ReceiptSelectSheet> createState() => _ReceiptSelectSheetState();
}

class _ReceiptSelectSheetState extends State<ReceiptSelectSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.allReceipts.map((r) => r.id).toSet();
  }

  bool get _allSelected => _selected.length == widget.allReceipts.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.allReceipts.map((r) => r.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select receipts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAll,
                    child: Text(_allSelected ? 'Clear all' : 'Select all'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.allReceipts.length,
                itemBuilder: (context, i) {
                  final r = widget.allReceipts[i];
                  final checked = _selected.contains(r.id);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(r.title),
                    subtitle: Text(
                      '${formatDate(r.purchaseDate)}  ·  '
                      '${formatMoney(r.amount, r.currency)}'
                      '${r.vendor.isEmpty ? '' : '  ·  ${r.vendor}'}',
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(r.id);
                        } else {
                          _selected.remove(r.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('${_selected.length} selected'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final chosen = widget.allReceipts
                                .where((r) => _selected.contains(r.id))
                                .toList();
                            Navigator.of(context).pop(chosen);
                          },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('View PDF'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
