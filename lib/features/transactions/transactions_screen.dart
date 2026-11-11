import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Transactions module:
/// - TransactionID (auto: T001, T002, ...)
/// - Type: ONLY Incoming or Outgoing
/// - Product (dropdown/search), Quantity, Unit (auto from product)
/// - Supplier (required for Incoming only)
/// - Storage Location (dropdown)
/// - Date/Time (default now), Notes, RecordedBy (auto, current user)
/// - Blocks Outgoing if quantity > available stock
/// - Updates stock using Firestore transactions so counts stay accurate
/// - Immutable after saving; Admin/Manager can void one with a reason, creating a reversing entry
/// - Paginated to 10 items per page
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  String _selectedType = 'All';
  String _selectedProductId = 'All';
  DateTimeRange? _dateRange;
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await CatchUpCompactDateRangeDialog.show(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
        _currentPage = 0;
      });
    }
  }

  Future<void> _voidTransaction(StockTransaction tx) async {
    final reason = await showVoidReasonDialog(
      context: context,
      title: 'Void Transaction ${tx.transactionId}',
      subtitle:
          'Voiding this ${tx.type} transaction (${tx.quantity} ${tx.unit} of ${tx.productName}) will create a reversing entry and adjust stock.',
    );
    if (reason == null) return;

    final currentUser = ref.read(currentUserProfileProvider).value;
    final useFirebase = ref.read(firestoreActiveProvider);

    try {
      void voidLocally() {
        LocalDemoStore.instance.voidTransaction(
          tx,
          reason,
          currentUser?.userEmail ?? 'Admin',
        );
      }

      if (!useFirebase) {
        voidLocally();
      } else {
        try {
          final firestore = ref.read(firestoreProvider);
          final counterService = ref.read(counterServiceProvider);
          await firestore.runTransaction((transaction) async {
            final productRef =
                firestore.collection('products').doc(tx.productId);
            final txRef = firestore
                .collection('stockTransactions')
                .doc(tx.transactionId);

            final productSnap = await transaction.get(productRef);
            final txSnap = await transaction.get(txRef);

            if (!txSnap.exists || (txSnap.data()?['isVoided'] == true)) {
              throw Exception('Transaction is already voided.');
            }

            final currentStock =
                (productSnap.data()?['currentStock'] as num?)?.toDouble() ??
                0.0;

            final double newStock = tx.isIncoming
                ? currentStock - tx.quantity
                : currentStock + tx.quantity;

            if (newStock < 0) {
              throw Exception(
                'Cannot void this Incoming transaction because current stock ($currentStock ${tx.unit}) is lower than ${tx.quantity} ${tx.unit}.',
              );
            }

            final reversalId = await counterService.getNextId(
              counterKey: 'stockTransactions',
              prefix: 'T',
              transaction: transaction,
            );

            final reversalType = tx.isIncoming ? 'Outgoing' : 'Incoming';
            final reversalEntry = StockTransaction(
              transactionId: reversalId,
              type: reversalType,
              productId: tx.productId,
              productName: tx.productName,
              quantity: tx.quantity,
              unit: tx.unit,
              supplierId: tx.supplierId,
              supplierName: tx.supplierName,
              storageId: tx.storageId,
              storageName: tx.storageName,
              dateTime: DateTime.now(),
              notes: 'REVERSAL of ${tx.transactionId}: $reason',
              recordedBy: currentUser?.userEmail ?? 'Admin',
              isReversal: true,
              reversesTransactionId: tx.transactionId,
            );

            transaction.update(txRef, {
              'isVoided': true,
              'voidReason': reason,
              'voidedBy': currentUser?.userEmail ?? 'Admin',
              'voidedAt': DateTime.now(),
            });

            transaction.set(
              firestore.collection('stockTransactions').doc(reversalId),
              reversalEntry.toMap(),
            );

            if (productSnap.exists) {
              transaction.update(productRef, {'currentStock': newStock});
            }
          });
        } catch (fbErr) {
          if ('$fbErr'.contains('Cannot void')) rethrow;
          LocalDemoStore.instance.markFirestoreBlocked();
          voidLocally();
        }
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          'Transaction ${tx.transactionId} voided and reversing entry created.',
        );
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(
          context,
          '$e'.replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsStreamProvider);
    final products = ref.watch(productsStreamProvider).value ?? [];
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canVoid = currentUser?.canVoidRecords ?? false;

    return txAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) =>
          Center(child: Text('Error loading transactions: $err')),
      data: (allTx) {
        if (allTx.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.swap_horiz_outlined,
            title: 'No stock transactions yet',
            message:
                'No transactions yet. Tap Record Transaction to log incoming or outgoing stock.',
            actionLabel: 'Record Transaction',
            onAction: () => _openRecordDialog(context),
          );
        }

        final filtered = allTx.where((tx) {
          final matchesSearch =
              _searchQuery.isEmpty ||
              tx.transactionId.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              tx.productName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              (tx.supplierName ?? '').toLowerCase().contains(
                _searchQuery.toLowerCase(),
              );
          final matchesType =
              _selectedType == 'All' || tx.type == _selectedType;
          final matchesProd =
              _selectedProductId == 'All' || tx.productId == _selectedProductId;
          final matchesDate =
              _dateRange == null ||
              (!tx.dateTime.isBefore(_dateRange!.start) &&
                  !tx.dateTime.isAfter(
                    _dateRange!.end.add(const Duration(days: 1)),
                  ));
          return matchesSearch && matchesType && matchesProd && matchesDate;
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil();
        final safePage = totalPages == 0
            ? 0
            : _currentPage.clamp(0, totalPages - 1);
        final visible = filtered
            .skip(safePage * _pageSize)
            .take(_pageSize)
            .toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Stock Transactions',
            subtitle:
                'Record Incoming supplier deliveries and Outgoing stock usage',
            actions: [
              ElevatedButton.icon(
                onPressed: () => _openRecordDialog(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Record Transaction'),
              ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search ID, product, supplier...',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (v) => _searchDebouncer.run(() {
                    if (!mounted) return;
                    setState(() {
                      _searchQuery = v;
                      _currentPage = 0;
                    });
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 170,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'All',
                      child: Text('All Types', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Incoming',
                      child: Text('Incoming', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Outgoing',
                      child: Text('Outgoing', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedType = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedProductId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Products',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...products.map(
                      (p) => DropdownMenuItem(
                        value: p.productId,
                        child: Text(
                          '${p.productName} (${p.productId})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedProductId = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 230,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.date_range_outlined, size: 18),
                        label: Text(
                          _dateRange == null
                              ? 'Filter Date Range'
                              : '${AppFormatters.formatDate(_dateRange!.start)} - ${AppFormatters.formatDate(_dateRange!.end)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_dateRange != null)
                      IconButton(
                        tooltip: 'Clear date range',
                        onPressed: () => setState(() {
                          _dateRange = null;
                          _currentPage = 0;
                        }),
                        icon: const Icon(Icons.clear, size: 18),
                      ),
                  ],
                ),
              ),
            ],
          ),
          isEmpty: filtered.isEmpty,
          emptyChild: const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No transactions match your filters.')),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: [
              const DataColumn(label: Text('ID')),
              const DataColumn(label: Text('Type')),
              const DataColumn(label: Text('Product')),
              const DataColumn(label: Text('Quantity')),
              const DataColumn(label: Text('Supplier')),
              const DataColumn(label: Text('Storage')),
              const DataColumn(label: Text('Date / Time')),
              const DataColumn(label: Text('Recorded By')),
              const DataColumn(label: Text('Notes')),
              if (canVoid) const DataColumn(label: Text('Action')),
            ],
            rows: visible.map((tx) {
              final strike = tx.isVoided
                  ? const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey,
                    )
                  : null;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      tx.transactionId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(
                          label: tx.type,
                          color: tx.isIncoming
                              ? AppColors.statusGreen
                              : AppColors.statusOrange,
                        ),
                        if (tx.isVoided) ...[
                          const SizedBox(width: 4),
                          const StatusBadge(
                            label: 'VOIDED',
                            color: AppColors.statusRed,
                          ),
                        ],
                        if (tx.isReversal) ...[
                          const SizedBox(width: 4),
                          const StatusBadge(
                            label: 'REVERSAL',
                            color: AppColors.sidebarActiveBlue,
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    Text('${tx.productName} (${tx.productId})', style: strike),
                  ),
                  DataCell(
                    Text(
                      '${AppFormatters.formatNumber(tx.quantity)} ${tx.unit}',
                      style: strike,
                    ),
                  ),
                  DataCell(Text(tx.supplierName ?? '-', style: strike)),
                  DataCell(Text(tx.storageName, style: strike)),
                  DataCell(
                    Text(
                      AppFormatters.formatDateTime(tx.dateTime),
                      style: strike,
                    ),
                  ),
                  DataCell(Text(tx.recordedBy, style: strike)),
                  DataCell(
                    Text(
                      tx.isVoided
                          ? '${tx.notes} [Void: ${tx.voidReason}]'
                          : tx.notes,
                    ),
                  ),
                  if (canVoid)
                    DataCell(
                      (!tx.isVoided && !tx.isReversal)
                          ? TextButton.icon(
                              onPressed: () => _voidTransaction(tx),
                              icon: const Icon(
                                Icons.block_outlined,
                                size: 16,
                                color: AppColors.statusRed,
                              ),
                              label: const Text(
                                'Void',
                                style: TextStyle(color: AppColors.statusRed),
                              ),
                            )
                          : const Text('-'),
                    ),
                ],
              );
            }).toList(),
          ),
          mobileCards: visible.map((tx) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusBadge(
                          label: tx.type,
                          color: tx.isIncoming
                              ? AppColors.statusGreen
                              : AppColors.statusOrange,
                        ),
                        if (tx.isVoided) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            label: 'VOIDED',
                            color: AppColors.statusRed,
                          ),
                        ],
                        if (tx.isReversal) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            label: 'REVERSAL',
                            color: AppColors.sidebarActiveBlue,
                          ),
                        ],
                        const Spacer(),
                        Text(
                          tx.transactionId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (canVoid && !tx.isVoided && !tx.isReversal)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.block_outlined,
                              color: AppColors.statusRed,
                              size: 20,
                            ),
                            tooltip: 'Void Transaction',
                            onPressed: () => _voidTransaction(tx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tx.productName} (${AppFormatters.formatNumber(tx.quantity)} ${tx.unit})',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        decoration: tx.isVoided
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppFormatters.formatDateTime(tx.dateTime)} | Storage: ${tx.storageName}${tx.supplierName != null ? " | Supplier: ${tx.supplierName}" : ""}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'By: ${tx.recordedBy}${tx.isVoided ? " | VOIDED (${tx.voidReason})" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          paginationBar: CatchUpPaginationBar(
            currentPage: safePage,
            totalItems: filtered.length,
            pageSize: _pageSize,
            onPageChanged: (p) => setState(() => _currentPage = p),
          ),
        );
      },
    );
  }

  Future<void> _openRecordDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RecordTransactionDialog(),
    );
  }
}

