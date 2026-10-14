// Unit tests for the calendar-month ranges the analytics charts bucket by.

import 'package:flutter_test/flutter_test.dart';

import 'package:papertrail/utils/month_ranges.dart';

/// How many of [ranges] hold [date].
int _hits(List<(DateTime, DateTime)> ranges, DateTime date) =>
    ranges.where((r) => !date.isBefore(r.$1) && date.isBefore(r.$2)).length;

void main() {
  final now = DateTime(2026, 10, 12, 15, 30);

  group('monthRanges', () {
    test('starts at the month holding a mid-month period start', () {
      // The 3M period (90 days back) starts on 14 Jul. Counting back three
      // whole months would begin at August and drop 14-31 Jul.
      final from = now.subtract(const Duration(days: 90));
      final ranges = monthRanges(from: from, now: now);

      expect(ranges.map((r) => r.$1), [
        DateTime(2026, 7),
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      expect(_hits(ranges, DateTime(2026, 7, 20)), 1);
    });

    test('puts every day of the period in exactly one range', () {
      for (final days in [30, 90, 180, 365]) {
        final from = now.subtract(Duration(days: days));
        final ranges = monthRanges(from: from, now: now);
        for (
          var d = from;
          !d.isAfter(now);
          d = d.add(const Duration(days: 1))
        ) {
          expect(_hits(ranges, d), 1, reason: '$days-day period, $d');
        }
        expect(_hits(ranges, now), 1);
      }
    });

    test('crosses a year boundary with consecutive months', () {
      final ranges = monthRanges(from: DateTime(2025, 11, 20), now: now);
      expect(ranges.first, (DateTime(2025, 11), DateTime(2025, 12)));
      expect(ranges[1], (DateTime(2025, 12), DateTime(2026, 1)));
      expect(ranges.last, (DateTime(2026, 10), DateTime(2026, 11)));
      expect(ranges, hasLength(12));
    });

    test('a start in the current month gives a single range', () {
      expect(monthRanges(from: DateTime(2026, 10, 1), now: now), [
        (DateTime(2026, 10), DateTime(2026, 11)),
      ]);
    });

    test('caps to the most recent months and reports the cap', () {
      final from = DateTime(2020, 3, 5);
      final ranges = monthRanges(from: from, now: now, maxMonths: 24);

      expect(ranges, hasLength(24));
      expect(ranges.first.$1, DateTime(2024, 11));
      expect(ranges.last.$1, DateTime(2026, 10));
      expect(monthRangesTruncated(from: from, now: now, maxMonths: 24), isTrue);
      expect(
        monthRangesTruncated(
          from: DateTime(2025, 1, 1),
          now: now,
          maxMonths: 24,
        ),
        isFalse,
      );
    });

    test('is empty when the start is after now', () {
      expect(monthRanges(from: DateTime(2026, 11, 2), now: now), isEmpty);
    });
  });
}
