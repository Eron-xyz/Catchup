import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Users module. Admin has full control, Manager is view-only.
/// - Admin: create user, edit name/role, deactivate/reactivate, send password reset (no hard delete)
/// - An admin cannot deactivate or demote themselves
/// - The system must always keep at least one active Admin
/// - Paginated to 10 items per page
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final InputDebouncer _searchDebouncer = InputDebouncer();
  String _search = '';
  String _roleFilter = 'All';
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    CatchUpToast.show(context, msg, isError: error);
  }

  int _activeAdminCount(List<AppUser> all) =>
      all.where((u) => u.isAdmin && u.isActive).length;

  Future<void> _toggleActive(
      AppUser target, List<AppUser> all, AppUser me) async {
    if (target.uid == me.uid) {
      _snack('You cannot move your own account to Trash.', error: true);
      return;
    }
    if (target.isActive && target.isAdmin && _activeAdminCount(all) <= 1) {
      _snack('At least one active Admin must remain.', error: true);
      return;
    }
    final isDeleting = target.isActive;
    final ok = await showConfirmDialog(
      context: context,
      title: isDeleting ? 'Move to Trash' : 'Restore User',
      message: isDeleting
          ? 'Move ${target.fullName} (${target.userEmail}) to Trash? The user will not be able to log in until restored from Trash.'
          : 'Restore ${target.fullName} (${target.userEmail}) from Trash?',
      confirmLabel: isDeleting ? 'Move to Trash' : 'Restore',
      confirmColor:
          isDeleting ? AppColors.statusRed : AppColors.statusGreen,
    );
    if (!ok) return;
    LocalDemoStore.instance
        .updateUser(target.uid, isActive: !target.isActive);
    if (ref.read(firestoreActiveProvider)) {
      try {
        await ref
            .read(firestoreProvider)
            .collection('users')
            .doc(target.uid)
            .update({'isActive': !target.isActive});
      } catch (_) {
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }
    if (mounted) {
      _snack(isDeleting
          ? '${target.fullName} moved to Trash.'
          : '${target.fullName} restored from Trash.');
    }
  }

  Future<void> _resetPassword(AppUser target) async {
    try {
      await ref.read(authServiceProvider).sendPasswordReset(target.userEmail);
      _snack('Password reset email sent to ${target.userEmail}.');
    } catch (e) {
      _snack(AuthService.friendlyErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersStreamProvider);
    final me = ref.watch(currentUserProfileProvider).value;
    final isAdmin = me?.canManageUsers ?? false;

    return usersAsync.when(
      loading: () => const CatchUpModuleSkeleton(),
      error: (e, _) => Center(child: Text('Error loading users: $e')),
      data: (all) {
        final activeUsers = all.where((u) => u.isActive).toList();
        if (activeUsers.isEmpty && all.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.group_outlined,
            title: 'No users yet',
            message: 'No users yet. Tap Add User to get started.',
            actionLabel: isAdmin ? 'Add User' : null,
            onAction: isAdmin ? () => _openUserDialog(null, all) : null,
          );
        }

        final filtered = activeUsers.where((u) {
          final q = _search.toLowerCase();
          final matchSearch = q.isEmpty ||
              u.fullName.toLowerCase().contains(q) ||
              u.userEmail.toLowerCase().contains(q);
          final matchRole = _roleFilter == 'All' || u.role.label == _roleFilter;
          return matchSearch && matchRole;
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil();
        final safePage =
            totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
        final paged =
            filtered.skip(safePage * _pageSize).take(_pageSize).toList();

        return ResponsiveModulePage(
          header: ResponsivePageHeader(
            title: 'Users',
            subtitle: isAdmin
                ? 'Create accounts and manage roles'
                : 'View-only: only Admins can change users',
            actions: [
              if (isAdmin)
                ElevatedButton.icon(
                  onPressed: () => _openUserDialog(null, all),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add User'),
                ),
            ],
          ),
          filterBar: ResponsiveFilterCard(
            items: [
              ResponsiveFilterItem(
                desktopWidth: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name or email...',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (v) => _searchDebouncer.run(() {
                    if (!mounted) return;
                    setState(() {
                      _search = v;
                      _currentPage = 0;
                    });
                  }),
                ),
              ),
              ResponsiveFilterItem(
                desktopWidth: 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _roleFilter,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: ['All', ...UserRole.values.map((r) => r.label)]
                      .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _roleFilter = v ?? 'All';
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
              child: Center(child: Text('No users match your search.')),
            ),
          ),
          desktopTable: FullWidthDataTable(
            columns: [
              const DataColumn(label: Text('Full Name')),
              const DataColumn(label: Text('Email')),
              const DataColumn(label: Text('Role')),
              const DataColumn(label: Text('Active')),
              const DataColumn(label: Text('Created')),
              if (isAdmin) const DataColumn(label: Text('Actions')),
            ],
            rows: paged
                .map((u) => DataRow(cells: [
                      DataCell(Text(u.fullName)),
                      DataCell(Text(u.userEmail)),
                      DataCell(Text(u.role.label)),
                      DataCell(StatusBadge(
                        label: u.isActive ? 'Yes' : 'No',
                        color: u.isActive ? AppColors.statusGreen : Colors.grey,
                      )),
                      DataCell(Text(AppFormatters.formatDate(u.createdAt))),
                      if (isAdmin) DataCell(_actions(u, all, me!)),
                    ]))
                .toList(),
          ),
          mobileCards: paged.map((u) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: AppColors.sidebarNavy,
                      child: Text(
                        u.fullName.isNotEmpty
                            ? u.fullName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          Text(
                            u.userEmail,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              StatusBadge(
                                label: u.role.label,
                                color: AppColors.sidebarActiveBlue,
                              ),
                              StatusBadge(
                                label: u.isActive ? 'Active' : 'Inactive',
                                color: u.isActive
                                    ? AppColors.statusGreen
                                    : Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin) _actions(u, all, me!),
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

  Widget _actions(AppUser u, List<AppUser> all, AppUser me) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 19),
          tooltip: 'Edit name / role',
          onPressed: () => _openUserDialog(u, all),
        ),
        IconButton(
          icon: const Icon(Icons.lock_reset, size: 19),
          tooltip: 'Send password reset',
          onPressed: () => _resetPassword(u),
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            size: 19,
            color: AppColors.statusRed,
          ),
          tooltip: 'Move to Trash',
          onPressed: () => _toggleActive(u, all, me),
        ),
      ],
    );
  }

  Future<void> _openUserDialog(AppUser? user, List<AppUser> all) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(user: user, allUsers: all),
    );
  }
}

