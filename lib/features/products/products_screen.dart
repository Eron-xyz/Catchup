import 'dart:convert';
import 'dart:typed_data';
import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/utils/photo_upload_service.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/product.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Products module:
/// - Product list (DataTable on desktop, Card list on Android)
/// - Search, category filter, movement filter, active/inactive toggle, pagination
/// - Add/Edit dialog with photo picker (gallery/camera on Android, file picker on desktop) and compression
/// - Soft delete (`isActive` toggle)
/// - Tap a row/card to open Product Detail with its transaction history
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedMovement = 'All';
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final stockMap = ref.watch(calculatedStockMapProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canEdit = currentUser?.canEditMasterData ?? false;
    final settings = ref.watch(appSettingsStreamProvider).value;
    final categories = settings?.categories ?? ProductConstants.defaultCategories;

    return productsAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) => Center(child: Text('Error loading products: $err')),
      data: (allProducts) {
        final activeList = allProducts.where((p) => p.isActive).toList();

        if (activeList.isEmpty && allProducts.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.view_in_ar_outlined,
            title: 'No products yet',
            message: 'No products yet. Tap Add Product to get started.',
            actionLabel: canEdit ? 'Add Product' : null,
            onAction: canEdit ? () => _showProductDialog(context) : null,
          );
        }

        final filtered = activeList.where((p) {
          final matchesSearch = _searchQuery.isEmpty ||
              p.productName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              p.productId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              p.type.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesCat =
              _selectedCategory == 'All' || p.category == _selectedCategory;
          final matchesMove = _selectedMovement == 'All' ||
              p.productMovement == _selectedMovement;
          return matchesSearch && matchesCat && matchesMove;
        }).toList();

        final totalPages =
            filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
        final safePage = _currentPage.clamp(0, totalPages - 1);
        final visibleItems =
            filtered.skip(safePage * _pageSize).take(_pageSize).toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Seafood Products',
            subtitle:
                'Manage seafood items, minimum stock thresholds, and movement speed',
            actions: [
              if (canEdit)
                ElevatedButton.icon(
                  onPressed: () => _showProductDialog(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Product'),
                ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search ID, name, or type...',
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
                desktopWidth: 200,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text('All Categories',
                          overflow: TextOverflow.ellipsis),
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
                desktopWidth: 190,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedMovement,
                  decoration: const InputDecoration(
                    labelText: 'Movement',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'All',
                      child: Text('All Movement',
                          overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Fast Moving',
                      child: Text('Fast Moving'),
                    ),
                    DropdownMenuItem(
                      value: 'Slow Moving',
                      child: Text('Slow Moving'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedMovement = v ?? 'All';
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
                child: Text('No products match your search/filters.'),
              ),
            ),
          ),
          desktopTable: FullWidthDataTable(
            showCheckboxColumn: false,
            columns: [
              const DataColumn(label: Text('Photo')),
              const DataColumn(label: Text('ID')),
              const DataColumn(label: Text('Name')),
              const DataColumn(label: Text('Category')),
              const DataColumn(label: Text('Type')),
              const DataColumn(label: Text('Price (PHP)')),
              const DataColumn(label: Text('Min Stock')),
              const DataColumn(label: Text('Current Stock')),
              const DataColumn(label: Text('Movement')),
              if (canEdit) const DataColumn(label: Text('Actions')),
            ],
            rows: visibleItems.map((product) {
              final currentStock =
                  stockMap[product.productId] ?? product.currentStock;
              return DataRow(
                onSelectChanged: (_) =>
                    context.push('/products/${product.productId}'),
                cells: [
                  DataCell(_ProductThumb(photoUrl: product.photoUrl)),
                  DataCell(Text(
                    product.productId,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )),
                  DataCell(Text(product.productName)),
                  DataCell(Text(product.category)),
                  DataCell(Text(product.type)),
                  DataCell(Text(AppFormatters.formatCurrency(product.price))),
                  DataCell(Text(
                      '${AppFormatters.formatNumber(product.minimumStock)} ${product.unit}')),
                  DataCell(Text(
                    '${AppFormatters.formatNumber(currentStock)} ${product.unit}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: currentStock <= 0
                          ? AppColors.statusRed
                          : currentStock <= product.minimumStock
                              ? AppColors.statusOrange
                              : AppColors.statusGreen,
                    ),
                  )),
                  DataCell(StatusBadge(
                    label: product.productMovement,
                    color: product.productMovement == 'Fast Moving'
                        ? AppColors.oceanTeal
                        : AppColors.sidebarActiveBlue,
                  )),
                  if (canEdit)
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          tooltip: 'Edit Product',
                          onPressed: () => _showProductDialog(
                            context,
                            product: product,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: AppColors.statusRed,
                          ),
                          tooltip: 'Move to Trash',
                          onPressed: () => _toggleProductActive(product),
                        ),
                      ],
                    )),
                ],
              );
            }).toList(),
          ),
          mobileCards: visibleItems.map((product) {
            final currentStock =
                stockMap[product.productId] ?? product.currentStock;
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/products/${product.productId}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProductThumb(photoUrl: product.photoUrl),
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
                              '${product.category} | ${product.type} | ${AppFormatters.formatCurrency(product.price)}/${product.unit}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                StatusBadge(
                                  label:
                                      'Stock: ${AppFormatters.formatNumber(currentStock)} ${product.unit}',
                                  color: currentStock <= 0
                                      ? AppColors.statusRed
                                      : currentStock <= product.minimumStock
                                          ? AppColors.statusOrange
                                          : AppColors.statusGreen,
                                ),
                                StatusBadge(
                                  label: product.productMovement,
                                  color: AppColors.oceanTeal,
                                ),
                                if (!product.isActive)
                                  const StatusBadge(
                                    label: 'Inactive',
                                    color: Colors.grey,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (canEdit)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit Product',
                              onPressed: () => _showProductDialog(
                                context,
                                product: product,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: AppColors.statusRed,
                              ),
                              tooltip: 'Move to Trash',
                              onPressed: () => _toggleProductActive(product),
                            ),
                          ],
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

  Future<void> _toggleProductActive(Product product) async {
    final isDeleting = product.isActive;
    final confirmed = await showConfirmDialog(
      context: context,
      title: isDeleting ? 'Move to Trash' : 'Restore Product',
      message: isDeleting
          ? 'Are you sure you want to move "${product.productName}" (${product.productId}) to Trash? It will be hidden from active inventory and can be restored anytime from Trash in Settings.'
          : 'Restore "${product.productName}" (${product.productId}) back to active products?',
      confirmLabel: isDeleting ? 'Move to Trash' : 'Restore',
      confirmColor:
          isDeleting ? AppColors.statusRed : AppColors.statusGreen,
    );
    if (!confirmed) return;

    if (ref.read(firestoreActiveProvider)) {
      try {
        await ref
            .read(firestoreProvider)
            .collection('products')
            .doc(product.productId)
            .update({'isActive': !product.isActive});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleProductActive(product.productId);
      }
    } else {
      LocalDemoStore.instance.toggleProductActive(product.productId);
    }
    if (mounted) {
      CatchUpToast.success(
        context,
        isDeleting
            ? '${product.productName} moved to Trash.'
            : '${product.productName} restored from Trash.',
      );
    }
  }

  Future<void> _showProductDialog(BuildContext context,
      {Product? product}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductFormDialog(product: product),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String? photoUrl;

  const _ProductThumb({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.sidebarActiveBlue.withValues(alpha: 0.12),
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
                size: 22,
              ),
            )
          : const Icon(
              Icons.set_meal_outlined,
              color: AppColors.sidebarActiveBlue,
              size: 22,
            ),
    );
  }
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  final Product? product;

  const _ProductFormDialog({this.product});

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _priceController;
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
    final settings = ref.read(appSettingsStreamProvider).value;
    final defaultThreshold = settings?.defaultLowStockThreshold ?? 10.0;

    _nameController = TextEditingController(text: p?.productName ?? '');
    _typeController = TextEditingController(text: p?.type ?? 'Fish');
    _priceController =
        TextEditingController(text: p != null ? '${p.price}' : '');
    _minStockController = TextEditingController(
        text: p != null ? '${p.minimumStock}' : '$defaultThreshold');
    _reorderPointController = TextEditingController(
        text: p != null ? '${p.reorderPoint}' : '${defaultThreshold * 1.5}');

    _category = p?.category ?? ProductConstants.defaultCategories.first;
    _unit = p?.unit ?? ProductConstants.defaultUnits.first;
    _movement = p?.productMovement ?? ProductConstants.movements.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _priceController.dispose();
    _minStockController.dispose();
    _reorderPointController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    final bytes =
        await PhotoUploadService.pickAndCompressImage(fromCamera: fromCamera);
    if (bytes != null) {
      setState(() => _pickedPhotoBytes = bytes);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final useFirebase = ref.read(firestoreActiveProvider);
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
        currentStock: widget.product?.currentStock ?? 0.0,
        createdAt: widget.product?.createdAt ?? DateTime.now(),
      );

      if (ref.read(firestoreActiveProvider)) {
        try {
          await ref
              .read(firestoreProvider)
              .collection('products')
              .doc(productId)
              .set(product.toMap(), SetOptions(merge: true));
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
          LocalDemoStore.instance.saveProduct(product);
        }
      } else {
        LocalDemoStore.instance.saveProduct(product);
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          widget.product == null
              ? 'Product ${product.productName} added.'
              : 'Product ${product.productName} updated.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Failed to save product: $e');
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
          isEdit ? 'Edit Product (${widget.product!.productId})' : 'Add Product'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo preview & picker buttons
                Row(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.sidebarActiveBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _pickedPhotoBytes != null
                          ? Image.memory(_pickedPhotoBytes!, fit: BoxFit.cover)
                          : (widget.product?.photoUrl != null &&
                                  widget.product!.photoUrl!.isNotEmpty)
                              ? Image.network(widget.product!.photoUrl!,
                                  fit: BoxFit.cover)
                              : const Icon(Icons.set_meal_outlined,
                                  size: 32, color: AppColors.sidebarActiveBlue),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickImage(fromCamera: false),
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 18),
                            label: const Text('Choose Photo'),
                          ),
                          // Camera is only offered on Android.
                          if (PhotoUploadService.isAndroid)
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(fromCamera: true),
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 18),
                              label: const Text('Take Photo'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration:
                      const InputDecoration(labelText: 'Product Name *'),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Product Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            categories.contains(_category) ? _category : categories.first,
                        decoration:
                            const InputDecoration(labelText: 'Category *'),
                        items: categories
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _category = v ?? categories.first),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _typeController,
                        decoration: const InputDecoration(
                          labelText: 'Type (e.g. Fish, Mollusk) *',
                        ),
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
                      child: DropdownButtonFormField<String>(
                        initialValue: units.contains(_unit) ? _unit : units.first,
                        decoration: const InputDecoration(labelText: 'Unit *'),
                        items: units
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _unit = v ?? units.first),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Price (PHP) *',
                          prefixText: 'PHP ',
                        ),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Price'),
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
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Minimum Stock *'),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Minimum Stock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderPointController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Reorder Point *'),
                        validator: (v) =>
                            AppValidators.nonNegativeNumber(v, 'Reorder Point'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _movement,
                  decoration:
                      const InputDecoration(labelText: 'Product Movement *'),
                  items: ProductConstants.movements
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(
                      () => _movement = v ?? ProductConstants.movements.first),
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
          child: _isSaving
              ? const CatchUpButtonLoading(
                  label: 'Loading...',
                  forDarkBackground: true,
                )
              : Text(isEdit ? 'Save Changes' : 'Add Product'),
        ),
      ],
    );
  }
}

