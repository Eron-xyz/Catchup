import 'dart:convert';
import 'dart:typed_data';
import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/utils/photo_upload_service.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Inventory (Stock on Hand) module:
/// - Can Create Inventory Item and Edit Inventory Item directly from Inventory
/// - Full-width aligned table with 10-items-per-page pagination
/// - Fixed dropdown widths (`isExpanded: true`) so there is never a right-overflow yellow stripe
/// - Clean ASCII subtitle ("Current Stock = Total Incoming - Total Outgoing - Total Waste per product")
class InventoryScreen extends ConsumerStatefulWidget {
  final bool initialLowStockOnly;

  const InventoryScreen({super.key, this.initialLowStockOnly = false});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedStorageId = 'All';
  late bool _lowStockOnly;
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _lowStockOnly = widget.initialLowStockOnly;
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLowStockOnly != widget.initialLowStockOnly) {
      setState(() {
        _lowStockOnly = widget.initialLowStockOnly;
        _currentPage = 0;
      });
    }
  }

  Future<void> _openCreateOrEditInventoryDialog(
    BuildContext context, {
    Product? product,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InventoryItemDialog(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final stockMap = ref.watch(calculatedStockMapProvider);
    final transactions = ref.watch(transactionsStreamProvider).value ?? [];
    final storages = ref.watch(storageLocationsStreamProvider).value ?? [];
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canEdit = currentUser?.canEditMasterData ?? false;
    final settings = ref.watch(appSettingsStreamProvider).value;
    final categories =
        settings?.categories ?? ProductConstants.defaultCategories;

    return productsAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) => Center(child: Text('Error loading inventory: $err')),
      data: (allProducts) {
        final activeProducts = allProducts.where((p) => p.isActive).toList();

        if (activeProducts.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.inventory_2_outlined,
            title: 'No inventory items yet',
            message:
                'No inventory items yet. Tap Create Inventory to add your first item.',
            actionLabel: canEdit ? 'Create Inventory' : null,
            onAction: canEdit
                ? () => _openCreateOrEditInventoryDialog(context)
                : null,
          );
        }

        final Set<String>? productsInSelectedStorage =
            _selectedStorageId == 'All'
            ? null
            : transactions
                  .where(
                    (t) => !t.isVoided && t.storageId == _selectedStorageId,
                  )
                  .map((t) => t.productId)
                  .toSet();

        final filtered = activeProducts.where((p) {
          final currentStock = stockMap[p.productId] ?? p.currentStock;
          final matchesSearch =
              _searchQuery.isEmpty ||
              p.productName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              p.productId.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesCategory =
              _selectedCategory == 'All' || p.category == _selectedCategory;
          final matchesStorage =
              productsInSelectedStorage == null ||
              productsInSelectedStorage.contains(p.productId);
          final matchesLowStock =
              !_lowStockOnly || currentStock <= p.minimumStock;

          return matchesSearch &&
              matchesCategory &&
              matchesStorage &&
              matchesLowStock;
        }).toList();

        final totalPages = filtered.isEmpty
            ? 1
            : ((filtered.length - 1) ~/ _pageSize) + 1;
        final safePage = _currentPage.clamp(0, totalPages - 1);
        final pageItems = filtered
            .skip(safePage * _pageSize)
            .take(_pageSize)
            .toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Inventory (Stock on Hand)',
            subtitle:
                'Current Stock = Total Incoming - Total Outgoing - Total Waste per product',
            actions: [
              if (canEdit)
                ElevatedButton.icon(
                  onPressed: () => _openCreateOrEditInventoryDialog(context),
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('Create Inventory'),
                ),
              if (currentUser?.canManageTransactions ?? false)
                OutlinedButton.icon(
                  onPressed: () => context.go('/transactions'),
                  icon: const Icon(Icons.swap_horiz_outlined, size: 18),
                  label: const Text('Record Stock Transaction'),
                ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search product ID or name...',
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
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Categories',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...categories.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedCategory = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 240,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedStorageId,
                  decoration: const InputDecoration(
                    labelText: 'Storage Location',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Storage Locations',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...storages.map(
                      (st) => DropdownMenuItem(
                        value: st.storageId,
                        child: Text(
                          st.storageName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedStorageId = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
            ],
            trailingChips: [
              FilterChip(
                label: const Text('Low / Out of Stock Only'),
                selected: _lowStockOnly,
                onSelected: (v) => setState(() {
                  _lowStockOnly = v;
                  _currentPage = 0;
                }),
              ),
            ],
          ),
          isEmpty: filtered.isEmpty,
          emptyChild: const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('No inventory items match your filters.'),
              ),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: [
              const DataColumn(label: Text('Photo')),
              const DataColumn(label: Text('ProductID')),
              const DataColumn(label: Text('Name')),
              const DataColumn(label: Text('Category')),
              const DataColumn(label: Text('Price (PHP)')),
              const DataColumn(label: Text('Min Stock')),
              const DataColumn(label: Text('Current Stock')),
              const DataColumn(label: Text('Unit')),
              const DataColumn(label: Text('Status')),
              if (canEdit) const DataColumn(label: Text('Actions')),
            ],
            rows: pageItems.map((product) {
              final currentStock =
                  stockMap[product.productId] ?? product.currentStock;
              final statusLabel = currentStock <= 0
                  ? 'Out of stock'
                  : currentStock <= product.minimumStock
                  ? 'Low'
                  : 'OK';
              final statusColor = currentStock <= 0
                  ? AppColors.statusRed
                  : currentStock <= product.minimumStock
                  ? AppColors.statusOrange
                  : AppColors.statusGreen;

              return DataRow(
                onSelectChanged: (_) =>
                    context.push('/products/${product.productId}'),
                cells: [
                  DataCell(_InventoryThumb(photoUrl: product.photoUrl)),
                  DataCell(
                    Text(
                      product.productId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(Text(product.productName)),
                  DataCell(Text(product.category)),
                  DataCell(Text(AppFormatters.formatCurrency(product.price))),
                  DataCell(
                    Text(AppFormatters.formatNumber(product.minimumStock)),
                  ),
                  DataCell(
                    Text(
                      AppFormatters.formatNumber(currentStock),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  DataCell(Text(product.unit)),
                  DataCell(StatusBadge(label: statusLabel, color: statusColor)),
                  if (canEdit)
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: 'Edit Inventory & Stock',
                        onPressed: () => _openCreateOrEditInventoryDialog(
                          context,
                          product: product,
                        ),
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
          mobileCards: pageItems.map((product) {
            final currentStock =
                stockMap[product.productId] ?? product.currentStock;
            final statusLabel = currentStock <= 0
                ? 'Out of stock'
                : currentStock <= product.minimumStock
                ? 'Low'
                : 'OK';
            final statusColor = currentStock <= 0
                ? AppColors.statusRed
                : currentStock <= product.minimumStock
                ? AppColors.statusOrange
                : AppColors.statusGreen;

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/products/${product.productId}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InventoryThumb(photoUrl: product.photoUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${product.productName} (${product.productId})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product.category} | ${AppFormatters.formatCurrency(product.price)} / ${product.unit}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusBadge(
                                  label:
                                      'Stock: ${AppFormatters.formatNumber(currentStock)} ${product.unit}',
                                  color: statusColor,
                                ),
                                StatusBadge(
                                  label: statusLabel,
                                  color: statusColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Inventory',
                          onPressed: () => _openCreateOrEditInventoryDialog(
                            context,
                            product: product,
                          ),
                        ),
                    ],
                  ),
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
}

class _InventoryThumb extends StatelessWidget {
  final String? photoUrl;

  const _InventoryThumb({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.sidebarActiveBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.set_meal_outlined,
                color: AppColors.sidebarActiveBlue,
                size: 20,
              ),
            )
          : const Icon(
              Icons.set_meal_outlined,
              color: AppColors.sidebarActiveBlue,
              size: 20,
            ),
    );
  }
}

/// Dialog for creating a new Inventory Item (with initial stock) or editing an existing
/// Inventory Item (including adjusting its current stock on hand).
class _InventoryItemDialog extends ConsumerStatefulWidget {
  final Product? product;
  const _InventoryItemDialog({this.product});

  @override
  ConsumerState<_InventoryItemDialog> createState() =>
      _InventoryItemDialogState();
}

class _InventoryItemDialogState extends ConsumerState<_InventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _reorderPointController;

  late String _category;
  late String _unit;
  late String _movement;
  Uint8List? _pickedPhotoBytes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final stockMap = ref.read(calculatedStockMapProvider);
    final currentStock = p != null
        ? (stockMap[p.productId] ?? p.currentStock)
        : 0.0;

    _nameController = TextEditingController(text: p?.productName ?? '');
    _typeController = TextEditingController(text: p?.type ?? 'Fish');
    _priceController = TextEditingController(
      text: p != null ? '${p.price}' : '200',
    );
    _stockController = TextEditingController(text: '$currentStock');
    _minStockController = TextEditingController(
      text: p != null ? '${p.minimumStock}' : '15',
    );
    _reorderPointController = TextEditingController(
      text: p != null ? '${p.reorderPoint}' : '25',
    );

    _category = p?.category ?? ProductConstants.defaultCategories.first;
    _unit = p?.unit ?? ProductConstants.defaultUnits.first;
    _movement = p?.productMovement ?? ProductConstants.movements.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _reorderPointController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final bytes = await PhotoUploadService.pickAndCompressImage();
    if (bytes != null) {
      setState(() => _pickedPhotoBytes = bytes);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final useFirebase = ref.read(firestoreActiveProvider);
      final currentUser = ref.read(currentUserProfileProvider).value;
      final stockMap = ref.read(calculatedStockMapProvider);
      final storages = ref.read(storageLocationsStreamProvider).value ?? [];
      final defaultStorage = storages.firstOrNull;

      String productId = widget.product?.productId ?? '';
      if (productId.isEmpty) {
        if (useFirebase) {
          try {
            productId = await ref
                .read(counterServiceProvider)
                .getNextId(counterKey: 'products', prefix: 'P');
          } catch (_) {
            LocalDemoStore.instance.markFirestoreBlocked();
            productId = LocalDemoStore.instance.nextId('products', 'P');
          }
        } else {
          productId = LocalDemoStore.instance.nextId('products', 'P');
        }
      }

      String? photoUrl = widget.product?.photoUrl;
      if (_pickedPhotoBytes != null) {
        if (ref.read(firestoreActiveProvider)) {
          try {
            photoUrl = await PhotoUploadService.uploadProductPhoto(
              productId: productId,
              imageBytes: _pickedPhotoBytes!,
            );
          } catch (_) {
            photoUrl =
                'data:image/jpeg;base64,${base64Encode(_pickedPhotoBytes!)}';
          }
        } else {
          photoUrl =
              'data:image/jpeg;base64,${base64Encode(_pickedPhotoBytes!)}';
        }
      }

      final targetStock = double.parse(_stockController.text.trim());
      final previousStock = widget.product != null
          ? (stockMap[productId] ?? widget.product!.currentStock)
          : 0.0;
      final stockDelta = targetStock - previousStock;

      final product = Product(
        productId: productId,
        productName: _nameController.text.trim(),
        category: _category,
        type: _typeController.text.trim(),
        unit: _unit,
        price: double.parse(_priceController.text.trim()),
        minimumStock: double.parse(_minStockController.text.trim()),
        reorderPoint: double.parse(_reorderPointController.text.trim()),
        productMovement: _movement,
        photoUrl: photoUrl,
        isActive: widget.product?.isActive ?? true,
        currentStock: targetStock,
        createdAt: widget.product?.createdAt ?? DateTime.now(),
      );

      void saveLocally() {
        LocalDemoStore.instance.saveProduct(product);
        if (stockDelta.abs() > 0.0001) {
          final txId = LocalDemoStore.instance.nextId('stockTransactions', 'T');
          final adjTx = StockTransaction(
            transactionId: txId,
            type: stockDelta > 0 ? 'Incoming' : 'Outgoing',
            productId: productId,
            productName: product.productName,
            quantity: stockDelta.abs(),
            unit: product.unit,
            storageId: defaultStorage?.storageId ?? 'ST001',
            storageName: defaultStorage?.storageName ?? 'Main Storage',
            dateTime: DateTime.now(),
            notes: widget.product == null
                ? 'Initial inventory stock'
                : 'Inventory stock adjustment',
            recordedBy: currentUser?.userEmail ?? 'Admin',
          );
          LocalDemoStore.instance.transactions.insert(0, adjTx);
        }
      }

      if (ref.read(firestoreActiveProvider)) {
        try {
          final firestore = ref.read(firestoreProvider);
          await firestore
              .collection('products')
              .doc(productId)
              .set(product.toMap(), SetOptions(merge: true));

          if (stockDelta.abs() > 0.0001) {
            final txId = await ref
                .read(counterServiceProvider)
                .getNextId(counterKey: 'stockTransactions', prefix: 'T');
            final adjTx = StockTransaction(
              transactionId: txId,
              type: stockDelta > 0 ? 'Incoming' : 'Outgoing',
              productId: productId,
              productName: product.productName,
              quantity: stockDelta.abs(),
              unit: product.unit,
              storageId: defaultStorage?.storageId ?? 'ST001',
              storageName: defaultStorage?.storageName ?? 'Main Storage',
              dateTime: DateTime.now(),
              notes: widget.product == null
                  ? 'Initial inventory stock'
                  : 'Inventory stock adjustment',
              recordedBy: currentUser?.userEmail ?? 'Admin',
            );
            await firestore
                .collection('stockTransactions')
                .doc(txId)
                .set(adjTx.toMap());
          }
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
          saveLocally();
        }
      } else {
        saveLocally();
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          widget.product == null
              ? 'Inventory item ${product.productName} created.'
              : 'Inventory item ${product.productName} updated.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Failed to save inventory item: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final settings = ref.watch(appSettingsStreamProvider).value;
    final categories =
        settings?.categories ?? ProductConstants.defaultCategories;
    final units = settings?.units ?? ProductConstants.defaultUnits;

    return AlertDialog(
      title: Text(
        isEdit
            ? 'Edit Inventory (${widget.product!.productId})'
            : 'Create Inventory Item',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.sidebarActiveBlue.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _pickedPhotoBytes != null
                          ? Image.memory(_pickedPhotoBytes!, fit: BoxFit.cover)
                          : const Icon(
                              Icons.set_meal_outlined,
                              size: 28,
                              color: AppColors.sidebarActiveBlue,
                            ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Choose Photo'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                  ),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Product Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: categories.contains(_category)
                            ? _category
                            : categories.first,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                        ),
                        items: categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _category = v ?? categories.first),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _typeController,
                        decoration: const InputDecoration(labelText: 'Type *'),
                        validator: (v) =>
                            AppValidators.requiredField(v, 'Type'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Current Stock on Hand *',
                        ),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Stock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: units.contains(_unit)
                            ? _unit
                            : units.first,
                        decoration: const InputDecoration(labelText: 'Unit *'),
                        items: units
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _unit = v ?? units.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price (PHP) *',
                          prefixText: 'PHP ',
                        ),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Price'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _movement,
                        decoration: const InputDecoration(
                          labelText: 'Movement *',
                        ),
                        items: ProductConstants.movements
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (v) => setState(
                          () =>
                              _movement = v ?? ProductConstants.movements.first,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minStockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Minimum Stock *',
                        ),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Minimum Stock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderPointController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Reorder Point *',
                        ),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Reorder Point'),
                      ),
                    ),
                  ],
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
          onPressed: _isSaving ? null : _save,
          child: Text(isEdit ? 'Save Inventory' : 'Create Inventory'),
        ),
      ],
    );
  }
}