class _RecordTransactionDialog extends ConsumerStatefulWidget {
  const _RecordTransactionDialog();

  @override
  ConsumerState<_RecordTransactionDialog> createState() =>
      _RecordTransactionDialogState();
}

class _RecordTransactionDialogState
    extends ConsumerState<_RecordTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'Incoming';
  Product? _selectedProduct;
  String? _selectedSupplierId;
  String? _selectedStorageId;
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;
  String? _errorMsg;

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      setState(() => _errorMsg = 'Please select a product.');
      return;
    }
    if (_type == 'Incoming' && _selectedSupplierId == null) {
      setState(
        () => _errorMsg = 'Supplier is required for Incoming deliveries.',
      );
      return;
    }
    if (_selectedStorageId == null) {
      setState(() => _errorMsg = 'Please select a storage location.');
      return;
    }

    final qty = double.parse(_qtyController.text.trim());
    final stockMap = ref.read(calculatedStockMapProvider);
    final availableStock =
        stockMap[_selectedProduct!.productId] ?? _selectedProduct!.currentStock;

    if (_type == 'Outgoing' && qty > availableStock) {
      setState(() {
        _errorMsg =
            'Cannot record Outgoing of $qty ${_selectedProduct!.unit}. Only ${AppFormatters.formatNumber(availableStock)} ${_selectedProduct!.unit} available in stock.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      final useFirebase = ref.read(firestoreActiveProvider);
      final currentUser = ref.read(currentUserProfileProvider).value;
      final suppliers = ref.read(suppliersStreamProvider).value ?? [];
      final storages = ref.read(storageLocationsStreamProvider).value ?? [];

      final supplier = suppliers
          .where((s) => s.supplierId == _selectedSupplierId)
          .firstOrNull;
      final storage = storages
          .where((st) => st.storageId == _selectedStorageId)
          .first;

      void saveLocally() {
        final txId = LocalDemoStore.instance.nextId('stockTransactions', 'T');
        final stockTx = StockTransaction(
          transactionId: txId,
          type: _type,
          productId: _selectedProduct!.productId,
          productName: _selectedProduct!.productName,
          quantity: qty,
          unit: _selectedProduct!.unit,
          supplierId: _type == 'Incoming' ? supplier?.supplierId : null,
          supplierName: _type == 'Incoming' ? supplier?.supplierName : null,
          storageId: storage.storageId,
          storageName: storage.storageName,
          dateTime: DateTime.now(),
          notes: _notesController.text.trim(),
          recordedBy:
              currentUser?.userEmail ?? currentUser?.fullName ?? 'Staff',
        );
        LocalDemoStore.instance.recordTransaction(stockTx);
      }

      if (!useFirebase) {
        saveLocally();
      } else {
        try {
          final firestore = ref.read(firestoreProvider);
          final counterService = ref.read(counterServiceProvider);
          await firestore.runTransaction((transaction) async {
            final productRef = firestore
                .collection('products')
                .doc(_selectedProduct!.productId);
            final productSnap = await transaction.get(productRef);

            final currentStockInDb =
                (productSnap.data()?['currentStock'] as num?)?.toDouble() ??
                availableStock;

            if (_type == 'Outgoing' && qty > currentStockInDb) {
              throw Exception(
                'Insufficient stock! Available: ${AppFormatters.formatNumber(currentStockInDb)} ${_selectedProduct!.unit}.',
              );
            }

            final txId = await counterService.getNextId(
              counterKey: 'stockTransactions',
              prefix: 'T',
              transaction: transaction,
            );

            final newStock = _type == 'Incoming'
                ? currentStockInDb + qty
                : currentStockInDb - qty;

            final stockTx = StockTransaction(
              transactionId: txId,
              type: _type,
              productId: _selectedProduct!.productId,
              productName: _selectedProduct!.productName,
              quantity: qty,
              unit: _selectedProduct!.unit,
              supplierId: _type == 'Incoming' ? supplier?.supplierId : null,
              supplierName: _type == 'Incoming' ? supplier?.supplierName : null,
              storageId: storage.storageId,
              storageName: storage.storageName,
              dateTime: DateTime.now(),
              notes: _notesController.text.trim(),
              recordedBy:
                  currentUser?.userEmail ?? currentUser?.fullName ?? 'Staff',
            );

            transaction.set(
              firestore.collection('stockTransactions').doc(txId),
              stockTx.toMap(),
            );
            transaction.update(productRef, {'currentStock': newStock});
          });
        } catch (fbErr) {
          if ('$fbErr'.contains('Insufficient stock')) rethrow;
          LocalDemoStore.instance.markFirestoreBlocked();
          saveLocally();
        }
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          '$_type transaction recorded for ${_selectedProduct!.productName}.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _errorMsg = msg;
      });
      if (mounted) {
        CatchUpToast.error(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeProducts = ref.watch(activeProductsProvider);
    final suppliers = (ref.watch(suppliersStreamProvider).value ?? [])
        .where((s) => s.isActive)
        .toList();
    final storages = ref.watch(storageLocationsStreamProvider).value ?? [];
    final stockMap = ref.watch(calculatedStockMapProvider);

    if (activeProducts.isEmpty) {
      return AlertDialog(
        title: const Text('Record Transaction'),
        content: const Text(
          'No active products exist yet. Please add a product first before recording a stock transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/products');
            },
            child: const Text('Go to Products'),
          ),
        ],
      );
    }

    final selectedStock = _selectedProduct != null
        ? (stockMap[_selectedProduct!.productId] ??
              _selectedProduct!.currentStock)
        : 0.0;

    return AlertDialog(
      title: const Text('Record Stock Transaction'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMsg != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.statusRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.statusRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(
                        color: AppColors.statusRed,
                        fontSize: 13,
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Type *',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Incoming',
                      child: Text(
                        'Incoming - Received from supplier',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Outgoing',
                      child: Text(
                        'Outgoing - Used for prep / authorized',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'Incoming'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Product>(
                  isExpanded: true,
                  initialValue: _selectedProduct,
                  decoration: const InputDecoration(labelText: 'Product *'),
                  items: activeProducts
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.productName} (${p.productId}) - ${AppFormatters.formatNumber(stockMap[p.productId] ?? p.currentStock)} ${p.unit}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (p) => setState(() => _selectedProduct = p),
                  validator: (p) => p == null ? 'Select a product' : null,
                ),
                if (_selectedProduct != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Available Stock: ${AppFormatters.formatNumber(selectedStock)} ${_selectedProduct!.unit}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selectedStock <= 0
                          ? AppColors.statusRed
                          : AppColors.sidebarActiveBlue,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity *',
                        ),
                        validator: (v) =>
                            AppValidators.positiveNumber(v, 'Quantity'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Unit (Auto)',
                        ),
                        child: Text(_selectedProduct?.unit ?? '-'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_type == 'Incoming') ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSupplierId,
                    decoration: const InputDecoration(
                      labelText: 'Supplier (Required for Incoming) *',
                    ),
                    items: suppliers
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.supplierId,
                            child: Text(
                              '${s.supplierName} (${s.supplierId})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSupplierId = v),
                    validator: (v) => (_type == 'Incoming' && v == null)
                        ? 'Supplier is required for Incoming stock'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedStorageId,
                  decoration: const InputDecoration(
                    labelText: 'Storage Location *',
                  ),
                  items: storages
                      .map(
                        (st) => DropdownMenuItem(
                          value: st.storageId,
                          child: Text(
                            '${st.storageName} (${st.storageType})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedStorageId = v),
                  validator: (v) =>
                      v == null ? 'Storage Location is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: const Text('Save Transaction'),
        ),
      ],
    );
  }
}