/// Product detail screen showing product summary and full transaction & waste history.
class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsStreamProvider).value ?? [];
    final product =
        products.where((p) => p.productId == productId).firstOrNull;
    final stockMap = ref.watch(calculatedStockMapProvider);
    final allTransactions =
        ref.watch(transactionsStreamProvider).value ?? [];
    final allWaste = ref.watch(wasteRecordsStreamProvider).value ?? [];

    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Product $productId')),
        body: const Center(child: Text('Product not found.')),
      );
    }

    final currentStock = stockMap[product.productId] ?? product.currentStock;
    final productTxs =
        allTransactions.where((t) => t.productId == productId).toList();
    final productWaste =
        allWaste.where((w) => w.productId == productId).toList();

    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${product.productName} (${product.productId})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: currentStock <= 0
                    ? 'Out of stock'
                    : currentStock <= product.minimumStock
                        ? 'Low'
                        : 'OK',
                color: currentStock <= 0
                    ? AppColors.statusRed
                    : currentStock <= product.minimumStock
                        ? AppColors.statusOrange
                        : AppColors.statusGreen,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  _DetailStat(label: 'Category', value: product.category),
                  _DetailStat(label: 'Type', value: product.type),
                  _DetailStat(
                    label: 'Unit Price',
                    value:
                        '${AppFormatters.formatCurrency(product.price)} / ${product.unit}',
                  ),
                  _DetailStat(
                    label: 'Current Stock',
                    value:
                        '${AppFormatters.formatNumber(currentStock)} ${product.unit}',
                  ),
                  _DetailStat(
                    label: 'Min Stock / Reorder',
                    value:
                        '${AppFormatters.formatNumber(product.minimumStock)} / ${AppFormatters.formatNumber(product.reorderPoint)} ${product.unit}',
                  ),
                  _DetailStat(
                    label: 'Movement',
                    value: product.productMovement,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Transaction & Waste History',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: (productTxs.isEmpty && productWaste.isEmpty)
                ? const Card(
                    child: Center(
                      child: Text(
                          'No stock transactions or waste records for this product yet.'),
                    ),
                  )
                : Card(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        ...productTxs.map(
                          (tx) => ListTile(
                            leading: StatusBadge(
                              label: tx.type,
                              color: tx.isIncoming
                                  ? AppColors.statusGreen
                                  : AppColors.statusOrange,
                            ),
                            title: Text(
                              '${tx.transactionId} | ${AppFormatters.formatNumber(tx.quantity)} ${tx.unit}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: tx.isVoided
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              '${AppFormatters.formatDateTime(tx.dateTime)} | Storage: ${tx.storageName} | By: ${tx.recordedBy}${tx.isVoided ? " (VOIDED: ${tx.voidReason})" : ""}',
                            ),
                          ),
                        ),
                        ...productWaste.map(
                          (w) => ListTile(
                            leading: const StatusBadge(
                              label: 'Waste',
                              color: AppColors.statusRed,
                            ),
                            title: Text(
                              '${w.wasteId} | -${AppFormatters.formatNumber(w.quantity)} ${w.unit} (${w.reason})',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: w.isVoided
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              '${AppFormatters.formatDateTime(w.wasteDateTime)} | By: ${w.recordedBy}${w.isVoided ? " (VOIDED: ${w.voidReason})" : ""}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;

  const _DetailStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

