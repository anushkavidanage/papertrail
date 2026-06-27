/// Form for creating a new receipt or editing an existing one.
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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_config.dart';
import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../utils/formatting.dart';

// ---------------------------------------------------------------------------
// Extra-slot state holder — one per supplementary file in the form.
// ---------------------------------------------------------------------------

class _ExtraSlot {
  _ExtraSlot({
    required this.id,
    this.existingExtension,
    String? descriptionText,
  }) : description = TextEditingController(text: descriptionText ?? '');

  /// Stable UUID — also used as the Pod filename stem for this extra file.
  final String id;

  /// Extension already stored on the Pod when editing an existing receipt.
  final String? existingExtension;

  /// User-facing description controller.
  final TextEditingController description;

  /// Local file path after the user picks (or compresses) a new file.
  String? pickedPath;

  /// Extension of the newly-picked file.
  String? pickedExt;

  bool isCompressing = false;

  /// Effective extension to show in the UI and save to the model.
  String? get effectiveExtension => pickedExt ?? existingExtension;

  bool get hasFile => effectiveExtension != null;

  void dispose() => description.dispose();
}

// ---------------------------------------------------------------------------
// Screen widget
// ---------------------------------------------------------------------------

class AddEditReceiptScreen extends StatefulWidget {
  const AddEditReceiptScreen({super.key, this.existing, this.duplicateFrom});

  /// When non-null the form edits this receipt; otherwise it creates one.
  final Receipt? existing;

  /// When non-null the form is pre-filled from this receipt but saves as a
  /// brand-new entry (new UUID, no attachments copied).
  final Receipt? duplicateFrom;

  bool get isEditing => existing != null;
  bool get isDuplicating => duplicateFrom != null;

  @override
  State<AddEditReceiptScreen> createState() => _AddEditReceiptScreenState();
}

