import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/supplier.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Suppliers module:
/// - Fields: SupplierID (auto: S001...), SupplierName, ContactPerson, Phone, Email, Address, Notes, IsActive
/// - Validates PH phone format (09XXXXXXXXX) and email format
/// - Tap-to-call and tap-to-email actions
/// - Paginated to 10 items per page
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _launchCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          CatchUpToast.info(context, 'Call: $phone');
        }
      }
    } catch (_) {
      if (mounted) {
        CatchUpToast.info(context, 'Call: $phone');
      }
    }
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          CatchUpToast.info(context, 'Email: $email');
        }
      }
    } catch (_) {
      if (mounted) {
        CatchUpToast.info(context, 'Email: $email');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canEdit = currentUser?.canEditMasterData ?? false;

    return suppliersAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) => Center(child: Text('Error loading suppliers: $err')),
      data: (allSuppliers) {
        final baseList = allSuppliers.where((s) => s.isActive).toList();

        if (baseList.isEmpty && allSuppliers.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.people_outline,
            title: 'No suppliers yet',
            message: 'No suppliers yet. Tap Add Supplier to get started.',
            actionLabel: canEdit ? 'Add Supplier' : null,
            onAction: canEdit ? () => _showSupplierDialog(context) : null,
          );
        }

        final filtered = baseList.where((s) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return s.supplierId.toLowerCase().contains(q) ||
              s.supplierName.toLowerCase().contains(q) ||
              s.contactPerson.toLowerCase().contains(q) ||
              s.phone.contains(q) ||
              s.address.toLowerCase().contains(q);
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil();
        final safePage =
            totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
        final visible =
            filtered.skip(safePage * _pageSize).take(_pageSize).toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Seafood Suppliers',
            subtitle:
                'Manage local Roxas City & Capiz seafood suppliers and contact details',
            actions: [
              if (canEdit)
                ElevatedButton.icon(
                  onPressed: () => _showSupplierDialog(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Supplier'),
                ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search supplier, contact, or phone...',
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
            ],
          ),
          isEmpty: filtered.isEmpty,
          emptyChild: const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No matching suppliers found.')),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: [
              const DataColumn(label: Text('ID')),
              const DataColumn(label: Text('Supplier Name')),
              const DataColumn(label: Text('Contact Person')),
              const DataColumn(label: Text('Phone')),
              const DataColumn(label: Text('Email')),
              const DataColumn(label: Text('Address')),
              const DataColumn(label: Text('Status')),
              if (canEdit) const DataColumn(label: Text('Actions')),
            ],
            rows: visible.map((s) {
              return DataRow(
                cells: [
                  DataCell(Text(
                    s.supplierId,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )),
                  DataCell(Text(s.supplierName)),
                  DataCell(Text(s.contactPerson)),
                  DataCell(
                    InkWell(
                      onTap: () => _launchCall(s.phone),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone,
                              size: 15, color: AppColors.sidebarActiveBlue),
                          const SizedBox(width: 4),
                          Text(
                            s.phone,
                            style: const TextStyle(
                              color: AppColors.sidebarActiveBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    InkWell(
                      onTap: () => _launchEmail(s.email),
                      child: Text(
                        s.email,
                        style: const TextStyle(
                          color: AppColors.sidebarActiveBlue,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(s.address)),
                  DataCell(StatusBadge(
                    label: s.isActive ? 'Active' : 'Inactive',
                    color: s.isActive ? AppColors.statusGreen : Colors.grey,
                  )),
                  if (canEdit)
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          onPressed: () => _showSupplierDialog(
                            context,
                            supplier: s,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: AppColors.statusRed,
                          ),
                          tooltip: 'Move to Trash',
                          onPressed: () => _toggleActive(s),
                        ),
                      ],
                    )),
                ],
              );
            }).toList(),
          ),
          mobileCards: visible.map((s) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s.supplierName} (${s.supplierId})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        StatusBadge(
                          label: s.isActive ? 'Active' : 'Inactive',
                          color:
                              s.isActive ? AppColors.statusGreen : Colors.grey,
                        ),
                        if (canEdit) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit Supplier',
                            onPressed: () => _showSupplierDialog(
                              context,
                              supplier: s,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.statusRed,
                            ),
                            tooltip: 'Move to Trash',
                            onPressed: () => _toggleActive(s),
                          ),
                        ],
                      ],
                    ),
                    Text('Contact: ${s.contactPerson}'),
                    Text('Address: ${s.address}'),
                    if (s.notes.isNotEmpty) Text('Notes: ${s.notes}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _launchCall(s.phone),
                          icon: const Icon(Icons.call, size: 16),
                          label: Text(s.phone),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _launchEmail(s.email),
                          icon: const Icon(Icons.email_outlined, size: 16),
                          label: Text(s.email),
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
            totalItems: filtered.length,
            pageSize: _pageSize,
            onPageChanged: (p) => setState(() => _currentPage = p),
          ),
        );
      },
    );
  }

  Future<void> _toggleActive(Supplier s) async {
    final isDeleting = s.isActive;
    final confirmed = await showConfirmDialog(
      context: context,
      title: isDeleting ? 'Move to Trash' : 'Restore Supplier',
      message: isDeleting
          ? 'Are you sure you want to move ${s.supplierName} to Trash? It will be hidden from active lists and can be restored anytime from Trash in Settings.'
          : 'Restore ${s.supplierName} back to active suppliers?',
      confirmLabel: isDeleting ? 'Move to Trash' : 'Restore',
      confirmColor: isDeleting ? AppColors.statusRed : AppColors.statusGreen,
    );
    if (!confirmed) return;

    if (ref.read(firestoreActiveProvider)) {
      try {
        await ref
            .read(firestoreProvider)
            .collection('suppliers')
            .doc(s.supplierId)
            .update({'isActive': !s.isActive});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleSupplierActive(s.supplierId);
      }
    } else {
      LocalDemoStore.instance.toggleSupplierActive(s.supplierId);
    }
    if (mounted) {
      CatchUpToast.success(
        context,
        isDeleting
            ? '${s.supplierName} moved to Trash.'
            : '${s.supplierName} restored from Trash.',
      );
    }
  }

  Future<void> _showSupplierDialog(BuildContext context,
      {Supplier? supplier}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SupplierFormDialog(supplier: supplier),
    );
  }
}

