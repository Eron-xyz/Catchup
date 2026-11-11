import 'package:cloud_firestore/cloud_firestore.dart';

class Supplier {
  final String supplierId; // S001...
  final String supplierName;
  final String contactPerson;
  final String phone; // 09XXXXXXXXX
  final String email;
  final String address;
  final String notes;
  final bool isActive;
  final DateTime createdAt;

  const Supplier({
    required this.supplierId,
    required this.supplierName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.notes,
    required this.isActive,
    required this.createdAt,
  });

  factory Supplier.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Supplier(
      supplierId: (data['supplierId'] ?? doc.id) as String,
      supplierName: (data['supplierName'] ?? '') as String,
      contactPerson: (data['contactPerson'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      notes: (data['notes'] ?? '') as String,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'supplierId': supplierId,
      'supplierName': supplierName,
      'contactPerson': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
