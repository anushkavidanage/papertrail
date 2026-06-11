/// Lightweight formatting helpers (kept dependency-free).
library;

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
