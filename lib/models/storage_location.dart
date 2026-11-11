import 'package:cloud_firestore/cloud_firestore.dart';

class StorageConstants {
  static const List<String> storageTypes = [
    'Chiller',
    'Freezer',
    'Dry Storage',
    'Ice Box',
    'Other',
  ];

  static const List<String> rotationMethods = [
    'FIFO',
    'LIFO',
    'FEFO',
  ];

  static const List<String> conditions = [
    'Normal',
    'Needs Attention',
    'Out of Order',
  ];
}

class StorageLocation {
  final String storageId; // ST001...
  final String storageName;
  final String storageType;
  final double temperatureMinC;
  final double temperatureMaxC;
  final String stockRotationMethod;
  final DateTime lastChecked;
  final String condition; // Normal / Needs Attention / Out of Order
  final String notes;
  final bool isActive;
  final DateTime createdAt;

  const StorageLocation({
    required this.storageId,
    required this.storageName,
    required this.storageType,
    required this.temperatureMinC,
    required this.temperatureMaxC,
    required this.stockRotationMethod,
    required this.lastChecked,
    required this.condition,
    required this.notes,
    this.isActive = true,
    required this.createdAt,
  });

  bool get hasConditionIssue => condition != 'Normal';

  bool get isOverdueCheck =>
      DateTime.now().difference(lastChecked).inDays >= 7;

  bool get needsAlert => hasConditionIssue || isOverdueCheck;

  StorageLocation copyWith({
    String? storageId,
    String? storageName,
    String? storageType,
    double? temperatureMinC,
    double? temperatureMaxC,
    String? stockRotationMethod,
    DateTime? lastChecked,
    String? condition,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return StorageLocation(
      storageId: storageId ?? this.storageId,
      storageName: storageName ?? this.storageName,
      storageType: storageType ?? this.storageType,
      temperatureMinC: temperatureMinC ?? this.temperatureMinC,
      temperatureMaxC: temperatureMaxC ?? this.temperatureMaxC,
      stockRotationMethod: stockRotationMethod ?? this.stockRotationMethod,
      lastChecked: lastChecked ?? this.lastChecked,
      condition: condition ?? this.condition,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory StorageLocation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return StorageLocation(
      storageId: (data['storageId'] ?? doc.id) as String,
      storageName: (data['storageName'] ?? '') as String,
      storageType: (data['storageType'] ?? StorageConstants.storageTypes.first) as String,
      temperatureMinC: (data['temperatureMinC'] as num?)?.toDouble() ?? 0.0,
      temperatureMaxC: (data['temperatureMaxC'] as num?)?.toDouble() ?? 4.0,
      stockRotationMethod: (data['stockRotationMethod'] ?? 'FIFO') as String,
      lastChecked: (data['lastChecked'] as Timestamp?)?.toDate() ?? DateTime.now(),
      condition: (data['condition'] ?? 'Normal') as String,
      notes: (data['notes'] ?? '') as String,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storageId': storageId,
      'storageName': storageName,
      'storageType': storageType,
      'temperatureMinC': temperatureMinC,
      'temperatureMaxC': temperatureMaxC,
      'stockRotationMethod': stockRotationMethod,
      'lastChecked': Timestamp.fromDate(lastChecked),
      'condition': condition,
      'notes': notes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
