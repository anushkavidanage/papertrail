/// Form for creating a new receipt or editing an existing one.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_config.dart';
import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../utils/formatting.dart';

class AddEditReceiptScreen extends StatefulWidget {
  const AddEditReceiptScreen({super.key, this.existing});

  /// When non-null the form edits this receipt; otherwise it creates one.
  final Receipt? existing;

  bool get isEditing => existing != null;

  @override
  State<AddEditReceiptScreen> createState() => _AddEditReceiptScreenState();
}

class _AddEditReceiptScreenState extends State<AddEditReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _vendorController;
  late final TextEditingController _descriptionController;

  late String _currency;
  late DateTime _purchaseDate;
  late Set<String> _categories;
  late Set<String> _flags;
  late bool _hasWarranty;
  DateTime? _warrantyExpiry;

  // Attachment state.
  String? _existingAttachmentExt;
  String? _pickedPath;
  String? _pickedExt;
  bool _removeAttachment = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _titleController = TextEditingController(text: r?.title ?? '');
    _amountController = TextEditingController(
        text: r != null ? r.amount.toStringAsFixed(2) : '');
    _vendorController = TextEditingController(text: r?.vendor ?? '');
    _descriptionController = TextEditingController(text: r?.description ?? '');
    _currency = r?.currency ?? currencies.first;
    _purchaseDate = r?.purchaseDate ?? DateTime.now();
    _categories = {...?r?.categories};
    _flags = {...?r?.flags};
    _hasWarranty = r?.hasWarranty ?? false;
    _warrantyExpiry = r?.warrantyExpiry;
    _existingAttachmentExt = r?.attachmentExtension;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _vendorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? get _effectiveAttachmentExt {
    if (_pickedExt != null) return _pickedExt;
    if (_removeAttachment) return null;
    return _existingAttachmentExt;
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _pickWarrantyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _warrantyExpiry = picked);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: attachmentExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.path == null) {
      _showSnack('Could not read the selected file on this platform.');
      return;
    }
    // file_picker reports 0 on platforms where it cannot stat the file.
    final size = file.size > 0 ? file.size : File(file.path!).lengthSync();
    if (size > maxAttachmentBytes) {
      final sizeMb = (size / (1024 * 1024)).toStringAsFixed(1);
      final limitMb = maxAttachmentBytes ~/ (1024 * 1024);
      _showSnack(
          'This file is $sizeMb MB. Attachments must be $limitMb MB or smaller.');
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    setState(() {
      _pickedPath = file.path;
      _pickedExt = ext.isEmpty ? null : ext;
      _removeAttachment = false;
    });
  }

  void _clearAttachment() {
    setState(() {
      _pickedPath = null;
      _pickedExt = null;
      _removeAttachment = _existingAttachmentExt != null;
    });
  }

  Future<void> _addCustomTag({required bool isCategory}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCategory ? 'Add category' : 'Add flag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: isCategory ? 'e.g. Subscriptions' : 'e.g. Urgent',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final tag = value?.trim();
    if (tag != null && tag.isNotEmpty) {
      setState(() => (isCategory ? _categories : _flags).add(tag));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasWarranty && _warrantyExpiry == null) {
      _showSnack('Please set a warranty expiry date, or turn warranty off.');
      return;
    }

    final amount =
        double.parse(_amountController.text.trim().replaceAll(',', ''));
    final now = DateTime.now();
    final existing = widget.existing;

    final receipt = Receipt(
      id: existing?.id ?? _uuid.v4(),
      title: _titleController.text.trim(),
      amount: amount,
      currency: _currency,
      purchaseDate: _purchaseDate,
      description: _descriptionController.text.trim(),
      vendor: _vendorController.text.trim(),
      categories: _categories.toList()..sort(),
      flags: _flags.toList()..sort(),
      hasWarranty: _hasWarranty,
      warrantyExpiry: _hasWarranty ? _warrantyExpiry : null,
      attachmentExtension: _effectiveAttachmentExt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    try {
      await ReceiptStore.instance.save(
        receipt,
        attachmentPath: _pickedPath,
        removeAttachment: _removeAttachment && _pickedPath == null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(receipt);
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('Could not save receipt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit receipt' : 'Add receipt'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g. Coffee machine',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Amount *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final parsed = double.tryParse(
                                (v ?? '').trim().replaceAll(',', ''));
                            if (parsed == null) return 'Enter a number';
                            if (parsed < 0) return 'Must be ≥ 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(
                            labelText: 'Currency',
                            border: OutlineInputBorder(),
                          ),
                          items: currencies
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _currency = v ?? _currency),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DateTile(
                    icon: Icons.event,
                    label: 'Purchase date',
                    value: formatDate(_purchaseDate),
                    onTap: _pickPurchaseDate,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _vendorController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Store / vendor',
                      hintText: 'e.g. The Good Guys',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description / notes',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TagSection(
                    title: 'Categories',
                    options: {...defaultCategories, ..._categories},
                    selected: _categories,
                    onToggle: (tag, sel) => setState(() {
                      sel ? _categories.add(tag) : _categories.remove(tag);
                    }),
                    onAddCustom: () => _addCustomTag(isCategory: true),
                  ),
                  const SizedBox(height: 24),
                  _TagSection(
                    title: 'Flags',
                    options: {...defaultFlags, ..._flags},
                    selected: _flags,
                    onToggle: (tag, sel) => setState(() {
                      sel ? _flags.add(tag) : _flags.remove(tag);
                    }),
                    onAddCustom: () => _addCustomTag(isCategory: false),
                  ),
                  const SizedBox(height: 24),
                  _WarrantySection(
                    hasWarranty: _hasWarranty,
                    expiry: _warrantyExpiry,
                    onChanged: (v) => setState(() {
                      _hasWarranty = v;
                      if (!v) _warrantyExpiry = null;
                    }),
                    onPickExpiry: _pickWarrantyDate,
                  ),
                  const SizedBox(height: 24),
                  _AttachmentSection(
                    extension: _effectiveAttachmentExt,
                    pickedPath: _pickedPath,
                    onPick: _pickAttachment,
                    onClear: _clearAttachment,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(widget.isEditing
                        ? 'Save changes'
                        : 'Save receipt'),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
            if (_saving)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        child: Text(value),
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onAddCustom,
  });

  final String title;
  final Set<String> options;
  final Set<String> selected;
  final void Function(String tag, bool selected) onToggle;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    final sorted = options.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...sorted.map(
              (tag) => FilterChip(
                label: Text(tag),
                selected: selected.contains(tag),
                onSelected: (sel) => onToggle(tag, sel),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              onPressed: onAddCustom,
            ),
          ],
        ),
      ],
    );
  }
}

