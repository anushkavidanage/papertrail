/// The [Receipt] domain model.
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

/// The kind of attachment associated with a receipt.
enum AttachmentKind {
  none,
  image,
  pdf;

  static AttachmentKind fromExtension(String? ext) {
    if (ext == null) return AttachmentKind.none;
    final e = ext.toLowerCase().replaceFirst('.', '');
    if (e == 'pdf') return AttachmentKind.pdf;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'].contains(e)) {
      return AttachmentKind.image;
    }
    return AttachmentKind.none;
  }
}

/// A secondary file attached to a receipt, with a user-supplied description.
///
/// Stored on the Pod at `attachments/<receiptId>_e<id>`. The [id] is a stable
/// UUID assigned at creation time and used as the Pod filename stem.
class ExtraAttachment {
  ExtraAttachment({
    required this.id,
    required this.extension,
    required this.description,
  });

  final String id;
  final String extension;
  final String description;

  AttachmentKind get kind => AttachmentKind.fromExtension(extension);

  Map<String, dynamic> toJson() => {
    'id': id,
    'extension': extension,
    'description': description,
  };

  factory ExtraAttachment.fromJson(Map<String, dynamic> json) =>
      ExtraAttachment(
        id: (json['id'] as String?) ?? '',
        extension: (json['extension'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
      );
}

/// A single purchase receipt.
///
/// Instances are serialised to an encrypted Turtle file on the user's Pod
/// (see `ReceiptSerializer`). The attachment bytes (photo or PDF) are stored
/// separately via the Solid large-file API and referenced here by
/// [attachmentExtension]. Additional files are stored per-entry in
/// [extraAttachments].
class Receipt {
  Receipt({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.vendor = '',
    this.categories = const [],
    this.flags = const [],
    this.hasWarranty = false,
    this.warrantyExpiry,
    this.attachmentExtension,
    this.extraAttachments = const [],
  });

  /// Stable unique identifier; also the file name stem on the Pod.
  final String id;

  /// Short title, e.g. "Coffee machine".
  String title;

  /// Total amount paid.
  double amount;

  /// ISO currency code, e.g. "AUD".
  String currency;

  /// When the purchase was made.
  DateTime purchaseDate;

  /// Free-form notes.
  String description;

  /// The shop or merchant name.
  String vendor;

  /// One or more categories such as "Grocery" or "Electronics".
  List<String> categories;

  /// Arbitrary flags the user attaches such as "Tax deductible".
  List<String> flags;

  /// Whether the purchase carries a warranty.
  bool hasWarranty;

  /// When the warranty expires (only meaningful when [hasWarranty]).
  DateTime? warrantyExpiry;

  /// File extension of the stored attachment (e.g. "jpg", "pdf"), or null when
  /// the receipt has no attachment.
  String? attachmentExtension;

  /// Additional supplementary files (e.g. warranty card, invoice).
  List<ExtraAttachment> extraAttachments;

  /// When the receipt entry was first created.
  final DateTime createdAt;

  /// When the receipt entry was last modified.
  DateTime updatedAt;

  bool get hasAttachment => attachmentExtension != null;

  AttachmentKind get attachmentKind =>
      AttachmentKind.fromExtension(attachmentExtension);

  /// True when the warranty has a date that is already in the past.
  bool get isWarrantyExpired =>
      hasWarranty &&
      warrantyExpiry != null &&
      warrantyExpiry!.isBefore(DateTime.now());

  /// Days remaining until the warranty expires, or null when not applicable.
  int? get warrantyDaysRemaining {
    if (!hasWarranty || warrantyExpiry == null) return null;
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final d1 = DateTime(
      warrantyExpiry!.year,
      warrantyExpiry!.month,
      warrantyExpiry!.day,
    );
    return d1.difference(d0).inDays;
  }

  Receipt copyWith({
    String? title,
    double? amount,
    String? currency,
    DateTime? purchaseDate,
    String? description,
    String? vendor,
    List<String>? categories,
    List<String>? flags,
    bool? hasWarranty,
    DateTime? warrantyExpiry,
    bool clearWarrantyExpiry = false,
    String? attachmentExtension,
    bool clearAttachment = false,
    List<ExtraAttachment>? extraAttachments,
    DateTime? updatedAt,
  }) {
    return Receipt(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      description: description ?? this.description,
      vendor: vendor ?? this.vendor,
      categories: categories ?? this.categories,
      flags: flags ?? this.flags,
      hasWarranty: hasWarranty ?? this.hasWarranty,
      warrantyExpiry: clearWarrantyExpiry
          ? null
          : (warrantyExpiry ?? this.warrantyExpiry),
      attachmentExtension: clearAttachment
          ? null
          : (attachmentExtension ?? this.attachmentExtension),
      extraAttachments: extraAttachments ?? this.extraAttachments,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Serialise to a plain JSON-compatible map (the canonical payload).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'currency': currency,
    'purchaseDate': purchaseDate.toIso8601String(),
    'description': description,
    'vendor': vendor,
    'categories': categories,
    'flags': flags,
    'hasWarranty': hasWarranty,
    'warrantyExpiry': warrantyExpiry?.toIso8601String(),
    'attachmentExtension': attachmentExtension,
    'extraAttachments': extraAttachments.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Reconstruct from a JSON map produced by [toJson].
  factory Receipt.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return Receipt(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?) ?? 'AUD',
      purchaseDate: parseDate(json['purchaseDate']) ?? DateTime.now(),
      description: (json['description'] as String?) ?? '',
      vendor: (json['vendor'] as String?) ?? '',
      categories:
          (json['categories'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      flags: (json['flags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hasWarranty: (json['hasWarranty'] as bool?) ?? false,
      warrantyExpiry: parseDate(json['warrantyExpiry']),
      attachmentExtension: json['attachmentExtension'] as String?,
      extraAttachments:
          (json['extraAttachments'] as List?)
              ?.map((e) => ExtraAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: parseDate(json['updatedAt']) ?? DateTime.now(),
    );
  }
}