class _AddEditReceiptScreenState extends State<AddEditReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  late final TextEditingController _titleController;
  final FocusNode _titleFocus = FocusNode();
  late final TextEditingController _amountController;
  late final TextEditingController _vendorController;
  final FocusNode _vendorFocus = FocusNode();
  late final TextEditingController _descriptionController;

  late String _currency;
  late DateTime _purchaseDate;
  late Set<String> _categories;
  late Set<String> _flags;
  late bool _hasWarranty;
  DateTime? _warrantyExpiry;

  // Primary attachment state.
  String? _existingAttachmentExt;
  String? _pickedPath;
  String? _pickedExt;
  bool _removeAttachment = false;
  bool _compressing = false;

  // Extra attachment state.
  late final List<_ExtraSlot> _extraSlots;

  /// IDs of existing extra attachments that were removed; their Pod files
  /// must be deleted on save.
  final List<String> _removedExtraIds = [];

  bool _saving = false;

  /// Sorted list of distinct vendors from existing receipts, for autocomplete.
  late final List<String> _knownVendors;

  /// Sorted list of distinct titles from existing receipts, for autocomplete.
  late final List<String> _knownTitles;

  @override
  void initState() {
    super.initState();
    final r = widget.existing ?? widget.duplicateFrom;
    final duping = widget.isDuplicating;

    // Build the distinct, sorted vendor list for the autocomplete dropdown.
    final vendors = <String>{};
    for (final receipt in ReceiptStore.instance.receipts) {
      final v = receipt.vendor.trim();
      if (v.isNotEmpty) vendors.add(v);
    }
    _knownVendors = vendors.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Build the distinct, sorted title list for the autocomplete dropdown.
    final titles = <String>{};
    for (final receipt in ReceiptStore.instance.receipts) {
      final t = receipt.title.trim();
      if (t.isNotEmpty) titles.add(t);
    }
    _knownTitles = titles.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _titleController = TextEditingController(
      text: duping && r != null ? 'Copy of ${r.title}' : (r?.title ?? ''),
    );
    _amountController = TextEditingController(
      text: r != null ? r.amount.toStringAsFixed(2) : '',
    );
    _vendorController = TextEditingController(text: r?.vendor ?? '');
    _descriptionController = TextEditingController(text: r?.description ?? '');
    _currency = r?.currency ?? currencies.first;
    _purchaseDate = duping
        ? DateTime.now()
        : (r?.purchaseDate ?? DateTime.now());
    _categories = {...?r?.categories};
    _flags = {...?r?.flags};
    _hasWarranty = r?.hasWarranty ?? false;
    _warrantyExpiry = r?.warrantyExpiry;
    // Attachments are not copied when duplicating — the new receipt starts clean.
    _existingAttachmentExt = duping ? null : r?.attachmentExtension;

    _extraSlots = duping
        ? []
        : (r?.extraAttachments ?? [])
              .map(
                (e) => _ExtraSlot(
                  id: e.id,
                  existingExtension: e.extension,
                  descriptionText: e.description,
                ),
              )
              .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    _amountController.dispose();
    _vendorController.dispose();
    _vendorFocus.dispose();
    _descriptionController.dispose();
    for (final slot in _extraSlots) {
      slot.dispose();
    }
    super.dispose();
  }

  String? get _effectiveAttachmentExt {
    if (_pickedExt != null) return _pickedExt;
    if (_removeAttachment) return null;
    return _existingAttachmentExt;
  }

  // -------------------------------------------------------------------------
  // Date pickers
  // -------------------------------------------------------------------------

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
      initialDate:
          _warrantyExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _warrantyExpiry = picked);
  }

  // -------------------------------------------------------------------------
  // Primary attachment
  // -------------------------------------------------------------------------

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
    final ext = (file.extension ?? '').toLowerCase();

    if (size > maxAttachmentBytes) {
      if (AttachmentKind.fromExtension(ext) != AttachmentKind.image) {
        // PDFs cannot be compressed — hard limit.
        final sizeMb = (size / (1024 * 1024)).toStringAsFixed(1);
        final limitMb = maxAttachmentBytes ~/ (1024 * 1024);
        _showSnack(
          'This PDF is $sizeMb MB. PDFs must be $limitMb MB or smaller.',
        );
        return;
      }

      // Image is over the limit — compress it in a background isolate.
      setState(() => _compressing = true);
      try {
        final originalBytes = await File(file.path!).readAsBytes();
        final compressed = await compute(_compressToJpeg, (
          originalBytes,
          maxAttachmentBytes,
        ));
        if (!mounted) return;
        if (compressed == null || compressed.length > maxAttachmentBytes) {
          _showSnack(
            'Could not compress this image under '
            '${maxAttachmentBytes ~/ (1024 * 1024)} MB. '
            'Try a JPEG file or a smaller image.',
          );
          setState(() => _compressing = false);
          return;
        }
        final dir = await getTemporaryDirectory();
        final tmp = File(
          '${dir.path}/pt_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tmp.writeAsBytes(compressed);
        final origMb = (size / (1024 * 1024)).toStringAsFixed(1);
        final newMb = (compressed.length / (1024 * 1024)).toStringAsFixed(1);
        if (!mounted) return;
        setState(() {
          _pickedPath = tmp.path;
          _pickedExt = 'jpg';
          _removeAttachment = false;
          _compressing = false;
        });
        _showSnack('Image compressed from $origMb MB to $newMb MB.');
      } catch (e) {
        if (mounted) setState(() => _compressing = false);
        _showSnack('Could not compress image: $e');
      }
      return;
    }

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

  Future<void> _captureAttachment() async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: ImageSource.camera);
    } catch (e) {
      _showSnack('Camera is not available: $e');
      return;
    }
    if (photo == null) return;

    final file = File(photo.path);
    final size = await file.length();

    if (size > maxAttachmentBytes) {
      setState(() => _compressing = true);
      try {
        final originalBytes = await file.readAsBytes();
        final compressed = await compute(_compressToJpeg, (
          originalBytes,
          maxAttachmentBytes,
        ));
        if (!mounted) return;
        if (compressed == null || compressed.length > maxAttachmentBytes) {
          _showSnack(
            'Could not compress this photo under '
            '${maxAttachmentBytes ~/ (1024 * 1024)} MB.',
          );
          setState(() => _compressing = false);
          return;
        }
        final dir = await getTemporaryDirectory();
        final tmp = File(
          '${dir.path}/pt_cam_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tmp.writeAsBytes(compressed);
        if (!mounted) return;
        setState(() {
          _pickedPath = tmp.path;
          _pickedExt = 'jpg';
          _removeAttachment = false;
          _compressing = false;
        });
      } catch (e) {
        if (mounted) setState(() => _compressing = false);
        _showSnack('Could not process photo: $e');
      }
      return;
    }

    setState(() {
      _pickedPath = photo?.path;
      _pickedExt = 'jpg';
      _removeAttachment = false;
    });
  }

  // -------------------------------------------------------------------------
  // Extra attachments
  // -------------------------------------------------------------------------

  void _addExtraSlot() {
    setState(() => _extraSlots.add(_ExtraSlot(id: _uuid.v4())));
  }

  void _removeExtraSlot(int index) {
    final slot = _extraSlots[index];
    if (slot.existingExtension != null) {
      // Mark for deletion from the Pod on save.
      _removedExtraIds.add(slot.id);
    }
    setState(() => _extraSlots.removeAt(index));
    slot.dispose();
  }

  Future<void> _pickExtraFile(int index) async {
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
    final size = file.size > 0 ? file.size : File(file.path!).lengthSync();
    final ext = (file.extension ?? '').toLowerCase();

    if (size > maxAttachmentBytes) {
      if (AttachmentKind.fromExtension(ext) != AttachmentKind.image) {
        final sizeMb = (size / (1024 * 1024)).toStringAsFixed(1);
        final limitMb = maxAttachmentBytes ~/ (1024 * 1024);
        _showSnack(
          'This PDF is $sizeMb MB. PDFs must be $limitMb MB or smaller.',
        );
        return;
      }

      setState(() => _extraSlots[index].isCompressing = true);
      try {
        final originalBytes = await File(file.path!).readAsBytes();
        final compressed = await compute(_compressToJpeg, (
          originalBytes,
          maxAttachmentBytes,
        ));
        if (!mounted) return;
        if (compressed == null || compressed.length > maxAttachmentBytes) {
          _showSnack(
            'Could not compress this image under '
            '${maxAttachmentBytes ~/ (1024 * 1024)} MB. '
            'Try a JPEG file or a smaller image.',
          );
          setState(() => _extraSlots[index].isCompressing = false);
          return;
        }
        final dir = await getTemporaryDirectory();
        final tmp = File(
          '${dir.path}/pt_extra_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tmp.writeAsBytes(compressed);
        final origMb = (size / (1024 * 1024)).toStringAsFixed(1);
        final newMb = (compressed.length / (1024 * 1024)).toStringAsFixed(1);
        if (!mounted) return;
        setState(() {
          _extraSlots[index].pickedPath = tmp.path;
          _extraSlots[index].pickedExt = 'jpg';
          _extraSlots[index].isCompressing = false;
        });
        _showSnack('Image compressed from $origMb MB to $newMb MB.');
      } catch (e) {
        if (mounted) setState(() => _extraSlots[index].isCompressing = false);
        _showSnack('Could not compress image: $e');
      }
      return;
    }

    setState(() {
      _extraSlots[index].pickedPath = file.path;
      _extraSlots[index].pickedExt = ext.isEmpty ? null : ext;
    });
  }

  Future<void> _captureExtraPhoto(int index) async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: ImageSource.camera);
    } catch (e) {
      _showSnack('Camera is not available: $e');
      return;
    }
    if (photo == null) return;

    final file = File(photo.path);
    final size = await file.length();

    if (size > maxAttachmentBytes) {
      setState(() => _extraSlots[index].isCompressing = true);
      try {
        final originalBytes = await file.readAsBytes();
        final compressed = await compute(_compressToJpeg, (
          originalBytes,
          maxAttachmentBytes,
        ));
        if (!mounted) return;
        if (compressed == null || compressed.length > maxAttachmentBytes) {
          _showSnack(
            'Could not compress this photo under '
            '${maxAttachmentBytes ~/ (1024 * 1024)} MB.',
          );
          setState(() => _extraSlots[index].isCompressing = false);
          return;
        }
        final dir = await getTemporaryDirectory();
        final tmp = File(
          '${dir.path}/pt_cam_extra_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tmp.writeAsBytes(compressed);
        if (!mounted) return;
        setState(() {
          _extraSlots[index].pickedPath = tmp.path;
          _extraSlots[index].pickedExt = 'jpg';
          _extraSlots[index].isCompressing = false;
        });
      } catch (e) {
        if (mounted) setState(() => _extraSlots[index].isCompressing = false);
        _showSnack('Could not process photo: $e');
      }
      return;
    }

    setState(() {
      _extraSlots[index].pickedPath = photo?.path;
      _extraSlots[index].pickedExt = 'jpg';
    });
  }

  // -------------------------------------------------------------------------
  // Tags
  // -------------------------------------------------------------------------

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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasWarranty && _warrantyExpiry == null) {
      _showSnack('Please set a warranty expiry date, or turn warranty off.');
      return;
    }

    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    final now = DateTime.now();
    final existing = widget.existing;

    // Build extra attachment data.
    final extraAttachments = <ExtraAttachment>[];
    final extraPaths = <String, String>{};
    for (final slot in _extraSlots) {
      if (!slot.hasFile) continue;
      extraAttachments.add(
        ExtraAttachment(
          id: slot.id,
          extension: slot.effectiveExtension!,
          description: slot.description.text.trim(),
        ),
      );
      if (slot.pickedPath != null) {
        extraPaths[slot.id] = slot.pickedPath!;
      }
    }

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
      extraAttachments: extraAttachments,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    try {
      await ReceiptStore.instance.save(
        receipt,
        attachmentPath: _pickedPath,
        removeAttachment: _removeAttachment && _pickedPath == null,
        extraAttachmentPaths: extraPaths,
        extraAttachmentIdsToDelete: _removedExtraIds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(receipt);
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('Could not save receipt: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Edit receipt'
              : widget.isDuplicating
              ? 'Duplicate receipt'
              : 'Add receipt',
        ),
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
                  RawAutocomplete<String>(
                    textEditingController: _titleController,
                    focusNode: _titleFocus,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      if (query.isEmpty) return _knownTitles;
                      return _knownTitles.where(
                        (t) => t.toLowerCase().contains(query),
                      );
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Title *',
                              hintText: 'e.g. Coffee machine',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.arrow_drop_down),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter a title'
                                : null,
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 240,
                              maxWidth: 400,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final option = options.elementAt(i);
                                return ListTile(
                                  dense: true,
                                  title: Text(option),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
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
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final parsed = double.tryParse(
                              (v ?? '').trim().replaceAll(',', ''),
                            );
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
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
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
                  RawAutocomplete<String>(
                    textEditingController: _vendorController,
                    focusNode: _vendorFocus,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      if (query.isEmpty) return _knownVendors;
                      return _knownVendors.where(
                        (v) => v.toLowerCase().contains(query),
                      );
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Store / vendor',
                              hintText: 'e.g. The Good Guys',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.arrow_drop_down),
                            ),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 240,
                              maxWidth: 400,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final option = options.elementAt(i);
                                return ListTile(
                                  dense: true,
                                  title: Text(option),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
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
                    onCamera: (Platform.isAndroid || Platform.isIOS)
                        ? _captureAttachment
                        : null,
                    isCompressing: _compressing,
                  ),
                  const SizedBox(height: 24),
                  _ExtraAttachmentsSection(
                    slots: _extraSlots,
                    onAdd: _addExtraSlot,
                    onRemove: _removeExtraSlot,
                    onPick: _pickExtraFile,
                    onCamera: (Platform.isAndroid || Platform.isIOS)
                        ? _captureExtraPhoto
                        : null,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(
                      widget.isEditing ? 'Save changes' : 'Save receipt',
                    ),
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

// ---------------------------------------------------------------------------
// Shared form sub-widgets
// ---------------------------------------------------------------------------

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
            value: expiry == null
                ? 'Tap to choose a date'
                : formatDate(expiry!),
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
    this.onCamera,
    this.isCompressing = false,
  });

  final String? extension;
  final String? pickedPath;
  final VoidCallback onPick;
  final VoidCallback onClear;

  /// Non-null only on Android / iOS — shows a "Take photo" button.
  final VoidCallback? onCamera;
  final bool isCompressing;

  @override
  Widget build(BuildContext context) {
    final kind = AttachmentKind.fromExtension(extension);
    final hasAttachment = extension != null;

    Widget preview;
    if (isCompressing) {
      preview = Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Compressing image…'),
        ],
      );
    } else if (pickedPath != null && kind == AttachmentKind.image) {
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
            kind == AttachmentKind.pdf ? Icons.picture_as_pdf : Icons.image,
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
          'Images over ${maxAttachmentBytes ~/ (1024 * 1024)} MB are compressed '
          'automatically. PDFs must be '
          '${maxAttachmentBytes ~/ (1024 * 1024)} MB or smaller.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        preview,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onCamera != null)
              OutlinedButton.icon(
                onPressed: isCompressing ? null : onCamera,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
            OutlinedButton.icon(
              onPressed: isCompressing ? null : onPick,
              icon: const Icon(Icons.attach_file),
              label: Text(hasAttachment ? 'Replace file' : 'Add file'),
            ),
            if (hasAttachment && !isCompressing)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Extra attachments section
// ---------------------------------------------------------------------------

class _ExtraAttachmentsSection extends StatelessWidget {
  const _ExtraAttachmentsSection({
    required this.slots,
    required this.onAdd,
    required this.onRemove,
    required this.onPick,
    this.onCamera,
  });

  final List<_ExtraSlot> slots;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final Future<void> Function(int index) onPick;

  /// Non-null only on Android / iOS — passed down to each slot tile.
  final Future<void> Function(int index)? onCamera;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Additional Files',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Attach supplementary files such as a warranty card or invoice. '
          'Same size limits apply.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ...List.generate(
          slots.length,
          (i) => _ExtraSlotTile(
            index: i,
            slot: slots[i],
            onRemove: () => onRemove(i),
            onPick: () => onPick(i),
            onCamera: onCamera != null ? () => onCamera!(i) : null,
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add another file'),
        ),
      ],
    );
  }
}