class _WarrantySection extends StatelessWidget {
  const _WarrantySection({
    required this.hasWarranty,
    required this.expiry,
    required this.onChanged,
    required this.onPickExpiry,
  });

  final bool hasWarranty;
  final DateTime? expiry;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPickExpiry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Has warranty'),
          subtitle: const Text('Track when the warranty expires'),
          value: hasWarranty,
          onChanged: onChanged,
        ),
        if (hasWarranty) ...[
          const SizedBox(height: 8),
          _DateTile(
            icon: Icons.verified_user_outlined,
            label: 'Warranty expires',
            value: expiry == null ? 'Tap to choose a date' : formatDate(expiry!),
            onTap: onPickExpiry,
          ),
        ],
      ],
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.extension,
    required this.pickedPath,
    required this.onPick,
    required this.onClear,
  });

  final String? extension;
  final String? pickedPath;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final kind = AttachmentKind.fromExtension(extension);
    final hasAttachment = extension != null;

    Widget preview;
    if (pickedPath != null && kind == AttachmentKind.image) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(pickedPath!),
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (hasAttachment) {
      preview = Row(
        children: [
          Icon(
            kind == AttachmentKind.pdf
                ? Icons.picture_as_pdf
                : Icons.image,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pickedPath == null
                  ? 'Attachment stored on your Pod (.$extension)'
                  : 'Selected file (.$extension)',
            ),
          ),
        ],
      );
    } else {
      preview = const Text('No attachment');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attachment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Add a photo of the receipt or a PDF document '
          '(max ${maxAttachmentBytes ~/ (1024 * 1024)} MB).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        preview,
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.attach_file),
              label: Text(hasAttachment ? 'Replace' : 'Add file'),
            ),
            if (hasAttachment) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
