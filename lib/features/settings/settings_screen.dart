import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/export_service.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/app_settings.dart';
import 'package:catchup/models/app_user.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/storage_location.dart';
import 'package:catchup/models/supplier.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String appVersion = '1.0.0';

/// Settings module (Admin only):
/// - Business Name, Address, Contact Number
/// - Appearance: PHP currency (fixed) and Light/Dark theme switch
/// - Backup/Export all data to CSV
/// - App version and About with CatchUP logo
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _exporting = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _contact]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fill the form once from the saved settings (or defaults if none exist yet).
  void _load(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _name.text = s.businessName;
    _address.text = s.address;
    _contact.text = s.contactNumber;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final current =
          ref.read(appSettingsStreamProvider).value ?? const AppSettings();
      final s = current.copyWith(
        businessName: _name.text.trim(),
        address: _address.text.trim(),
        contactNumber: _contact.text.trim(),
        currency: 'PHP',
      );
      LocalDemoStore.instance.saveSettings(s);
      if (ref.read(firestoreActiveProvider)) {
        try {
          await ref
              .read(firestoreProvider)
              .collection('settings')
              .doc('general')
              .set(s.toMap());
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
        }
      }
      if (mounted) {
        CatchUpToast.success(context, 'Settings saved.');
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Could not save settings: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Backup: export each collection to its own CSV file.
  Future<void> _backup() async {
    setState(() => _exporting = true);
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      String? lastMessage;
      if (ref.read(firestoreActiveProvider)) {
        try {
          final db = ref.read(firestoreProvider);
          for (final name in [
            'products',
            'suppliers',
            'storageLocations',
            'stockTransactions',
            'wasteRecords',
            'users',
          ]) {
            final snap = await db.collection(name).get();
            final keys = <String>{};
            for (final d in snap.docs) {
              keys.addAll(d.data().keys);
            }
            final headers = keys.toList()..sort();
            final rows = snap.docs.map((d) {
              return headers.map((k) {
                final v = d.data()[k];
                if (v is Timestamp) return v.toDate().toIso8601String();
                return v?.toString() ?? '';
              }).toList();
            }).toList();
            lastMessage = await ExportService.exportCsv(
              TableData(title: name, headers: headers, rows: rows),
              'catchup_${name}_$stamp.csv',
            );
            if (lastMessage == null) break;
          }
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
        }
      }
      if (!ref.read(firestoreActiveProvider) || lastMessage == null) {
        final store = LocalDemoStore.instance;
        final table = TableData(
          title: 'Products',
          headers: [
            'ProductID',
            'Name',
            'Category',
            'Unit',
            'Price (PHP)',
            'Stock',
          ],
          rows: store.products
              .map(
                (p) => [
                  p.productId,
                  p.productName,
                  p.category,
                  p.unit,
                  '${p.price}',
                  '${p.currentStock}',
                ],
              )
              .toList(),
        );
        lastMessage = await ExportService.exportCsv(
          table,
          'catchup_backup_$stamp.csv',
        );
      }
      if (mounted && lastMessage != null) {
        CatchUpToast.success(context, 'Backup finished. $lastMessage');
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Backup failed: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appSettingsStreamProvider);
    return async.when(
      loading: () =>
          const CatchUpLoadingIndicator(message: 'Loading settings...'),
      error: (e, _) => Center(child: Text('Error loading settings: $e')),
      data: (settings) {
        _load(settings);
        final isMobile = MediaQuery.sizeOf(context).width < 600;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final borderColor = isDark
            ? AppColors.darkBorder
            : AppColors.lightBorder;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Row with Save Settings on Upper Right
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: borderColor, width: 1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settings',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage business profile and system backups',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.shrink()
                            : const Icon(Icons.save_outlined, size: 18),
                        label: _saving
                            ? const CatchUpButtonLoading(
                                label: 'Loading...',
                                forDarkBackground: true,
                              )
                            : const Text('Save Settings'),
                      ),
                    ],
                  ),
                ),

                _section('Business Information', borderColor, [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Business Name *',
                    ),
                    validator: (v) =>
                        AppValidators.requiredField(v, 'Business name'),
                  ),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  TextFormField(
                    controller: _contact,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                    ),
                  ),
                ]),

                _section('Data Backup', borderColor, [
                  const Text(
                    'Export products, suppliers, storage locations, transactions, waste records, and users to CSV files.',
                  ),
                  Align(
                    alignment: isMobile
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: SizedBox(
                      width: isMobile ? double.infinity : null,
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : _backup,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(
                          _exporting
                              ? 'Exporting...'
                              : 'Export All Data to CSV',
                        ),
                      ),
                    ),
                  ),
                ]),

                // Trash / Soft Deleted Records
                _section('Trash (Soft-Deleted Items)', borderColor, [
                  const Text(
                    'View and restore products, suppliers, and user accounts that have been moved to Trash.',
                  ),
                  _TrashManagerWidget(ref: ref),
                ]),

                // About CatchUP (No card box, clean frameless layout with thin top line)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: borderColor, width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'About CatchUP',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      CatchUpLogo(
                        iconSize: 56,
                        fontSize: 24,
                        showTagline: true,
                        forDarkBackground: isDark,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CatchUP — Seafood Inventory Management System',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text('Version $appVersion'),
                      const SizedBox(height: 4),
                      const Text('Built for Roxas City, Capiz, Philippines.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(String title, Color borderColor, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 1),
                  ),
                ),
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 14),
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Trash Manager Widget embedded in Settings allowing users to view and
/// restore soft-deleted Products, Suppliers, and Users with 1 click.
class _TrashManagerWidget extends StatefulWidget {
  final WidgetRef ref;

