/// Full detail view of a single receipt, with edit and delete actions and
/// on-demand viewing of the attached photo or PDF.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/receipt.dart';
import '../services/pod_service.dart';
import '../services/receipt_store.dart';
import '../utils/formatting.dart';
import 'add_edit_receipt_screen.dart';

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({super.key, required this.receiptId});

  final String receiptId;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _busy = false;

  Future<void> _edit(Receipt receipt) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => AddEditReceiptScreen(existing: receipt)),
    );
    // The store updates itself on save; nothing else to do here.
  }

  Future<void> _delete(Receipt receipt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text(
            'This permanently removes "${receipt.title}" and its attachment '
            'from your Pod.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ReceiptStore.instance.delete(receipt);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReceiptStore.instance,
      builder: (context, _) {
        final receipt = ReceiptStore.instance.byId(widget.receiptId);
        if (receipt == null) {
          // Likely just deleted.
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This receipt is no longer available.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Receipt'),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _busy ? null : () => _edit(receipt),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _delete(receipt),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  receipt.title.isEmpty ? '(untitled receipt)' : receipt.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(receipt.amount, receipt.currency),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 20),
                _InfoRow(
                    icon: Icons.event,
                    label: 'Purchased',
                    value: formatDate(receipt.purchaseDate)),
                if (receipt.vendor.isNotEmpty)
                  _InfoRow(
                      icon: Icons.store_outlined,
                      label: 'Vendor',
                      value: receipt.vendor),
                if (receipt.hasWarranty)
                  _InfoRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Warranty',
                    value: receipt.warrantyExpiry == null
                        ? 'Yes'
                        : receipt.isWarrantyExpired
                            ? 'Expired ${formatDate(receipt.warrantyExpiry!)}'
                            : 'Until ${formatDate(receipt.warrantyExpiry!)} '
                                '(${relativeDay(receipt.warrantyExpiry!)})',
                    valueColor: receipt.isWarrantyExpired
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                if (receipt.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(receipt.description),
                ],
                if (receipt.categories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ChipBlock(
                      title: 'Categories', tags: receipt.categories),
                ],
                if (receipt.flags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ChipBlock(title: 'Flags', tags: receipt.flags),
                ],
                const SizedBox(height: 20),
                _AttachmentViewer(receipt: receipt),
                if (receipt.extraAttachments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _ExtraAttachmentsViewer(receipt: receipt),
                ],
                const SizedBox(height: 24),
                Text(
                  'Added ${formatDate(receipt.createdAt)}'
                  '${receipt.updatedAt != receipt.createdAt ? ' • updated ${formatDate(receipt.updatedAt)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          SizedBox(
            width: 88,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: valueColor)),
          ),
        ],
      ),
    );
  }
}

class _ChipBlock extends StatelessWidget {
  const _ChipBlock({required this.title, required this.tags});

  final String title;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: tags.map((t) => Chip(label: Text(t))).toList(),
        ),
      ],
    );
  }
}

/// Downloads (on demand) and displays a receipt's attachment.
class _AttachmentViewer extends StatefulWidget {
  const _AttachmentViewer({required this.receipt});

  final Receipt receipt;

  @override
  State<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<_AttachmentViewer> {
  Future<Uint8List>? _imageFuture;
  bool _openingPdf = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadImage();
  }

  @override
  void didUpdateWidget(_AttachmentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.attachmentExtension !=
        widget.receipt.attachmentExtension) {
      _maybeLoadImage();
    }
  }

  void _maybeLoadImage() {
    if (widget.receipt.attachmentKind == AttachmentKind.image) {
      _imageFuture = PodService.instance.readAttachmentBytes(widget.receipt.id);
    } else {
      _imageFuture = null;
    }
  }

  Future<void> _openPdf() async {
    setState(() => _openingPdf = true);
    try {
      final bytes =
          await PodService.instance.readAttachmentBytes(widget.receipt.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.receipt.id}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open PDF: ${result.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _openingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    if (!receipt.hasAttachment) {
      return const SizedBox.shrink();
    }

    Widget body;
    if (receipt.attachmentKind == AttachmentKind.image) {
      body = FutureBuilder<Uint8List>(
        future: _imageFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError || !snap.hasData) {
            return _AttachmentError(onRetry: () {
              setState(_maybeLoadImage);
            });
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(snap.data!, fit: BoxFit.contain),
          );
        },
      );
    } else {
      body = OutlinedButton.icon(
        onPressed: _openingPdf ? null : _openPdf,
        icon: _openingPdf
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf),
        label: Text(_openingPdf ? 'Opening…' : 'Open PDF'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attachment', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

class _AttachmentError extends StatelessWidget {
  const _AttachmentError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.broken_image_outlined),
        const SizedBox(width: 8),
        const Expanded(child: Text('Could not load attachment.')),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Extra attachments viewer
// ---------------------------------------------------------------------------

/// Shows all of a receipt's supplementary files.
class _ExtraAttachmentsViewer extends StatelessWidget {
  const _ExtraAttachmentsViewer({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Additional Files',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...receipt.extraAttachments.map(
          (extra) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ExtraAttachmentItem(receipt: receipt, extra: extra),
          ),
        ),
      ],
    );
  }
}

/// Downloads and displays one extra attachment.
class _ExtraAttachmentItem extends StatefulWidget {
  const _ExtraAttachmentItem(
      {required this.receipt, required this.extra});

  final Receipt receipt;
  final ExtraAttachment extra;

  @override
  State<_ExtraAttachmentItem> createState() => _ExtraAttachmentItemState();
}

class _ExtraAttachmentItemState extends State<_ExtraAttachmentItem> {
  Future<Uint8List>? _imageFuture;
  bool _openingPdf = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadImage();
  }

  @override
  void didUpdateWidget(_ExtraAttachmentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extra.id != widget.extra.id ||
        oldWidget.extra.extension != widget.extra.extension) {
      _maybeLoadImage();
    }
  }

  void _maybeLoadImage() {
    if (widget.extra.kind == AttachmentKind.image) {
      _imageFuture = PodService.instance.readExtraAttachmentBytes(
          widget.receipt.id, widget.extra.id);
    } else {
      _imageFuture = null;
    }
  }

  Future<void> _openPdf() async {
    setState(() => _openingPdf = true);
    try {
      final bytes = await PodService.instance.readExtraAttachmentBytes(
          widget.receipt.id, widget.extra.id);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${widget.receipt.id}_${widget.extra.id}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Could not open PDF: ${result.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: $e')));
      }
    } finally {
      if (mounted) setState(() => _openingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extra = widget.extra;

    Widget content;
    if (extra.kind == AttachmentKind.image) {
      content = FutureBuilder<Uint8List>(
        future: _imageFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError || !snap.hasData) {
            return _AttachmentError(
                onRetry: () => setState(_maybeLoadImage));
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(snap.data!, fit: BoxFit.contain),
          );
        },
      );
    } else {
      content = OutlinedButton.icon(
        onPressed: _openingPdf ? null : _openPdf,
        icon: _openingPdf
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf),
        label: Text(_openingPdf ? 'Opening…' : 'Open PDF'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (extra.description.isNotEmpty) ...[
          Text(
            extra.description,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
        ],
        content,
      ],
    );
  }
}