class _UserFormDialog extends ConsumerStatefulWidget {
  final AppUser? user;
  final List<AppUser> allUsers;

  const _UserFormDialog({this.user, required this.allUsers});

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late UserRole _role;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user?.fullName ?? '');
    _email = TextEditingController(text: widget.user?.userEmail ?? '');
    _role = widget.user?.role ?? UserRole.staff;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final editing = widget.user;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (editing == null) {
        await ref.read(authServiceProvider).createUserByAdmin(
              fullName: _name.text,
              email: _email.text,
              password: _password.text,
              role: _role,
            );
      } else {
        LocalDemoStore.instance.updateUser(
          editing.uid,
          fullName: _name.text.trim(),
          role: _role,
        );
        if (ref.read(firestoreActiveProvider)) {
          try {
            await ref
                .read(firestoreProvider)
                .collection('users')
                .doc(editing.uid)
                .update({
              'fullName': _name.text.trim(),
              'role': _role.label,
            });
          } catch (_) {
            LocalDemoStore.instance.markFirestoreBlocked();
          }
        }
      }
      if (mounted) {
        CatchUpToast.success(
          context,
          editing == null
              ? 'User ${_name.text.trim()} (${_role.label}) created.'
              : 'User ${_name.text.trim()} updated to ${_role.label}.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      final msg = AuthService.friendlyErrorMessage(e);
      setState(() => _error = msg);
      if (mounted) {
        CatchUpToast.error(context, msg);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.user != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit User' : 'Add User'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.statusRed)),
                  ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Full Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Username or Email *',
                    hintText: 'e.g. maria or maria@catchup.ph',
                  ),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Username or Email'),
                ),
                if (!isEdit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Temporary Password *'),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'At least 6 characters.'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  isExpanded: true,
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role *'),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label,
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (r) =>
                      setState(() => _role = r ?? UserRole.staff),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(isEdit ? 'Save Changes' : 'Create User'),
        ),
      ],
    );
  }
}
