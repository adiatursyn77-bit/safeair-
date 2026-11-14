import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/leak_event.dart';
import '../services/firestore_service.dart';
import '../utils/duration_format.dart';

/// Экран статистики по одной плате: сводные цифры + столбчатый график
/// числа утечек по месяцам за последние полгода.
class DeviceStatsScreen extends StatelessWidget {
  final String deviceId;
  final String deviceName;

  const DeviceStatsScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  static const _monthLabelsRu = [
    'Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
    'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек',
  ];
  static const _monthLabelsKk = [
    'Қаң', 'Ақп', 'Нау', 'Сәу', 'Мам', 'Мау',
    'Шіл', 'Там', 'Қыр', 'Қаз', 'Қар', 'Жел',
  ];
  static const _monthLabelsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<String> _monthLabels(String languageCode) {
    switch (languageCode) {
      case 'kk':
        return _monthLabelsKk;
      case 'en':
        return _monthLabelsEn;
      default:
        return _monthLabelsRu;
    }
  }

  List<_MonthBucket> _lastSixMonths(DateTime now) {
    return List.generate(6, (i) {
      final monthsAgo = 5 - i;
      final date = DateTime(now.year, now.month - monthsAgo, 1);
      return _MonthBucket(year: date.year, month: date.month, count: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firestoreService = FirestoreService();
    final lang = context.locale.languageCode;
    final monthLabels = _monthLabels(lang);

    return Scaffold(
      appBar: AppBar(
        title: Text('stats.title'.tr(args: [deviceName])),
      ),
      body: StreamBuilder<List<LeakEvent>>(
        stream: firestoreService.streamEvents(deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('deviceDetail.error'.tr(args: ['${snapshot.error}'])));
          }

          final events = snapshot.data ?? [];

          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded,
                      size: 48, color: colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    'stats.noData'.tr(),
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          final now = DateTime.now();
          final buckets = _lastSixMonths(now);

          for (final event in events) {
            for (final bucket in buckets) {
              if (event.startedAt.year == bucket.year &&
                  event.startedAt.month == bucket.month) {
                bucket.count++;
                break;
              }
            }
          }

          final resolvedDurations = events
              .where((e) => e.durationSec != null)
              .map((e) => e.durationSec!)
              .toList();

          final totalLeaks = events.length;
          final avgDuration = resolvedDurations.isEmpty
              ? 0
              : resolvedDurations.reduce((a, b) => a + b) ~/
                  resolvedDurations.length;
          final maxDuration = resolvedDurations.isEmpty
              ? 0
              : resolvedDurations.reduce((a, b) => a > b ? a : b);

          final maxCount = buckets
              .map((b) => b.count)
              .fold<int>(1, (a, b) => a > b ? a : b);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.local_fire_department_rounded,
                      label: 'stats.totalLeaks'.tr(),
                      value: '$totalLeaks',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.timer_rounded,
                      label: 'stats.avgDuration'.tr(),
                      value: resolvedDurations.isEmpty
                          ? '—'
                          : formatShortDuration(lang, avgDuration),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.trending_up_rounded,
                label: 'stats.longestDuration'.tr(),
                value: resolvedDurations.isEmpty
                    ? '—'
                    : formatShortDuration(lang, maxDuration),
                fullWidth: true,
              ),
              const SizedBox(height: 24),
              Text(
                'stats.monthlyChart'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                  child: SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        maxY: (maxCount + 1).toDouble(),
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= buckets.length) {
                                  return const SizedBox.shrink();
                                }
                                final bucket = buckets[index];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    monthLabels[bucket.month - 1],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        barGroups: [
                          for (var i = 0; i < buckets.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: buckets[i].count.toDouble(),
                                  color: colorScheme.primary,
                                  width: 22,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'stats.eventsFooter'.tr(args: ['${events.length}']),
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthBucket {
  final int year;
  final int month;
  int count;

  _MonthBucket({required this.year, required this.month, required this.count});
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
