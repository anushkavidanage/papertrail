/// Calendar-month ranges for bucketing receipts in charts.
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

/// The `[start, end)` calendar months from the month containing [from] up to
/// and including the month containing [now], oldest first.
///
/// Starting from the month that holds [from], rather than counting back a
/// fixed number of months, means every receipt dated in `[from, now]` falls
/// in exactly one range. The first range may then be a partial month.
///
/// When the span is longer than [maxMonths], only the most recent
/// [maxMonths] are returned. Returns an empty list when [from] is after
/// [now].
List<(DateTime start, DateTime end)> monthRanges({
  required DateTime from,
  required DateTime now,
  int? maxMonths,
}) {
  var count = (now.year - from.year) * 12 + (now.month - from.month) + 1;
  if (count <= 0) return [];
  if (maxMonths != null && count > maxMonths) count = maxMonths;

  return List.generate(count, (i) {
    // DateTime normalises month overflow and underflow, e.g. month 0 is
    // December of the previous year.
    final start = DateTime(now.year, now.month - (count - 1 - i));
    final end = DateTime(start.year, start.month + 1);
    return (start, end);
  });
}

/// Whether [monthRanges] would drop months for this span at [maxMonths].
bool monthRangesTruncated({
  required DateTime from,
  required DateTime now,
  required int maxMonths,
}) => (now.year - from.year) * 12 + (now.month - from.month) + 1 > maxMonths;
