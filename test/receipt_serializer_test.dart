// Unit tests for the receipt Turtle (de)serialisation round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:papertrail/models/receipt.dart';
import 'package:papertrail/services/receipt_serializer.dart';

void main() {
  test('round-trips a fully populated receipt', () {
    final original = Receipt(
      id: 'abc-123',
      title: 'Espresso machine "Deluxe"\nwith line break',
      amount: 1299.95,
      currency: 'AUD',
      purchaseDate: DateTime(2026, 6, 1),
      description: 'Includes milk frother, backslash \\ and quote "',
      vendor: 'The Good Guys',
      categories: ['Electronics', 'Home'],
      flags: ['Tax deductible', 'Important'],
      hasWarranty: true,
      warrantyExpiry: DateTime(2028, 6, 1),
      attachmentExtension: 'pdf',
      createdAt: DateTime(2026, 6, 1, 10, 30),
      updatedAt: DateTime(2026, 6, 2, 9),
    );

    final turtle = ReceiptSerializer.toTurtle(original);
    final restored = ReceiptSerializer.fromTurtle(turtle);

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.amount, original.amount);
    expect(restored.currency, original.currency);
    expect(restored.purchaseDate, original.purchaseDate);
    expect(restored.description, original.description);
    expect(restored.vendor, original.vendor);
    expect(restored.categories, original.categories);
    expect(restored.flags, original.flags);
    expect(restored.hasWarranty, isTrue);
    expect(restored.warrantyExpiry, original.warrantyExpiry);
    expect(restored.attachmentExtension, 'pdf');
  });

  test('round-trips a minimal receipt with no attachment or warranty', () {
    final original = Receipt(
      id: 'minimal',
      title: 'Coffee',
      amount: 4.5,
      currency: 'AUD',
      purchaseDate: DateTime(2026, 1, 2),
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    );

    final restored =
        ReceiptSerializer.fromTurtle(ReceiptSerializer.toTurtle(original));

    expect(restored.title, 'Coffee');
    expect(restored.hasAttachment, isFalse);
    expect(restored.hasWarranty, isFalse);
    expect(restored.categories, isEmpty);
    expect(restored.flags, isEmpty);
  });

  test('throws on a Turtle document without a payload', () {
    expect(
      () => ReceiptSerializer.fromTurtle('@prefix x: <#> .\nx:a x:b "c" .'),
      throwsFormatException,
    );
  });
}