class _SupplierFormDialog extends ConsumerStatefulWidget {
  final Supplier? supplier;

  const _SupplierFormDialog({this.supplier});

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameController = TextEditingController(text: s?.supplierName ?? '');
    _contactController = TextEditingController(text: s?.contactPerson ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    _notesController = TextEditingController(text: s?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final useFirebase = ref.read(firestoreActiveProvider);
      String supplierId = widget.supplier?.supplierId ?? '';
      if (supplierId.isEmpty) {
        if (useFirebase) {
          try {
            supplierId = await ref
                .read(counterServiceProvider)
                .getNextId(counterKey: 'suppliers', prefix: 'S');
          } catch (_) {
            LocalDemoStore.instance.markFirestoreBlocked();
            supplierId = LocalDemoStore.instance.nextId('suppliers', 'S');
          }
        } else {
          supplierId = LocalDemoStore.instance.nextId('suppliers', 'S');
        }
      }

      final supplier = Supplier(
        supplierId: supplierId,
        supplierName: _nameController.text.trim(),
        contactPerson: _contactController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        notes: _notesController.text.trim(),
        isActive: widget.supplier?.isActive ?? true,
        createdAt: widget.supplier?.createdAt ?? DateTime.now(),
      );

      if (ref.read(firestoreActiveProvider)) {
        try {
          await ref
              .read(firestoreProvider)
              .collection('suppliers')
              .doc(supplierId)
              .set(supplier.toMap(), SetOptions(merge: true));
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
          LocalDemoStore.instance.saveSupplier(supplier);
        }
      } else {
        LocalDemoStore.instance.saveSupplier(supplier);
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          widget.supplier == null
              ? 'Supplier ${supplier.supplierName} added.'
              : 'Supplier ${supplier.supplierName} updated.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Error saving supplier: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;
    return AlertDialog(
      title: Text(isEdit
          ? 'Edit Supplier (${widget.supplier!.supplierId})'
          : 'Add Supplier'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration:
                      const InputDecoration(labelText: 'Supplier Name *'),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Supplier Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactController,
                  decoration:
                      const InputDecoration(labelText: 'Contact Person *'),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Contact Person'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'PH Mobile Phone (09XXXXXXXXX) *',
                    hintText: '09171234567',
                  ),
                  validator: AppValidators.phPhone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                  validator: AppValidators.email,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address *'),
                  validator: (v) => AppValidators.requiredField(v, 'Address'),
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
          onPressed: _isSaving ? null : _save,
          child: Text(isEdit ? 'Save Changes' : 'Add Supplier'),
        ),
      ],
    );
  }
}
