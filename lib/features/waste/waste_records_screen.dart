import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/waste_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Waste Records module:
/// - Fields: WasteID (auto: W001...), ProductID, Quantity, Unit (auto), WasteDateTime,
///   Reason (Spoiled, Expired, Damaged, Contaminated, Spillage, Other), Remarks, RecordedBy (signed-in user's email)
/// - Saving a waste record automatically deducts stock.
/// - Blocks saving if quantity > stock on hand.
/// - Staff can add; only Admin/Manager can void.
/// - Paginated to 10 items per page.
class WasteRecordsScreen extends ConsumerStatefulWidget {
  const WasteRecordsScreen({super.key});

  @override
  ConsumerState<WasteRecordsScreen> createState() => _WasteRecordsScreenState();
}

class _WasteRecordsScreenState extends ConsumerState<WasteRecordsScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  String _selectedReason = 'All';
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _voidWasteRecord(WasteRecord w) async {
    final reason = await showVoidReasonDialog(
      context: context,
      title: 'Void Waste Record ${w.wasteId}',
      subtitle:
          'Voiding this waste record will restore ${AppFormatters.formatNumber(w.quantity)} ${w.unit} of ${w.productName} back to stock.',
    );
    if (reason == null) return;

    final currentUser = ref.read(currentUserProfileProvider).value;
    final useFirebase = ref.read(firestoreActiveProvider);

    try {
      void voidLocally() {
        LocalDemoStore.instance.voidWaste(
          w,
          reason,
          currentUser?.userEmail ?? 'Admin',
        );
      }

      if (!useFirebase) {
        voidLocally();
      } else {
        try {
          final firestore = ref.read(firestoreProvider);
          await firestore.runTransaction((transaction) async {
            final productRef =
                firestore.collection('products').doc(w.productId);
            final wasteRef =
                firestore.collection('wasteRecords').doc(w.wasteId);

            final productSnap = await transaction.get(productRef);
            final wasteSnap = await transaction.get(wasteRef);

            if (!wasteSnap.exists || (wasteSnap.data()?['isVoided'] == true)) {
              throw Exception('Waste record is already voided.');
            }

            final currentStock =
                (productSnap.data()?['currentStock'] as num?)?.toDouble() ??
                0.0;
            final newStock = currentStock + w.quantity;

            transaction.update(wasteRef, {
              'isVoided': true,
              'voidReason': reason,
              'voidedBy': currentUser?.userEmail ?? 'Admin',
              'voidedAt': DateTime.now(),
            });

            if (productSnap.exists) {
              transaction.update(productRef, {'currentStock': newStock});
            }
          });
        } catch (fbErr) {
          LocalDemoStore.instance.markFirestoreBlocked();
          voidLocally();
        }
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          'Waste record ${w.wasteId} voided and stock restored.',
        );
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasteAsync = ref.watch(wasteRecordsStreamProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canVoid = currentUser?.canVoidRecords ?? false;

    return wasteAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) =>
          Center(child: Text('Error loading waste records: $err')),
      data: (allWaste) {
        if (allWaste.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.delete_outline,
            title: 'No waste records yet',
            message:
                'No waste records yet. Tap Record Waste to log spoiled, expired, or damaged seafood.',
            actionLabel: 'Record Waste',
            onAction: () => _openWasteDialog(context),
          );
        }

        final filtered = allWaste.where((w) {
          final matchesSearch =
              _searchQuery.isEmpty ||
              w.wasteId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              w.productName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              w.remarks.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesReason =
              _selectedReason == 'All' || w.reason == _selectedReason;
          return matchesSearch && matchesReason;
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil();
        final safePage = totalPages == 0
            ? 0
            : _currentPage.clamp(0, totalPages - 1);
        final paged = filtered
            .skip(safePage * _pageSize)
            .take(_pageSize)
            .toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Waste Records',
            subtitle:
                'Track spoiled, expired, damaged, or spilled seafood and automatically deduct stock',
            actions: [
              ElevatedButton.icon(
                onPressed: () => _openWasteDialog(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Record Waste'),
              ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search ID, product, or remarks...',
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
                desktopWidth: 210,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedReason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Reasons',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...WasteConstants.reasons.map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedReason = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
            ],
          ),
          isEmpty: filtered.isEmpty,
          emptyChild: const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('No waste records match your filters.'),
              ),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: [
              const DataColumn(label: Text('Waste ID')),
              const DataColumn(label: Text('Product')),
              const DataColumn(label: Text('Quantity')),
              const DataColumn(label: Text('Est. Value')),
              const DataColumn(label: Text('Reason')),
              const DataColumn(label: Text('Date / Time')),
              const DataColumn(label: Text('Recorded By')),
              const DataColumn(label: Text('Remarks')),
              if (canVoid) const DataColumn(label: Text('Action')),
            ],
            rows: paged.map((w) {
              final strike = w.isVoided
                  ? const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey,
                    )
                  : null;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      w.wasteId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text('${w.productName} (${w.productId})', style: strike),
                  ),
                  DataCell(
                    Text(
                      '${AppFormatters.formatNumber(w.quantity)} ${w.unit}',
                      style: strike,
                    ),
                  ),
                  DataCell(
                    Text(
                      AppFormatters.formatCurrency(w.estimatedValue),
                      style: strike,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(
                          label: w.reason,
                          color: AppColors.statusRed,
                        ),
                        if (w.isVoided) ...[
                          const SizedBox(width: 4),
                          const StatusBadge(
                            label: 'VOIDED',
                            color: Colors.grey,
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      AppFormatters.formatDateTime(w.wasteDateTime),
                      style: strike,
                    ),
                  ),
                  DataCell(Text(w.recordedBy, style: strike)),
                  DataCell(
                    Text(
                      w.isVoided
                          ? '${w.remarks} [Void: ${w.voidReason}]'
                          : w.remarks,
                    ),
                  ),
                  if (canVoid)
                    DataCell(
                      !w.isVoided
                          ? TextButton.icon(
                              onPressed: () => _voidWasteRecord(w),
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
          mobileCards: paged.map((w) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusBadge(
                          label: w.reason,
                          color: AppColors.statusRed,
                        ),
                        if (w.isVoided) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            label: 'VOIDED',
                            color: Colors.grey,
                          ),
                        ],
                        const Spacer(),
                        Text(
                          w.wasteId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (canVoid && !w.isVoided)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.block_outlined,
                              color: AppColors.statusRed,
                              size: 20,
                            ),
                            tooltip: 'Void Waste Record',
                            onPressed: () => _voidWasteRecord(w),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${w.productName} (${AppFormatters.formatNumber(w.quantity)} ${w.unit}) • ${AppFormatters.formatCurrency(w.estimatedValue)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        decoration: w.isVoided
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppFormatters.formatDateTime(w.wasteDateTime)} | By: ${w.recordedBy}${w.remarks.isNotEmpty ? "\nRemarks: ${w.remarks}" : ""}${w.isVoided ? "\nVOIDED: ${w.voidReason}" : ""}',
                      style: TextStyle(
                        fontSize: 12.5,
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

  Future<void> _openWasteDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RecordWasteDialog(),
    );
  }
}

class _RecordWasteDialog extends ConsumerStatefulWidget {
  const _RecordWasteDialog();

  @override
  ConsumerState<_RecordWasteDialog> createState() => _RecordWasteDialogState();
}

class _RecordWasteDialogState extends ConsumerState<_RecordWasteDialog> {
  final _formKey = GlobalKey<FormState>();
  Product? _selectedProduct;
  String _reason = WasteConstants.reasons.first;
  final _qtyController = TextEditingController();
  final _remarksController = TextEditingController();
  bool _isSaving = false;
  String? _errorMsg;

  @override
  void dispose() {
    _qtyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      setState(() => _errorMsg = 'Please select a product.');
      return;
    }

    final qty = double.parse(_qtyController.text.trim());
    final stockMap = ref.read(calculatedStockMapProvider);
    final availableStock =
        stockMap[_selectedProduct!.productId] ?? _selectedProduct!.currentStock;

    if (qty > availableStock) {
      setState(() {
        _errorMsg =
            'Cannot record waste of $qty ${_selectedProduct!.unit}. Only ${AppFormatters.formatNumber(availableStock)} ${_selectedProduct!.unit} on hand.';
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

      void saveLocally() {
        final wasteId = LocalDemoStore.instance.nextId('wasteRecords', 'W');
        final record = WasteRecord(
          wasteId: wasteId,
          productId: _selectedProduct!.productId,
          productName: _selectedProduct!.productName,
          quantity: qty,
          unit: _selectedProduct!.unit,
          unitPrice: _selectedProduct!.price,
          wasteDateTime: DateTime.now(),
          reason: _reason,
          remarks: _remarksController.text.trim(),
          recordedBy: currentUser?.userEmail ?? 'staff@catchup.ph',
        );
        LocalDemoStore.instance.recordWaste(record);
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

            if (qty > currentStockInDb) {
              throw Exception(
                'Quantity exceeds stock on hand (${AppFormatters.formatNumber(currentStockInDb)} ${_selectedProduct!.unit}).',
              );
            }

            final wasteId = await counterService.getNextId(
              counterKey: 'wasteRecords',
              prefix: 'W',
              transaction: transaction,
            );

            final record = WasteRecord(
              wasteId: wasteId,
              productId: _selectedProduct!.productId,
              productName: _selectedProduct!.productName,
              quantity: qty,
              unit: _selectedProduct!.unit,
              unitPrice: _selectedProduct!.price,
              wasteDateTime: DateTime.now(),
              reason: _reason,
              remarks: _remarksController.text.trim(),
              recordedBy: currentUser?.userEmail ?? 'staff@catchup.ph',
            );

            transaction.set(
              firestore.collection('wasteRecords').doc(wasteId),
              record.toMap(),
            );
            transaction.update(productRef, {
              'currentStock': currentStockInDb - qty,
            });
          });
        } catch (fbErr) {
          if ('$fbErr'.contains('Quantity exceeds')) rethrow;
          LocalDemoStore.instance.markFirestoreBlocked();
          saveLocally();
        }
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          'Waste record saved for ${_selectedProduct!.productName}.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() => _errorMsg = msg);
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
    final stockMap = ref.watch(calculatedStockMapProvider);

    if (activeProducts.isEmpty) {
      return AlertDialog(
        title: const Text('Record Waste'),
        content: const Text(
          'No active products exist yet. Add a product first before recording waste.',
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
      title: const Text('Record Seafood Waste'),
      content: SizedBox(
        width: 460,
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
                DropdownButtonFormField<Product>(
                  isExpanded: true,
                  initialValue: _selectedProduct,
                  decoration: const InputDecoration(labelText: 'Product *'),
                  items: activeProducts
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.productName} (${p.productId}) - Stock: ${AppFormatters.formatNumber(stockMap[p.productId] ?? p.currentStock)} ${p.unit}',
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
                    'Stock on Hand: ${AppFormatters.formatNumber(selectedStock)} ${_selectedProduct!.unit}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarActiveBlue,
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
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _reason,
                  decoration: const InputDecoration(labelText: 'Reason *'),
                  items: WasteConstants.reasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(
                    () => _reason = v ?? WasteConstants.reasons.first,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Remarks'),
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
          child: const Text('Save Waste Record'),
        ),
      ],
    );
  }
}
