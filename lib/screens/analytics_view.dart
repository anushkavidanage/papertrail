/// Analytics tab: spending charts and statistics derived from stored receipts.
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

import 'dart:math' show max;

import 'package:flutter/material.dart';

import 'package:fl_chart/fl_chart.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../utils/formatting.dart';
import '../widgets/locked_backdrop.dart';

// ---------------------------------------------------------------------------
// Palette — cycled across chart segments and bars.
// ---------------------------------------------------------------------------

const List<Color> _palette = [
  Color(0xFFEF6E37),
  Color(0xFF4E92DF),
  Color(0xFF4CAF50),
  Color(0xFFAB47BC),
  Color(0xFFFFCA28),
  Color(0xFF26C6DA),
  Color(0xFFEF5350),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
  Color(0xFFF06292),
];

Color _color(int i) => _palette[i % _palette.length];

// ---------------------------------------------------------------------------
// Period
// ---------------------------------------------------------------------------

enum _Period {
  month('1M', 30),
  threeMonths('3M', 90),
  sixMonths('6M', 180),
  year('1Y', 365),
  allTime('All', 0);

  const _Period(this.label, this.days);
  final String label;
  final int days;
}

// ---------------------------------------------------------------------------
// Root view
// ---------------------------------------------------------------------------

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  _Period _period = _Period.threeMonths;

  Future<void> _refresh() =>
      ReceiptStore.instance.refresh(context, const LockedBackdrop());

  List<Receipt> _filter(List<Receipt> all) {
    if (_period == _Period.allTime) return all;
    final cutoff = DateTime.now().subtract(Duration(days: _period.days));
    return all.where((r) => r.purchaseDate.isAfter(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReceiptStore.instance,
      builder: (context, _) {
        final store = ReceiptStore.instance;
        final receipts = _filter(store.receipts);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _PeriodSelector(
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              const SizedBox(height: 20),
              if (receipts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: Center(
                    child: Text(
                      'No receipts in this period.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              else ...[
                _SummaryRow(receipts: receipts),
                const SizedBox(height: 24),
                _CategoryDonut(receipts: receipts),
                const SizedBox(height: 24),
                _CategoryTrend(receipts: receipts, period: _period),
                const SizedBox(height: 24),
                _MonthlyBars(receipts: receipts, period: _period),
                const SizedBox(height: 24),
                _TopVendors(
                  receipts: receipts,
                  allReceipts: store.receipts,
                  period: _period,
                ),
                const SizedBox(height: 24),
                _UpcomingWarranties(
                  receipts: store.receipts,
                ), // always the full list
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Period selector
// ---------------------------------------------------------------------------

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChanged});

  final _Period selected;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _Period.values.map((p) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Center(child: Text(p.label)),
              selected: p == selected,
              onSelected: (_) => onChanged(p),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary stat cards
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final total = receipts.fold(0.0, (s, r) => s + r.amount);
    final count = receipts.length;
    final avg = count > 0 ? total / count : 0.0;
    final largest = receipts.isEmpty
        ? 0.0
        : receipts.map((r) => r.amount).reduce(max);
    final currency = _dominantCurrency(receipts);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _StatCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Total Spent',
          value: formatMoney(total, currency),
        ),
        _StatCard(
          icon: Icons.receipt_long_outlined,
          label: 'Receipts',
          value: '$count',
        ),
        _StatCard(
          icon: Icons.bar_chart_outlined,
          label: 'Avg per Receipt',
          value: formatMoney(avg, currency),
        ),
        _StatCard(
          icon: Icons.arrow_upward_outlined,
          label: 'Largest Purchase',
          value: formatMoney(largest, currency),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category spending — interactive donut chart
// ---------------------------------------------------------------------------

class _CategoryDonut extends StatefulWidget {
  const _CategoryDonut({required this.receipts});

  final List<Receipt> receipts;

  @override
  State<_CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<_CategoryDonut> {
  int? _touched;

  Map<String, double> get _totals {
    final map = <String, double>{};
    for (final r in widget.receipts) {
      final cats = r.categories.isEmpty
          ? const ['Uncategorised']
          : r.categories;
      for (final c in cats) {
        map[c] = (map[c] ?? 0) + r.amount;
      }
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    if (totals.isEmpty) return const SizedBox.shrink();

    final grandTotal = totals.values.fold(0.0, (a, b) => a + b);
    final keys = totals.keys.toList();
    final currency = _dominantCurrency(widget.receipts);

    final sections = List.generate(keys.length, (i) {
      final isTouched = _touched == i;
      final pct = grandTotal > 0 ? totals[keys[i]]! / grandTotal * 100 : 0.0;
      return PieChartSectionData(
        value: totals[keys[i]]!,
        color: _color(i),
        radius: isTouched ? 72.0 : 62.0,
        title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
        titleStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });

    return _Section(
      title: 'Spending by Category',
      subtitle: 'Tap a segment to highlight',
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 50,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response?.touchedSection == null) {
                        _touched = null;
                      } else {
                        _touched =
                            response!.touchedSection!.touchedSectionIndex;
                      }
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(keys.length, (i) {
              return Opacity(
                opacity: (_touched == null || _touched == i) ? 1.0 : 0.35,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _color(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${keys[i]}  ${formatMoney(totals[keys[i]]!, currency)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly spending — bar chart
// ---------------------------------------------------------------------------

class _MonthBucket {
  const _MonthBucket(this.month, this.total);
  final DateTime month;
  final double total;
}

/// The `[start, end)` calendar-month ranges covered by [period], oldest
/// first. Shared by every chart that buckets receipts by month.
List<(DateTime start, DateTime end)> _monthRanges(
  List<Receipt> receipts,
  _Period period,
) {
  final now = DateTime.now();
  int count;

  if (period == _Period.allTime) {
    if (receipts.isEmpty) return [];
    final oldest = receipts
        .map((r) => r.purchaseDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    count = (now.year - oldest.year) * 12 + (now.month - oldest.month) + 1;
    count = count.clamp(1, 24); // cap so the chart stays readable
  } else {
    count = switch (period) {
      _Period.month => 2,
      _Period.threeMonths => 3,
      _Period.sixMonths => 6,
      _Period.year => 12,
      _Period.allTime => 1, // unreachable
    };
  }

  return List.generate(count, (i) {
    final offset = count - 1 - i;
    int y = now.year;
    int m = now.month - offset;
    while (m <= 0) {
      m += 12;
      y--;
    }
    final start = DateTime(y, m);
    final end = m == 12 ? DateTime(y + 1, 1) : DateTime(y, m + 1);
    return (start, end);
  });
}

List<_MonthBucket> _buildMonthBuckets(List<Receipt> receipts, _Period period) {
  return _monthRanges(receipts, period).map((range) {
    final (start, end) = range;
    final total = receipts
        .where(
          (r) =>
              !r.purchaseDate.isBefore(start) && r.purchaseDate.isBefore(end),
        )
        .fold(0.0, (s, r) => s + r.amount);
    return _MonthBucket(start, total);
  }).toList();
}

const List<String> _monthAbbr = [
  '',
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

class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.receipts, required this.period});

  final List<Receipt> receipts;
  final _Period period;

  @override
  Widget build(BuildContext context) {
    final buckets = _buildMonthBuckets(receipts, period);
    if (buckets.isEmpty) return const SizedBox.shrink();

    final maxVal = buckets.map((b) => b.total).reduce(max);
    final chartMax = maxVal <= 0 ? 100.0 : maxVal * 1.25;
    final cs = Theme.of(context).colorScheme;
    final currency = _dominantCurrency(receipts);

    // Determine bar width based on count — narrower when many months.
    final barWidth = buckets.length <= 3
        ? 28.0
        : buckets.length <= 6
        ? 18.0
        : 10.0;

    return _Section(
      title: 'Monthly Trend',
      subtitle: 'Total spend per calendar month',
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: chartMax,
            barGroups: List.generate(
              buckets.length,
              (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].total,
                    color: cs.primary,
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 46,
                  getTitlesWidget: (value, meta) {
                    if (value == 0 || value == meta.max) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        _shortAmount(value),
                        style: Theme.of(context).textTheme.labelSmall,
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= buckets.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _monthAbbr[buckets[idx].month.month],
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: cs.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => cs.inverseSurface,
                getTooltipItem: (group, _, rod, unused) => BarTooltipItem(
                  '${_monthAbbr[buckets[group.x].month.month]}\n'
                  '${formatMoney(rod.toY, currency)}',
                  TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category spending trend — stacked monthly bars by category
// ---------------------------------------------------------------------------

class _CategoryMonthBucket {
  const _CategoryMonthBucket(this.month, this.totals);
  final DateTime month;

  /// Spend per entry in the trend's category labels list, same order.
  final List<double> totals;
}

class _CategoryTrend extends StatefulWidget {
  const _CategoryTrend({required this.receipts, required this.period});

  final List<Receipt> receipts;
  final _Period period;

  @override
  State<_CategoryTrend> createState() => _CategoryTrendState();
}

class _CategoryTrendState extends State<_CategoryTrend> {
  /// Categories beyond this rank are folded into a single "Other" series so
  /// the default (unfiltered) chart stays readable.
  static const _maxSeries = 4;
  static const _otherLabel = 'Other';

  /// The categories the user has chosen to show, or null to use the default
  /// top-[_maxSeries]-plus-"Other" view. Once set, this is the exact set of
  /// series drawn — no "Other" bucket.
  Set<String>? _selected;

  Map<String, double> get _categoryTotals {
    final totals = <String, double>{};
    for (final r in widget.receipts) {
      final cats = r.categories.isEmpty
          ? const ['Uncategorised']
          : r.categories;
      for (final c in cats) {
        totals[c] = (totals[c] ?? 0) + r.amount;
      }
    }
    return totals;
  }

  /// Every category present in the current period, ranked by spend.
  List<String> get _universe {
    final ranked = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.map((e) => e.key).toList();
  }

  List<String> _labelsFor(List<String> universe) {
    final selected = _selected;
    if (selected == null) {
      if (universe.length <= _maxSeries) return universe;
      return [...universe.take(_maxSeries), _otherLabel];
    }
    return universe.where(selected.contains).toList();
  }

  void _toggle(String category, List<String> universe) {
    setState(() {
      final next = Set<String>.from(_selected ?? universe.toSet());
      if (!next.remove(category)) next.add(category);
      _selected = next;
    });
  }

  List<_CategoryMonthBucket> _buildBuckets(List<String> labels) {
    final hasOther = _selected == null && labels.last == _otherLabel;
    return _monthRanges(widget.receipts, widget.period).map((range) {
      final (start, end) = range;
      final totals = List<double>.filled(labels.length, 0.0);
      for (final r in widget.receipts) {
        if (r.purchaseDate.isBefore(start) || !r.purchaseDate.isBefore(end)) {
          continue;
        }
        final cats = r.categories.isEmpty
            ? const ['Uncategorised']
            : r.categories;
        for (final c in cats) {
          final idx = labels.indexOf(c);
          if (idx != -1) {
            totals[idx] += r.amount;
          } else if (hasOther) {
            totals[labels.length - 1] += r.amount;
          }
        }
      }
      return _CategoryMonthBucket(start, totals);
    }).toList();
  }

  Color _seriesColor(BuildContext context, List<String> labels, int index) {
    if (labels[index] == _otherLabel) {
      return Theme.of(context).colorScheme.outlineVariant;
    }
    return _color(index);
  }

  Widget _buildChips(List<String> universe) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final category in universe)
          FilterChip(
            label: Text(category),
            selected: _selected == null || _selected!.contains(category),
            onSelected: (_) => _toggle(category, universe),
            visualDensity: VisualDensity.compact,
          ),
        if (_selected != null)
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: const Text('Reset'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final universe = _universe;
    if (universe.isEmpty) return const SizedBox.shrink();

    final labels = _labelsFor(universe);
    final subtitle = _selected == null
        ? 'Monthly spend split by category'
        : labels.isEmpty
        ? 'No categories selected'
        : '${labels.length} of ${universe.length} categories shown';

    return _Section(
      title: 'Category Trend',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChips(universe),
          const SizedBox(height: 16),
          if (labels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Select at least one category to see its trend.'),
              ),
            )
          else
            _CategoryTrendChart(
              receipts: widget.receipts,
              labels: labels,
              buckets: _buildBuckets(labels),
              seriesColor: (i) => _seriesColor(context, labels, i),
            ),
        ],
      ),
    );
  }
}

class _CategoryTrendChart extends StatelessWidget {
  const _CategoryTrendChart({
    required this.receipts,
    required this.labels,
    required this.buckets,
    required this.seriesColor,
  });

  final List<Receipt> receipts;
  final List<String> labels;
  final List<_CategoryMonthBucket> buckets;
  final Color Function(int index) seriesColor;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();

    final maxVal = buckets
        .map((b) => b.totals.fold(0.0, (a, b) => a + b))
        .reduce(max);
    final chartMax = maxVal <= 0 ? 100.0 : maxVal * 1.25;
    final currency = _dominantCurrency(receipts);

    final barWidth = buckets.length <= 3
        ? 28.0
        : buckets.length <= 6
        ? 18.0
        : 10.0;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              barGroups: List.generate(buckets.length, (i) {
                var cumulative = 0.0;
                final stackItems = List.generate(labels.length, (j) {
                  final from = cumulative;
                  cumulative += buckets[i].totals[j];
                  return BarChartRodStackItem(from, cumulative, seriesColor(j));
                });
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: cumulative,
                      rodStackItems: stackItems,
                      width: barWidth,
                    ),
                  ],
                );
              }),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    getTitlesWidget: (value, meta) {
                      if (value == 0 || value == meta.max) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          _shortAmount(value),
                          style: Theme.of(context).textTheme.labelSmall,
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _monthAbbr[buckets[idx].month.month],
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      Theme.of(context).colorScheme.inverseSurface,
                  getTooltipItem: (group, _, rod, unused) {
                    final bucket = buckets[group.x];
                    final lines = [
                      '${_monthAbbr[bucket.month.month]} ${bucket.month.year}',
                      for (var j = 0; j < labels.length; j++)
                        if (bucket.totals[j] > 0)
                          '${labels[j]}: ${formatMoney(bucket.totals[j], currency)}',
                    ];
                    return BarTooltipItem(
                      lines.join('\n'),
                      TextStyle(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: List.generate(labels.length, (i) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: seriesColor(i),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top vendors
// ---------------------------------------------------------------------------

class _TopVendors extends StatelessWidget {
  const _TopVendors({
    required this.receipts,
    required this.allReceipts,
    required this.period,
  });

  final List<Receipt> receipts;

  /// The full, unfiltered receipt history — used to tell whether a vendor's
  /// first-ever purchase falls inside the selected period ("New").
  final List<Receipt> allReceipts;
  final _Period period;

  bool _isNewVendor(String vendor, DateTime periodStart) {
    final purchaseDates = allReceipts
        .where((r) => r.vendor.trim() == vendor)
        .map((r) => r.purchaseDate);
    if (purchaseDates.isEmpty) return false;
    final firstEver = purchaseDates.reduce((a, b) => a.isBefore(b) ? a : b);
    return !firstEver.isBefore(periodStart);
  }

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    final visits = <String, int>{};
    for (final r in receipts) {
      final v = r.vendor.trim();
      if (v.isEmpty) continue;
      totals[v] = (totals[v] ?? 0) + r.amount;
      visits[v] = (visits[v] ?? 0) + 1;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final maxAmount = top.first.value;
    final currency = _dominantCurrency(receipts);
    final cs = Theme.of(context).colorScheme;

    final periodStart = period == _Period.allTime
        ? null
        : DateTime.now().subtract(Duration(days: period.days));

    return _Section(
      title: 'Top Vendors',
      subtitle: 'Up to 5 vendors by total spend, with visit frequency',
      child: Column(
        children: List.generate(top.length, (i) {
          final vendor = top[i].key;
          final amount = top[i].value;
          final visitCount = visits[vendor] ?? 1;
          final avg = amount / visitCount;
          final frac = maxAmount > 0 ? amount / maxAmount : 0.0;
          final isNew =
              periodStart != null && _isNewVendor(vendor, periodStart);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    vendor,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isNew) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'New',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(amount, currency),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$visitCount visit${visitCount == 1 ? '' : 's'} · '
                        'avg ${formatMoney(avg, currency)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: frac,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: _color(i),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming warranty expirations
// ---------------------------------------------------------------------------

class _UpcomingWarranties extends StatelessWidget {
  const _UpcomingWarranties({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final expiring = receipts.where((r) {
      if (!r.hasWarranty || r.warrantyExpiry == null) return false;
      final days = r.warrantyDaysRemaining;
      return days != null && days >= 0 && days <= 90;
    }).toList()..sort((a, b) => a.warrantyExpiry!.compareTo(b.warrantyExpiry!));

    if (expiring.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return _Section(
      title: 'Warranties Expiring Soon',
      subtitle: 'Receipts whose warranty expires within 90 days',
      child: Column(
        children: expiring.map((r) {
          final days = r.warrantyDaysRemaining!;
          final urgent = days <= 14;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.verified_user_outlined,
              color: urgent ? cs.error : cs.primary,
            ),
            title: Text(r.title, style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(
              'Expires ${formatDate(r.warrantyExpiry!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: urgent ? cs.error : cs.onSurfaceVariant,
              ),
            ),
            trailing: Text(
              relativeDay(r.warrantyExpiry!),
              style: TextStyle(
                fontSize: 12,
                color: urgent ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card wrapper for each analytics section
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The most frequently used currency in [receipts].
String _dominantCurrency(List<Receipt> receipts) {
  if (receipts.isEmpty) return 'AUD';
  final freq = <String, int>{};
  for (final r in receipts) {
    freq[r.currency] = (freq[r.currency] ?? 0) + 1;
  }
  return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// Compact axis label: 1200 → "1.2k", 15000 → "15k", 500 → "500".
String _shortAmount(double v) {
  if (v >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}
