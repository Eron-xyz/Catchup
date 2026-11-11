import 'package:cloud_firestore/cloud_firestore.dart';

/// User roles in CatchUP:
/// - Admin: manages all system modules (Dashboard, Inventory, Transactions,
///   Products, Suppliers, Storage Locations, Waste Records, Reports, Users, Settings)
/// - Manager: manages all except Inventory, Storage Locations, and Waste Records
///   (Dashboard, Transactions, Products, Suppliers, Reports, Users, Settings)
/// - Staff: manages Dashboard, Inventory, Storage Locations, and Waste Records
enum UserRole {
  admin('Admin'),
  manager('Manager'),
  staff('Staff');

  final String label;
  const UserRole(this.label);

  static UserRole fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'manager':
        return UserRole.manager;
      default:
        return UserRole.staff;
    }
  }
}

class AppUser {
  final String uid;
  final String userEmail;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;

  const AppUser({
    required this.uid,
    required this.userEmail,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isManager => role == UserRole.manager;
  bool get isStaff => role == UserRole.staff;

  /// Every role can manage the modules assigned to their role:
  /// - Admin: all modules
  /// - Manager: Dashboard, Transactions, Products, Suppliers, Reports, Users, Settings
  /// - Staff: Dashboard, Inventory, Storage Locations, Waste Records
  bool get canEditMasterData => true;
  bool get canVoidRecords => true;
  bool get canManageInventory => isAdmin || isStaff;
  bool get canManageStorage => isAdmin || isStaff;
  bool get canManageWaste => isAdmin || isStaff;
  bool get canManageTransactions => isAdmin || isManager;
  bool get canManageProducts => isAdmin || isManager;
  bool get canManageSuppliers => isAdmin || isManager;
  bool get canViewReports => isAdmin || isManager;
  bool get canViewUsers => isAdmin || isManager;
  bool get canManageUsers => isAdmin || isManager;
  bool get canManageSettings => isAdmin || isManager;

  /// Returns true if this user's role is permitted to view and manage [route].
  bool canAccessRoute(String route) {
    if (isAdmin) return true;
    if (route.startsWith('/dashboard')) return true;

    if (isManager) {
      if (route.startsWith('/inventory') ||
          route.startsWith('/storage') ||
          route.startsWith('/waste')) {
        return false;
      }
      return true;
    }

    if (isStaff) {
      return route.startsWith('/dashboard') ||
          route.startsWith('/inventory') ||
          route.startsWith('/storage') ||
          route.startsWith('/waste');
    }

    return false;
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      userEmail: (data['userEmail'] ?? data['email'] ?? '') as String,
      fullName: (data['fullName'] ?? '') as String,
      role: UserRole.fromString(data['role'] as String?),
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userEmail': userEmail,
      'fullName': fullName,
      'role': role.label,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  AppUser copyWith({
    String? fullName,
    UserRole? role,
    bool? isActive,
  }) {
    return AppUser(
      uid: uid,
      userEmail: userEmail,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
