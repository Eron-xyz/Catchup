import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/export_service.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/models/waste_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The six reports available (Admin and Manager only).
enum ReportType {
  currentStock('Current Stock'),
  lowStock('Low Stock / Reorder'),
  transactions('Stock Transactions'),
  waste('Waste'),
  movement('Fast vs Slow Moving'),
  deliveries('Supplier Deliveries');

  final String label;
  const ReportType(this.label);
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportType _type = ReportType.currentStock;
  late DateTimeRange _range;
  String _txType = 'All'; // transactions report
  String _productId = 'All'; // transactions + waste reports
  String _reason = 'All'; // waste report
  bool _busy = false;
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 29)),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  DateTime get _from => _range.start;
  DateTime get _to => _range.end.add(const Duration(days: 1));

  bool _inRange(DateTime d) => !d.isBefore(_from) && d.isBefore(_to);

  Future<void> _pickRange() async {
    final picked = await CatchUpCompactDateRangeDialog.show(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _currentPage = 0;
      });
    }
  }

  /// Builds the table for the selected report from the live data.
  TableData _build() {
    final products = ref.watch(productsStreamProvider).value ?? [];
    final stock = ref.watch(calculatedStockMapProvider);
    final txs = ref.watch(transactionsStreamProvider).value ?? [];
    final waste = ref.watch(wasteRecordsStreamProvider).value ?? [];
    double stockOf(String id) => stock[id] ?? 0;

    switch (_type) {
      case ReportType.currentStock:
        return TableData(
          title: 'Current Stock Report',
          headers: [
            'ProductID',
            'Name',
            'Category',
            'Stock',
            'Unit',
            'Status',
            'Value (PHP)'
          ],
          rows: products.where((p) => p.isActive).map((p) {
            final s = stockOf(p.productId);
            final status = s <= 0
                ? 'Out of stock'
                : (s <= p.minimumStock ? 'Low' : 'OK');
            return [
              p.productId,
              p.productName,
              p.category,
              AppFormatters.formatNumber(s),
              p.unit,
              status,
              AppFormatters.formatCurrency(s * p.price),
            ];
          }).toList(),
        );

      case ReportType.lowStock:
        return TableData(
          title: 'Low Stock / Reorder Report',
          headers: [
            'ProductID',
            'Name',
            'Stock',
            'Minimum',
            'Reorder Point',
            'Unit',
            'Action'
          ],
          rows: products
              .where(
                  (p) => p.isActive && stockOf(p.productId) <= p.reorderPoint)
              .map((p) {
            final s = stockOf(p.productId);
            final action = s <= 0
                ? 'Out of stock - reorder now'
                : (s <= p.minimumStock ? 'Below minimum' : 'Reorder soon');
            return [
              p.productId,
              p.productName,
              AppFormatters.formatNumber(s),
              AppFormatters.formatNumber(p.minimumStock),
              AppFormatters.formatNumber(p.reorderPoint),
              p.unit,
              action,
            ];
          }).toList(),
        );

      case ReportType.transactions:
        return TableData(
          title: 'Stock Transactions Report',
          headers: [
            'ID',
            'Date / Time',
            'Type',
            'Product',
            'Quantity',
            'Supplier',
            'Storage',
            'Recorded By',
            'Status'
          ],
          rows: txs
              .where((t) =>
                  _inRange(t.dateTime) &&
                  (_txType == 'All' || t.type == _txType) &&
                  (_productId == 'All' || t.productId == _productId))
              .map((t) => [
                    t.transactionId,
                    AppFormatters.formatDateTime(t.dateTime),
                    t.type,
                    t.productName,
                    '${AppFormatters.formatNumber(t.quantity)} ${t.unit}',
                    t.supplierName ?? '-',
                    t.storageName,
                    t.recordedBy,
                    t.isVoided ? 'Voided' : (t.isReversal ? 'Reversal' : 'OK'),
                  ])
              .toList(),
        );

      case ReportType.waste:
        final list = waste
            .where((w) =>
                !w.isVoided &&
                _inRange(w.wasteDateTime) &&
                (_reason == 'All' || w.reason == _reason) &&
                (_productId == 'All' || w.productId == _productId))
            .toList();
        final rows = list
            .map((w) => [
                  w.wasteId,
                  AppFormatters.formatDateTime(w.wasteDateTime),
                  w.productName,
                  AppFormatters.formatNumber(w.quantity),
                  w.unit,
                  w.reason,
                  AppFormatters.formatCurrency(w.estimatedValue),
                ])
            .toList();
        if (list.isNotEmpty) {
          final totalQty = list.fold<double>(0, (a, w) => a + w.quantity);
          final totalValue =
              list.fold<double>(0, (a, w) => a + w.estimatedValue);
          rows.add([
            'TOTAL',
            '',
            '',
            AppFormatters.formatNumber(totalQty),
            '',
            '',
            AppFormatters.formatCurrency(totalValue),
          ]);
        }
        return TableData(
          title: 'Waste Report',
          headers: [
            'WasteID',
            'Date / Time',
            'Product',
            'Quantity',
            'Unit',
            'Reason',
            'Est. Value (PHP)'
          ],
          rows: rows,
        );

      case ReportType.movement:
        final outgoing = <String, double>{};
        for (final t in txs) {
          if (t.isOutgoing &&
              !t.isVoided &&
              !t.isReversal &&
              _inRange(t.dateTime)) {
            outgoing[t.productId] = (outgoing[t.productId] ?? 0) + t.quantity;
          }
        }
        final active = products.where((p) => p.isActive).toList()
          ..sort((a, b) => a.productMovement.compareTo(b.productMovement));
        return TableData(
          title: 'Fast vs Slow Moving Report',
          headers: [
            'ProductID',
            'Name',
            'Movement',
            'Outgoing in Period',
            'Unit',
            'Current Stock'
          ],
          rows: active
              .map((p) => [
                    p.productId,
                    p.productName,
                    p.productMovement,
                    AppFormatters.formatNumber(outgoing[p.productId] ?? 0),
                    p.unit,
                    AppFormatters.formatNumber(stockOf(p.productId)),
                  ])
              .toList(),
        );

      case ReportType.deliveries:
        final list = txs
            .where((t) =>
                t.isIncoming &&
                !t.isVoided &&
                !t.isReversal &&
                _inRange(t.dateTime))
            .toList()
          ..sort(
              (a, b) => (a.supplierName ?? '').compareTo(b.supplierName ?? ''));
        return TableData(
          title: 'Supplier Deliveries Report',
          headers: [
            'Supplier',
            'Date / Time',
            'TransactionID',
            'Product',
            'Quantity',
            'Storage',
            'Received By'
          ],
          rows: list
              .map((t) => [
                    t.supplierName ?? '-',
                    AppFormatters.formatDateTime(t.dateTime),
                    t.transactionId,
                    t.productName,
                    '${AppFormatters.formatNumber(t.quantity)} ${t.unit}',
                    t.storageName,
                    t.recordedBy,
                  ])
              .toList(),
        );
    }
  }

  Future<void> _export(TableData table, {required bool pdf}) async {
    setState(() => _busy = true);
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'catchup_${_type.name}_$stamp.${pdf ? 'pdf' : 'csv'}';
      final period =
          'Period: ${AppFormatters.formatDate(_range.start)} - ${AppFormatters.formatDate(_range.end)}';
      final msg = pdf
          ? await ExportService.exportPdf(table, name, subtitle: period)
          : await ExportService.exportCsv(table, name);
      if (mounted && msg != null) {
        CatchUpToast.success(context, msg);
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Export failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider).value ?? [];
    final table = _build();
    final usesDates =
        _type != ReportType.currentStock && _type != ReportType.lowStock;

    final totalPages = (table.rows.length / _pageSize).ceil();
    final safePage =
        totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
    final pagedRows =
        table.rows.skip(safePage * _pageSize).take(_pageSize).toList();

    return ResponsiveModulePage(
      header: const ResponsivePageHeader(
        title: 'Reports',
        subtitle:
            'Generate, view, and export PHP inventory, stock movement, and supplier reports',
      ),
      filterBar: ResponsiveFilterCard(
        items: [
          ResponsiveFilterItem(
            desktopWidth: 240,
            child: DropdownButtonFormField<ReportType>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Report'),
              items: ReportType.values
                  .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(r.label, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() {
                _type = v ?? _type;
                _currentPage = 0;
              }),
            ),
          ),
          ResponsiveFilterItem(
            desktopWidth: 230,
            child: OutlinedButton.icon(
              onPressed: usesDates ? _pickRange : null,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                usesDates
                    ? '${AppFormatters.formatDate(_range.start)} - ${AppFormatters.formatDate(_range.end)}'
                    : 'Current levels (no date)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (_type == ReportType.transactions)
            ResponsiveFilterItem(
              desktopWidth: 170,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _txType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const ['All', 'Incoming', 'Outgoing']
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _txType = v ?? 'All';
                  _currentPage = 0;
                }),
              ),
            ),
          if (_type == ReportType.waste)
            ResponsiveFilterItem(
              desktopWidth: 180,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: ['All', ...WasteConstants.reasons]
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _reason = v ?? 'All';
                  _currentPage = 0;
                }),
              ),
            ),
          if (_type == ReportType.transactions || _type == ReportType.waste)
            ResponsiveFilterItem(
              desktopWidth: 220,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  const DropdownMenuItem(
                    value: 'All',
                    child:
                        Text('All Products', overflow: TextOverflow.ellipsis),
                  ),
                  ...products.map((p) => DropdownMenuItem(
                      value: p.productId,
                      child: Text(p.productName,
                          overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() {
                  _productId = v ?? 'All';
                  _currentPage = 0;
                }),
              ),
            ),
        ],
        trailingChips: [
          ElevatedButton.icon(
            onPressed: _busy || table.rows.isEmpty
                ? null
                : () => _export(table, pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Export PDF'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || table.rows.isEmpty
                ? null
                : () => _export(table, pdf: false),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Export CSV'),
          ),
        ],
      ),
      isEmpty: table.rows.isEmpty,
      emptyChild: const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyStateWidget(
            icon: Icons.bar_chart_outlined,
            title: 'Nothing to show',
            message: 'No records for this period.',
          ),
        ),
      ),
      desktopTable: FullWidthDataTable(
        columns: table.headers.map((h) => DataColumn(label: Text(h))).toList(),
        rows: pagedRows
            .map((r) => DataRow(
                  cells: r
                      .map((c) => DataCell(Text(
                            c,
                            style: r.first == 'TOTAL'
                                ? const TextStyle(fontWeight: FontWeight.bold)
                                : null,
                          )))
                      .toList(),
                ))
            .toList(),
      ),
      mobileCards: pagedRows.map((row) {
        final isTotal = row.isNotEmpty && row.first == 'TOTAL';
        return Card(
          color: isTotal
              ? AppColors.sidebarActiveBlue.withValues(alpha: 0.08)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.isNotEmpty)
                  Text(
                    isTotal
                        ? 'REPORT TOTAL'
                        : '${row[0]}${row.length > 1 && row[1].isNotEmpty ? " • ${row[1]}" : ""}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    for (int i = isTotal ? 1 : 2;
                        i < row.length && i < table.headers.length;
                        i++)
                      if (row[i].isNotEmpty)
                        RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context)
                                .style
                                .copyWith(fontSize: 12.5),
                            children: [
                              TextSpan(
                                text: '${table.headers[i]}: ',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              TextSpan(
                                text: row[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
      paginationBar: CatchUpPaginationBar(
        currentPage: safePage,
        totalItems: table.rows.length,
        pageSize: _pageSize,
        onPageChanged: (p) => setState(() => _currentPage = p),
      ),
    );
  }
}