  const _TrashManagerWidget({required this.ref});

  @override
  State<_TrashManagerWidget> createState() => _TrashManagerWidgetState();
}

class _TrashManagerWidgetState extends State<_TrashManagerWidget> {
  String _activeTab = 'Products';

  Future<void> _restoreProduct(Product p) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restore Product',
      message: 'Restore "${p.productName}" (${p.productId}) back to active inventory?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.statusGreen,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('products')
            .doc(p.productId)
            .update({'isActive': true});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleProductActive(p.productId);
      }
    } else {
      LocalDemoStore.instance.toggleProductActive(p.productId);
    }
    if (mounted) {
      CatchUpToast.success(context, '${p.productName} restored successfully.');
    }
  }

  Future<void> _permanentDeleteProduct(Product p) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Permanently Delete Product',
      message:
          'Permanently delete "${p.productName}" (${p.productId}) from Cloud Firestore? This action CANNOT be undone.',
      confirmLabel: 'Delete Permanently',
      confirmColor: AppColors.statusRed,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('products')
            .doc(p.productId)
            .delete();
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    LocalDemoStore.instance.permanentlyDeleteProduct(p.productId);
    if (mounted) {
      CatchUpToast.success(context, '${p.productName} permanently deleted.');
    }
  }

  Future<void> _restoreSupplier(Supplier s) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restore Supplier',
      message: 'Restore "${s.supplierName}" back to active suppliers?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.statusGreen,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('suppliers')
            .doc(s.supplierId)
            .update({'isActive': true});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleSupplierActive(s.supplierId);
      }
    } else {
      LocalDemoStore.instance.toggleSupplierActive(s.supplierId);
    }
    if (mounted) {
      CatchUpToast.success(context, '${s.supplierName} restored successfully.');
    }
  }

  Future<void> _permanentDeleteSupplier(Supplier s) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Permanently Delete Supplier',
      message:
          'Permanently delete "${s.supplierName}" (${s.supplierId}) from Cloud Firestore? This action CANNOT be undone.',
      confirmLabel: 'Delete Permanently',
      confirmColor: AppColors.statusRed,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('suppliers')
            .doc(s.supplierId)
            .delete();
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    LocalDemoStore.instance.permanentlyDeleteSupplier(s.supplierId);
    if (mounted) {
      CatchUpToast.success(context, '${s.supplierName} permanently deleted.');
    }
  }

  Future<void> _restoreStorageLocation(StorageLocation st) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restore Storage Location',
      message:
          'Restore "${st.storageName}" (${st.storageId}) back to active storage locations?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.statusGreen,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('storageLocations')
            .doc(st.storageId)
            .update({'isActive': true});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleStorageLocationActive(st.storageId);
      }
    } else {
      LocalDemoStore.instance.toggleStorageLocationActive(st.storageId);
    }
    if (mounted) {
      CatchUpToast.success(context, '${st.storageName} restored successfully.');
    }
  }

  Future<void> _permanentDeleteStorageLocation(StorageLocation st) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Permanently Delete Storage Location',
      message:
          'Permanently delete "${st.storageName}" (${st.storageId}) from Cloud Firestore? This action CANNOT be undone.',
      confirmLabel: 'Delete Permanently',
      confirmColor: AppColors.statusRed,
    );
    if (!confirmed) return;

    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('storageLocations')
            .doc(st.storageId)
            .delete();
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    LocalDemoStore.instance.permanentlyDeleteStorageLocation(st.storageId);
    if (mounted) {
      CatchUpToast.success(context, '${st.storageName} permanently deleted.');
    }
  }

  Future<void> _restoreUser(AppUser u) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restore User',
      message: 'Restore "${u.fullName}" (${u.userEmail}) from Trash?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.statusGreen,
    );
    if (!confirmed) return;

    LocalDemoStore.instance.updateUser(u.uid, isActive: true);
    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('users')
            .doc(u.uid)
            .update({'isActive': true});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    if (mounted) {
      CatchUpToast.success(context, '${u.fullName} restored successfully.');
    }
  }

  Future<void> _permanentDeleteUser(AppUser u) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Permanently Delete User',
      message:
          'Permanently delete "${u.fullName}" (${u.userEmail}) from Cloud Firestore? This action CANNOT be undone.',
      confirmLabel: 'Delete Permanently',
      confirmColor: AppColors.statusRed,
    );
    if (!confirmed) return;

    LocalDemoStore.instance.permanentlyDeleteUser(u.uid);
    if (widget.ref.read(firestoreActiveProvider)) {
      try {
        await widget.ref
            .read(firestoreProvider)
            .collection('users')
            .doc(u.uid)
            .delete();
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    if (mounted) {
      CatchUpToast.success(context, '${u.fullName} permanently deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.ref.watch(productsStreamProvider).value ?? [];
    final suppliers = widget.ref.watch(suppliersStreamProvider).value ?? [];
    final storages =
        widget.ref.watch(storageLocationsStreamProvider).value ?? [];
    final users = widget.ref.watch(usersStreamProvider).value ?? [];

    final trashedProducts = products.where((p) => !p.isActive).toList();
    final trashedSuppliers = suppliers.where((s) => !s.isActive).toList();
    final trashedStorages = storages.where((st) => !st.isActive).toList();
    final trashedUsers = users.where((u) => !u.isActive).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-tabs for Trashed Categories
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrashTabPill(
                label: 'Products (${trashedProducts.length})',
                isSelected: _activeTab == 'Products',
                icon: Icons.view_in_ar_outlined,
                onTap: () => setState(() => _activeTab = 'Products'),
              ),
              _TrashTabPill(
                label: 'Suppliers (${trashedSuppliers.length})',
                isSelected: _activeTab == 'Suppliers',
                icon: Icons.people_outline,
                onTap: () => setState(() => _activeTab = 'Suppliers'),
              ),
              _TrashTabPill(
                label: 'Storage (${trashedStorages.length})',
                isSelected: _activeTab == 'Storage',
                icon: Icons.location_on_outlined,
                onTap: () => setState(() => _activeTab = 'Storage'),
              ),
              _TrashTabPill(
                label: 'Users (${trashedUsers.length})',
                isSelected: _activeTab == 'Users',
                icon: Icons.person_outline,
                onTap: () => setState(() => _activeTab = 'Users'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Trashed Items List
          if (_activeTab == 'Products') ...[
            if (trashedProducts.isEmpty)
              const _EmptyTrashNote(message: 'No deleted products in Trash.')
            else
              for (final p in trashedProducts)
                _TrashItemRow(
                  title: p.productName,
                  subtitle: 'ID: ${p.productId} | Category: ${p.category} | ${p.unit}',
                  onRestore: () => _restoreProduct(p),
                  onPermanentDelete: () => _permanentDeleteProduct(p),
                ),
          ] else if (_activeTab == 'Suppliers') ...[
            if (trashedSuppliers.isEmpty)
              const _EmptyTrashNote(message: 'No deleted suppliers in Trash.')
            else
              for (final s in trashedSuppliers)
                _TrashItemRow(
                  title: s.supplierName,
                  subtitle: 'ID: ${s.supplierId} | Contact: ${s.contactPerson} | ${s.phone}',
                  onRestore: () => _restoreSupplier(s),
                  onPermanentDelete: () => _permanentDeleteSupplier(s),
                ),
          ] else if (_activeTab == 'Storage') ...[
            if (trashedStorages.isEmpty)
              const _EmptyTrashNote(message: 'No deleted storage locations in Trash.')
            else
              for (final st in trashedStorages)
                _TrashItemRow(
                  title: st.storageName,
                  subtitle: 'ID: ${st.storageId} | Type: ${st.storageType} | ${st.condition}',
                  onRestore: () => _restoreStorageLocation(st),
                  onPermanentDelete: () => _permanentDeleteStorageLocation(st),
                ),
          ] else if (_activeTab == 'Users') ...[
            if (trashedUsers.isEmpty)
              const _EmptyTrashNote(message: 'No deleted user accounts in Trash.')
            else
              for (final u in trashedUsers)
                _TrashItemRow(
                  title: u.fullName,
                  subtitle: 'Email: ${u.userEmail} | Role: ${u.role.label}',
                  onRestore: () => _restoreUser(u),
                  onPermanentDelete: () => _permanentDeleteUser(u),
                ),
          ],
        ],
      ),
    );
  }
}

class _TrashTabPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  const _TrashTabPill({
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.sidebarActiveBlue
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrashNote extends StatelessWidget {
  final String message;

  const _EmptyTrashNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashItemRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  const _TrashItemRow({
    required this.title,
    required this.subtitle,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.statusRed,
              side: BorderSide(
                color: AppColors.statusRed.withValues(alpha: 0.5),
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: onPermanentDelete,
            icon: const Icon(Icons.delete_forever_outlined, size: 15),
            label: const Text('Delete Permanently', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusGreen,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: onRestore,
            icon: const Icon(Icons.restore_from_trash_outlined, size: 15),
            label: const Text('Restore', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

