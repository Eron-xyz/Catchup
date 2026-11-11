import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dashboard module:
/// - Greeting: "Good day, {FullName}!" with a short subtitle + compact Product Movement Breakdown on the right
/// - Four summary metrics separated by thin hairline dividers (no generic card boxes)
/// - Stock Overview line chart: incoming vs outgoing, with a rounded pill range dropdown (Last 7 Days, Last 30 Days)
/// - Stock by Category donut chart with percentages
/// - Alerts & Notifications list (paginated to 10 max)
/// - Recent Transactions (paginated to 4 per page with CatchUpPaginationBar)
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedRangeDays = 7; // 7 or 30
  int _txPage = 0;
  static const int _pageSize = 4;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    if (productsAsync.isLoading || transactionsAsync.isLoading) {
      return const CatchUpModuleSkeleton();
    }

    final user = ref.watch(currentUserProfileProvider).value;
    final activeProducts = ref.watch(activeProductsProvider);
    final stockMap = ref.watch(calculatedStockMapProvider);
    final allTransactions = transactionsAsync.value ?? [];
    final allWaste = ref.watch(wasteRecordsStreamProvider).value ?? [];
    final alerts = ref.watch(systemAlertsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final fullName = (user?.fullName.isNotEmpty == true)
        ? user!.fullName
        : 'Team Member';

    double totalStock = 0.0;
    int lowStockCount = 0;
    int fastMovingCount = 0;
    int slowMovingCount = 0;

    for (final p in activeProducts) {
      final s = stockMap[p.productId] ?? p.currentStock;
      if (p.unit == 'kg') totalStock += s;
      if (p.unit == 'g') totalStock += s / 1000;
      if (s <= p.minimumStock) {
        lowStockCount++;
      }
      if (p.productMovement == 'Fast Moving') {
        fastMovingCount++;
      } else {
        slowMovingCount++;
      }
    }

    final now = DateTime.now();
    double totalWasteThisMonth = 0.0;
    for (final w in allWaste) {
      if (!w.isVoided &&
          w.wasteDateTime.year == now.year &&
          w.wasteDateTime.month == now.month) {
        totalWasteThisMonth += w.quantity;
      }
    }

    final validTransactions = allTransactions
        .where((t) => !t.isVoided && !t.isReversal)
        .toList();
    final isMobileScreen = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobileScreen ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Row: Greeting on Left + Small, Compact Product Movement Breakdown on Right
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Good day, $fullName!',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobileScreen ? 21 : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here is your Roxas City seafood inventory overview and real-time stock status.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                // Small, compact non-stretched Product Movement Breakdown
                _CompactMovementBreakdown(
                  fastMovingCount: fastMovingCount,
                  slowMovingCount: slowMovingCount,
                  borderColor: borderColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 50/50 Design: One Unified Curved Card Box with Thin Internal Hairline Dividers for the 4 KPIs
          Card(
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _SummaryCard(
                    title: 'Total Stock (kg)',
                    value: AppFormatters.formatNumber(totalStock),
                    subtitle: 'Total stock on hand',
                    icon: Icons.scale_outlined,
                    color: AppColors.sidebarActiveBlue,
                  ),
                  _SummaryCard(
                    title: 'Total Products',
                    value: '${activeProducts.length}',
                    subtitle: 'Active seafood items',
                    icon: Icons.view_in_ar_outlined,
                    color: AppColors.oceanTeal,
                  ),
                  _SummaryCard(
                    title: 'Low Stock Items',
                    value: '$lowStockCount',
                    subtitle: (user?.canManageInventory ?? true)
                        ? 'Tap to view low-stock list'
                        : 'Items at or below minimum stock',
                    icon: Icons.warning_amber_rounded,
                    color: lowStockCount > 0
                        ? AppColors.statusOrange
                        : AppColors.statusGreen,
                    onTap: (user?.canManageInventory ?? true)
                        ? () => context.go('/inventory?lowStock=true')
                        : null,
                  ),
                  _SummaryCard(
                    title: 'Total Waste (This Month)',
                    value: AppFormatters.formatNumber(totalWasteThisMonth),
                    subtitle: 'Spoiled / damaged this month',
                    icon: Icons.delete_outline,
                    color: AppColors.statusRed,
                  ),
                ];

                if (constraints.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: borderColor, width: 1),
                            ),
                          ),
                          child: cards[0],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: borderColor, width: 1),
                            ),
                          ),
                          child: cards[1],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: borderColor, width: 1),
                            ),
                          ),
                          child: cards[2],
                        ),
                      ),
                      Expanded(child: cards[3]),
                    ],
                  );
                } else if (constraints.maxWidth >= 520) {
                  return Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: borderColor, width: 1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: borderColor,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: cards[0],
                              ),
                            ),
                            Expanded(child: cards[1]),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: borderColor,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: cards[2],
                            ),
                          ),
                          Expanded(child: cards[3]),
                        ],
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < cards.length; i++)
                      Container(
                        decoration: i < cards.length - 1
                            ? BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: borderColor,
                                    width: 1,
                                  ),
                                ),
                              )
                            : null,
                        child: cards[i],
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Charts Row: Curved Cards with Thin Internal Header Lines + Animated Charts
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final lineChart = RepaintBoundary(
                child: _StockOverviewLineChartCard(
                  transactions: validTransactions,
                  rangeDays: _selectedRangeDays,
                  onRangeChanged: (days) =>
                      setState(() => _selectedRangeDays = days),
                ),
              );
              final donutChart = RepaintBoundary(
                child: _StockByCategoryDonutCard(
                  products: activeProducts,
                  stockMap: stockMap,
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: lineChart),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: donutChart),
                  ],
                );
              }
              return Column(
                children: [lineChart, const SizedBox(height: 16), donutChart],
              );
            },
          ),
          const SizedBox(height: 16),

          // Bottom Row: Curved Cards with Thin Internal Dividers for Alerts & Recent Transactions (4 per page)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final alertsCard = _AlertsListCard(
                alerts: alerts,
                canNavigate: (route) => user?.canAccessRoute(route) ?? true,
              );
              final recentTxCard = _RecentTransactionsCard(
                allTransactions: allTransactions,
                currentPage: _txPage,
                pageSize: _pageSize,
                onPageChanged: (p) => setState(() => _txPage = p),
                showViewAll: user?.canManageTransactions ?? true,
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: alertsCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: recentTxCard),
                  ],
                );
              }
              return Column(
                children: [
                  alertsCard,
                  const SizedBox(height: 16),
                  recentTxCard,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CompactMovementBreakdown extends StatelessWidget {
  final int fastMovingCount;
  final int slowMovingCount;
  final Color borderColor;

  const _CompactMovementBreakdown({
    required this.fastMovingCount,
    required this.slowMovingCount,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.speed_outlined,
            size: 16,
            color: AppColors.oceanTeal,
          ),
          const SizedBox(width: 6),
          const Text(
            'Movement:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.oceanTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Fast $fastMovingCount',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.oceanTeal,
            ),
          ),
          Container(
            height: 12,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: borderColor,
          ),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.sidebarActiveBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Slow $slowMovingCount',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.sidebarActiveBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: onTap != null
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.secondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _StockOverviewLineChartCard extends StatelessWidget {
  final List<StockTransaction> transactions;
  final int rangeDays;
  final ValueChanged<int> onRangeChanged;

  const _StockOverviewLineChartCard({
    required this.transactions,
    required this.rangeDays,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: rangeDays - 1));

    final Map<int, double> incomingByDay = {
      for (int i = 0; i < rangeDays; i++) i: 0.0,
    };
    final Map<int, double> outgoingByDay = {
      for (int i = 0; i < rangeDays; i++) i: 0.0,
    };

    bool hasAnyDataInPeriod = false;
    for (final tx in transactions) {
      final txDay = DateTime(
        tx.dateTime.year,
        tx.dateTime.month,
        tx.dateTime.day,
      );
      final diff = txDay.difference(startDate).inDays;
      if (diff >= 0 && diff < rangeDays) {
        hasAnyDataInPeriod = true;
        if (tx.isIncoming) {
          incomingByDay[diff] = (incomingByDay[diff] ?? 0) + tx.quantity;
        } else {
          outgoingByDay[diff] = (outgoingByDay[diff] ?? 0) + tx.quantity;
        }
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stock Overview (Incoming vs Outgoing)',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppColors.statusGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Incoming',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppColors.statusOrange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Outgoing',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 155,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: rangeDays,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child: Text(
                            'Last 7 Days',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text(
                            'Last 30 Days',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) onRangeChanged(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 230,
              child: !hasAnyDataInPeriod
                  ? Center(
                      child: Text(
                        'No data yet. Record your first transaction to see the chart.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.blueGrey.shade500),
                      ),
                    )
                  : TweenAnimationBuilder<double>(
                      key: ValueKey('stock_overview_$rangeDays'),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) {
                        return LineChart(
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOutCubic,
                          LineChartData(
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => Colors.transparent,
                                tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                tooltipMargin: 8,
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final isIncoming = spot.barIndex == 0;
                                    return LineTooltipItem(
                                      AppFormatters.formatNumber(spot.y),
                                      TextStyle(
                                        color: isIncoming
                                            ? AppColors.statusGreen
                                            : AppColors.statusOrange,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: const FlGridData(show: true),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: rangeDays == 7 ? 1 : 5,
                                  getTitlesWidget: (val, _) {
                                    final d = startDate.add(
                                      Duration(days: val.toInt()),
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '${d.month}/${d.day}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: [
                                  for (int i = 0; i < rangeDays; i++)
                                    FlSpot(
                                      i.toDouble(),
                                      (incomingByDay[i] ?? 0) * progress,
                                    ),
                                ],
                                isCurved: true,
                                color: AppColors.statusGreen,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(show: false),
                              ),
                              LineChartBarData(
                                spots: [
                                  for (int i = 0; i < rangeDays; i++)
                                    FlSpot(
                                      i.toDouble(),
                                      (outgoingByDay[i] ?? 0) * progress,
                                    ),
                                ],
                                isCurved: true,
                                color: AppColors.statusOrange,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockByCategoryDonutCard extends StatefulWidget {
  final List<Product> products;
  final Map<String, double> stockMap;

  const _StockByCategoryDonutCard({
    required this.products,
    required this.stockMap,
  });

  static const List<Color> _palette = [
    AppColors.sidebarNavy,
    AppColors.sidebarActiveBlue,
    AppColors.oceanTeal,
    AppColors.oceanWaveLight,
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
    Color(0xFF42A5F5),
    Color(0xFF00ACC1),
  ];

  @override
  State<_StockByCategoryDonutCard> createState() =>
      _StockByCategoryDonutCardState();
}

class _StockByCategoryDonutCardState extends State<_StockByCategoryDonutCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final Map<String, double> categoryStock = {};
    double totalStock = 0.0;

    for (final p in widget.products) {
      final s = widget.stockMap[p.productId] ?? p.currentStock;
      if (s > 0) {
        categoryStock[p.category] = (categoryStock[p.category] ?? 0) + s;
        totalStock += s;
      }
    }

    final entries = categoryStock.entries.toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Text(
                'Stock by Category',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (totalStock <= 0) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        'No data yet. Record your first transaction to see the chart.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.blueGrey.shade500),
                      ),
                    ),
                  );
                }

                final isCompact = constraints.maxWidth < 360;
                final pieWidget = TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.92, end: 1.0),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  builder: (context, scaleVal, child) {
                    return Transform.scale(scale: scaleVal, child: child);
                  },
                  child: SizedBox(
                    height: isCompact ? 195 : 230,
                    child: PieChart(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOutCubic,
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = pieTouchResponse
                                  .touchedSection!
                                  .touchedSectionIndex;
                            });
                          },
                        ),
                        centerSpaceRadius: isCompact ? 30 : 36,
                        sectionsSpace: 2.5,
                        sections: List.generate(entries.length, (i) {
                          final e = entries[i];
                          final pct = (e.value / totalStock) * 100;
                          final isTouched = i == _touchedIndex;
                          final baseRadius = isCompact ? 46.0 : 54.0;
                          return PieChartSectionData(
                            color:
                                _StockByCategoryDonutCard._palette[i %
                                    _StockByCategoryDonutCard._palette.length],
                            value: e.value,
                            title: '${pct.toStringAsFixed(0)}%',
                            radius: isTouched ? baseRadius + 9.0 : baseRadius,
                            titleStyle: TextStyle(
                              color: Colors.white,
                              fontSize: isTouched ? 12.5 : 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                );

                final legendItems = List.generate(entries.length, (i) {
                  final e = entries[i];
                  final pct = (e.value / totalStock) * 100;
                  final isTouched = i == _touchedIndex;
                  final color = _StockByCategoryDonutCard
                      ._palette[i % _StockByCategoryDonutCard._palette.length];
                  return MouseRegion(
                    onEnter: (_) => setState(() => _touchedIndex = i),
                    onExit: (_) => setState(() => _touchedIndex = -1),
                    child: AnimatedScale(
                      scale: isTouched ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 80),
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: isTouched ? 12 : 10,
                              height: isTouched ? 12 : 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${e.key} (${pct.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isTouched
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                });

                if (isCompact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      pieWidget,
                      const SizedBox(height: 12),
                      Wrap(spacing: 14, runSpacing: 4, children: legendItems),
                    ],
                  );
                }

                return SizedBox(
                  height: 230,
                  child: Row(
                    children: [
                      Expanded(child: pieWidget),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: legendItems,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsListCard extends StatelessWidget {
  final List<SystemAlert> alerts;
  final bool Function(String route) canNavigate;

  const _AlertsListCard({
    required this.alerts,
    required this.canNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final shownAlerts = alerts.take(10).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.statusOrange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Alerts & Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (shownAlerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'No active alerts. Stock levels and storage conditions are normal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey.shade500),
                ),
              )
            else
              for (int i = 0; i < shownAlerts.length; i++)
                Container(
                  decoration: i < shownAlerts.length - 1
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: borderColor, width: 1),
                          ),
                        )
                      : null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: canNavigate(shownAlerts[i].route)
                        ? () => context.go(shownAlerts[i].route)
                        : null,
                    leading: Icon(
                      shownAlerts[i].isCritical
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      color: shownAlerts[i].isCritical
                          ? AppColors.statusRed
                          : AppColors.statusOrange,
                    ),
                    title: Text(
                      shownAlerts[i].title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      shownAlerts[i].subtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RecentTransactionsCard extends StatelessWidget {
  final List<StockTransaction> allTransactions;
  final int currentPage;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final bool showViewAll;

  const _RecentTransactionsCard({
    required this.allTransactions,
    required this.currentPage,
    required this.pageSize,
    required this.onPageChanged,
    this.showViewAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final totalPages = (allTransactions.length / pageSize).ceil();
    final safePage = totalPages == 0 ? 0 : currentPage.clamp(0, totalPages - 1);
    final paged = allTransactions
        .skip(safePage * pageSize)
        .take(pageSize)
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (showViewAll)
                  TextButton(
                    onPressed: () => context.go('/transactions'),
                    child: const Text('View All'),
                  ),
              ],
            ),
          ),
          if (paged.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              child: Text(
                'No transactions recorded yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade500),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  for (int i = 0; i < paged.length; i++)
                    Container(
                      decoration: i < paged.length - 1
                          ? BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: borderColor,
                                  width: 1,
                                ),
                              ),
                            )
                          : null,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: StatusBadge(
                          label: paged[i].type,
                          color: paged[i].isIncoming
                              ? AppColors.statusGreen
                              : AppColors.statusOrange,
                        ),
                        title: Text(
                          '${paged[i].transactionId} | ${paged[i].productName} (${AppFormatters.formatNumber(paged[i].quantity)} ${paged[i].unit})',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: paged[i].isVoided
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          '${AppFormatters.formatDateTime(paged[i].dateTime)} | ${paged[i].storageName} | By: ${paged[i].recordedBy}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          CatchUpPaginationBar(
            currentPage: safePage,
            totalItems: allTransactions.length,
            pageSize: pageSize,
            onPageChanged: onPageChanged,
          ),
        ],
      ),
    );
  }
}
