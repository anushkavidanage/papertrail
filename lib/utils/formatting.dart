/// Lightweight formatting helpers (kept dependency-free).
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

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Format a date as e.g. "9 Jun 2026".
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Format an amount with a currency code, e.g. "AUD 12.50".
String formatMoney(double amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

/// Human friendly description of how far away [date] is from today.
String relativeDay(DateTime date) {
  final today = DateTime.now();
  final d0 = DateTime(today.year, today.month, today.day);
  final d1 = DateTime(date.year, date.month, date.day);
  final days = d1.difference(d0).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  if (days > 1) return 'in $days days';
  return '${-days} days ago';
}