class _ExtraSlotTile extends StatelessWidget {
  const _ExtraSlotTile({
    required this.index,
    required this.slot,
    required this.onRemove,
    required this.onPick,
    this.onCamera,
  });

  final int index;
  final _ExtraSlot slot;
  final VoidCallback onRemove;
  final VoidCallback onPick;

  /// Non-null only on Android / iOS.
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final kind = AttachmentKind.fromExtension(slot.effectiveExtension);
    final hasFile = slot.hasFile;

    Widget preview;
    if (slot.isCompressing) {
      preview = Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Compressing image…'),
        ],
      );
    } else if (slot.pickedPath != null && kind == AttachmentKind.image) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(slot.pickedPath!),
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (hasFile) {
      preview = Row(
        children: [
          Icon(
            kind == AttachmentKind.pdf ? Icons.picture_as_pdf : Icons.image,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              slot.pickedPath == null
                  ? 'Stored on your Pod (.${slot.effectiveExtension})'
                  : 'Selected file (.${slot.effectiveExtension})',
            ),
          ),
        ],
      );
    } else {
      preview = Text(
        'No file selected',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'File ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove this file',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            preview,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onCamera != null)
                  OutlinedButton.icon(
                    onPressed: slot.isCompressing ? null : onCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take photo'),
                  ),
                OutlinedButton.icon(
                  onPressed: slot.isCompressing ? null : onPick,
                  icon: const Icon(Icons.attach_file),
                  label: Text(hasFile ? 'Replace file' : 'Choose file'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: slot.description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'e.g. Warranty card, Invoice, User manual',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (slot.hasFile && (v == null || v.trim().isEmpty)) {
                  return 'Please describe this file';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image compression — runs in a background isolate via compute().
//
// Decodes any supported image format, resizes to at most 2048 px on the
// longest side, then re-encodes as JPEG at progressively lower quality until
// the result fits within [maxBytes]. Returns null if the image cannot be
// decoded (e.g. unsupported HEIC on this platform).
// ---------------------------------------------------------------------------

Uint8List? _compressToJpeg((Uint8List bytes, int maxBytes) args) {
  final (bytes, maxBytes) = args;

  var image = img.decodeImage(bytes);
  if (image == null) return null;

  // Downscale if either dimension exceeds 2048 px.
  const maxDim = 2048;
  if (image.width > maxDim || image.height > maxDim) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxDim)
        : img.copyResize(image, height: maxDim);
  }

  for (final quality in [85, 70, 50, 30, 15]) {
    final out = img.encodeJpg(image, quality: quality);
    if (out.length <= maxBytes) return out;
  }
  // Last resort — quality 10.  Virtually any photo fits under 1 MB at this
  // level after the resize above.
  return img.encodeJpg(image, quality: 10);
}
