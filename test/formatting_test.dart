// Unit tests for the display and filename formatting helpers.

import 'package:flutter_test/flutter_test.dart';

import 'package:papertrail/utils/formatting.dart';

void main() {
  group('attachmentFileName', () {
    test('slugifies the receipt title', () {
      expect(attachmentFileName('Logi Presenter', 'jpg'), 'logi-presenter.jpg');
    });

    test('collapses runs of punctuation and trims the edges', () {
      expect(attachmentFileName('Fruit & Veg!!', 'pdf'), 'fruit-veg.pdf');
      expect(attachmentFileName('--Coles--', 'png'), 'coles.png');
    });

    test('falls back to "receipt" when nothing usable is left', () {
      expect(attachmentFileName('   ', 'png'), 'receipt.png');
      expect(attachmentFileName('!!!', 'jpg'), 'receipt.jpg');
    });

    test('drops characters that are unsafe in a filename', () {
      // The accented letter and the slash both go, so the name stays safe on
      // every platform rather than creating a nested path.
      expect(attachmentFileName('Café/Bar', 'jpg'), 'caf-bar.jpg');
    });
  });
}
