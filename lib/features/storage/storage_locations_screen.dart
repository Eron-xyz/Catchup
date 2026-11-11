import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/storage_location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Storage Locations module:
/// - Fields: StorageID (auto: ST001...), StorageName, StorageType (Chiller, Freezer, Dry Storage, Ice Box, Other),
///   TemperatureMinC, TemperatureMaxC, StockRotationMethod (FIFO/LIFO/FEFO), LastChecked, Condition, Notes
/// - Highlights rows with Condition != Normal and locations not checked in the last 7 days
/// - Includes "Mark as Checked" button that updates LastChecked to now
/// - Paginated to 10 items per page
class StorageLocationsScreen extends ConsumerStatefulWidget {
  const StorageLocationsScreen({super.key});

  @override
  ConsumerState<StorageLocationsScreen> createState() =>
      _StorageLocationsScreenState();
}

class _StorageLocationsScreenState
    extends ConsumerState<StorageLocationsScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _searchQuery = '';
  String _selectedType = 'All';
  String _selectedCondition = 'All';
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _markAsChecked(StorageLocation st) async {
    if (!ref.read(firestoreActiveProvider)) {
      LocalDemoStore.instance.markStorageChecked(st.storageId);
    } else {
      try {
        await ref
            .read(firestoreProvider)
            .collection('storageLocations')
            .doc(st.storageId)
            .update({'lastChecked': Timestamp.fromDate(DateTime.now())});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.markStorageChecked(st.storageId);
      }
    }

    if (mounted) {
      CatchUpToast.success(
        context,
        '${st.storageName} marked as checked just now.',
      );
    }
  }

  Future<void> _toggleStorageActive(StorageLocation st) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Move to Trash',
      message:
          'Move "${st.storageName}" (${st.storageId}) to Trash? It will be hidden from storage lists and can be restored anytime from Trash in Settings.',
      confirmLabel: 'Move to Trash',
      confirmColor: AppColors.statusRed,
    );
    if (!confirmed) return;

    if (ref.read(firestoreActiveProvider)) {
      try {
        await ref
            .read(firestoreProvider)
            .collection('storageLocations')
            .doc(st.storageId)
            .update({'isActive': false});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
        LocalDemoStore.instance.toggleStorageLocationActive(st.storageId);
      }
    } else {
      LocalDemoStore.instance.toggleStorageLocationActive(st.storageId);
    }
    if (mounted) {
      CatchUpToast.success(context, '${st.storageName} moved to Trash.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageAsync = ref.watch(storageLocationsStreamProvider);
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final canEdit = currentUser?.canEditMasterData ?? false;

    return storageAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (err, _) =>
          Center(child: Text('Error loading storage locations: $err')),
      data: (allLocations) {
        final activeList = allLocations.where((st) => st.isActive).toList();
        if (activeList.isEmpty && allLocations.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.location_on_outlined,
            title: 'No storage locations yet',
            message:
                'No storage locations yet. Tap Add Storage Location to get started.',
            actionLabel: canEdit ? 'Add Storage Location' : null,
            onAction: canEdit ? () => _showStorageDialog(context) : null,
          );
        }

        final filtered = activeList.where((st) {
          final matchesSearch =
              _searchQuery.isEmpty ||
              st.storageName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              st.storageId.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesType =
              _selectedType == 'All' || st.storageType == _selectedType;
          final matchesCondition =
              _selectedCondition == 'All' || st.condition == _selectedCondition;
          return matchesSearch && matchesType && matchesCondition;
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
            title: 'Storage Locations',
            subtitle:
                'Monitor chillers, freezers, temperature ranges, and inspection schedules',
            actions: [
              if (canEdit)
                ElevatedButton.icon(
                  onPressed: () => _showStorageDialog(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Storage Location'),
                ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search ID or name...',
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
                desktopWidth: 190,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text('All Types', overflow: TextOverflow.ellipsis),
                    ),
                    ...StorageConstants.storageTypes.map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(t, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedType = v ?? 'All';
                    _currentPage = 0;
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 210,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedCondition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Conditions',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...StorageConstants.conditions.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedCondition = v ?? 'All';
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
                child: Text('No matching storage locations found.'),
              ),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Temp Range (°C)')),
              DataColumn(label: Text('Rotation')),
              DataColumn(label: Text('Last Checked')),
              DataColumn(label: Text('Condition')),
              DataColumn(label: Text('Actions')),
            ],
            rows: paged.map((st) {
              final highlight = st.needsAlert;
              return DataRow(
                color: highlight
                    ? WidgetStateProperty.all(
                        AppColors.statusOrange.withValues(alpha: 0.08),
                      )
                    : null,
                cells: [
                  DataCell(
                    Text(
                      st.storageId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(Text(st.storageName)),
                  DataCell(Text(st.storageType)),
                  DataCell(
                    Text('${st.temperatureMinC}°C to ${st.temperatureMaxC}°C'),
                  ),
                  DataCell(Text(st.stockRotationMethod)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppFormatters.formatDate(st.lastChecked)),
                        if (st.isOverdueCheck) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            label: '>7d overdue',
                            color: AppColors.statusRed,
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    StatusBadge(
                      label: st.condition,
                      color: st.condition == 'Normal'
                          ? AppColors.statusGreen
                          : st.condition == 'Needs Attention'
                          ? AppColors.statusOrange
                          : AppColors.statusRed,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canEdit)
                          OutlinedButton.icon(
                            onPressed: () => _markAsChecked(st),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                            ),
                            label: const Text('Mark as Checked'),
                          ),
                        if (canEdit) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 19),
                            tooltip: 'Edit',
                            onPressed: () =>
                                _showStorageDialog(context, storage: st),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: AppColors.statusRed,
                            ),
                            tooltip: 'Move to Trash',
                            onPressed: () => _toggleStorageActive(st),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          mobileCards: paged.map((st) {
            return Card(
              color: st.needsAlert
                  ? AppColors.statusOrange.withValues(alpha: 0.08)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${st.storageName} (${st.storageId})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        StatusBadge(
                          label: st.condition,
                          color: st.condition == 'Normal'
                              ? AppColors.statusGreen
                              : st.condition == 'Needs Attention'
                              ? AppColors.statusOrange
                              : AppColors.statusRed,
                        ),
                        if (canEdit) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () =>
                                _showStorageDialog(context, storage: st),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.statusRed,
                            ),
                            tooltip: 'Move to Trash',
                            onPressed: () => _toggleStorageActive(st),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${st.storageType} | Temp: ${st.temperatureMinC}°C to ${st.temperatureMaxC}°C | Rotation: ${st.stockRotationMethod}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last Checked: ${AppFormatters.formatDate(st.lastChecked)}${st.isOverdueCheck ? " (Overdue >7 days!)" : ""}',
                      style: TextStyle(
                        color: st.isOverdueCheck ? AppColors.statusRed : null,
                        fontWeight: st.isOverdueCheck ? FontWeight.w600 : null,
                      ),
                    ),
                    if (st.notes.isNotEmpty) Text('Notes: ${st.notes}'),
                    if (canEdit) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _markAsChecked(st),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Mark as Checked'),
                        ),
                      ),
                    ],
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

  Future<void> _showStorageDialog(
    BuildContext context, {
    StorageLocation? storage,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StorageFormDialog(storage: storage),
    );
  }
}

class _StorageFormDialog extends ConsumerStatefulWidget {
  final StorageLocation? storage;

  const _StorageFormDialog({this.storage});

  @override
  ConsumerState<_StorageFormDialog> createState() => _StorageFormDialogState();
}

class _StorageFormDialogState extends ConsumerState<_StorageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _tempMinController;
  late final TextEditingController _tempMaxController;
  late final TextEditingController _notesController;

  late String _storageType;
  late String _rotationMethod;
  late String _condition;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final st = widget.storage;
    _nameController = TextEditingController(text: st?.storageName ?? '');
    _tempMinController = TextEditingController(
      text: st != null ? '${st.temperatureMinC}' : '-18',
    );
    _tempMaxController = TextEditingController(
      text: st != null ? '${st.temperatureMaxC}' : '4',
    );
    _notesController = TextEditingController(text: st?.notes ?? '');

    _storageType = st?.storageType ?? StorageConstants.storageTypes.first;
    _rotationMethod =
        st?.stockRotationMethod ?? StorageConstants.rotationMethods.first;
    _condition = st?.condition ?? StorageConstants.conditions.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tempMinController.dispose();
    _tempMaxController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final useFirebase = ref.read(firestoreActiveProvider);
      String storageId = widget.storage?.storageId ?? '';
      if (storageId.isEmpty) {
        if (useFirebase) {
          try {
            storageId = await ref
                .read(counterServiceProvider)
                .getNextId(counterKey: 'storageLocations', prefix: 'ST');
          } catch (_) {
            LocalDemoStore.instance.markFirestoreBlocked();
            storageId = LocalDemoStore.instance.nextId('storageLocations', 'ST');
          }
        } else {
          storageId = LocalDemoStore.instance.nextId('storageLocations', 'ST');
        }
      }

      final location = StorageLocation(
        storageId: storageId,
        storageName: _nameController.text.trim(),
        storageType: _storageType,
        temperatureMinC: double.parse(_tempMinController.text.trim()),
        temperatureMaxC: double.parse(_tempMaxController.text.trim()),
        stockRotationMethod: _rotationMethod,
        lastChecked: widget.storage?.lastChecked ?? DateTime.now(),
        condition: _condition,
        notes: _notesController.text.trim(),
        createdAt: widget.storage?.createdAt ?? DateTime.now(),
      );

      if (ref.read(firestoreActiveProvider)) {
        try {
          await ref
              .read(firestoreProvider)
              .collection('storageLocations')
              .doc(storageId)
              .set(location.toMap(), SetOptions(merge: true));
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
          LocalDemoStore.instance.saveStorageLocation(location);
        }
      } else {
        LocalDemoStore.instance.saveStorageLocation(location);
      }

      if (mounted) {
        CatchUpToast.success(
          context,
          widget.storage == null
              ? 'Storage location ${location.storageName} added.'
              : 'Storage location ${location.storageName} updated.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, 'Error saving storage location: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.storage != null;
    return AlertDialog(
      title: Text(
        isEdit
            ? 'Edit Storage (${widget.storage!.storageId})'
            : 'Add Storage Location',
      ),
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
                  decoration: const InputDecoration(
                    labelText: 'Storage Name *',
                  ),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Storage Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _storageType,
                        decoration: const InputDecoration(
                          labelText: 'Storage Type *',
                        ),
                        items: StorageConstants.storageTypes
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(
                          () => _storageType =
                              v ?? StorageConstants.storageTypes.first,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _rotationMethod,
                        decoration: const InputDecoration(
                          labelText: 'Rotation Method *',
                        ),
                        items: StorageConstants.rotationMethods
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(
                          () => _rotationMethod =
                              v ?? StorageConstants.rotationMethods.first,
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
                        controller: _tempMinController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Min Temp (°C) *',
                        ),
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Enter valid °C'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _tempMaxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Max Temp (°C) *',
                        ),
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Enter valid °C'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _condition,
                  decoration: const InputDecoration(labelText: 'Condition *'),
                  items: StorageConstants.conditions
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(
                    () => _condition = v ?? StorageConstants.conditions.first,
                  ),
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
          child: Text(isEdit ? 'Save Changes' : 'Add Storage Location'),
        ),
      ],
    );
  }
}
