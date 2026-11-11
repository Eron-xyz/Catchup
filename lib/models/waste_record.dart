import 'package:cloud_firestore/cloud_firestore.dart';

class WasteConstants {
  static const List<String> reasons = [
    'Spoiled',
    'Expired',
    'Damaged',
    'Contaminated',
    'Spillage',
    'Other',
  ];
}

class WasteRecord {
  final String wasteId; // W001...
  final String productId;
  final String productName;
  final double quantity;
  final String unit;
  final double unitPrice; // Snapshot of product price at waste time for estimated value
  final DateTime wasteDateTime;
  final String reason;
  final String remarks;
  final String recordedBy; // Signed-in user's email
  final bool isVoided;
  final String? voidReason;
  final String? voidedBy;
  final DateTime? voidedAt;

  const WasteRecord({
    required this.wasteId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unit,
    this.unitPrice = 0.0,
    required this.wasteDateTime,
    required this.reason,
    required this.remarks,
    required this.recordedBy,
    this.isVoided = false,
    this.voidReason,
    this.voidedBy,
    this.voidedAt,
  });

  double get estimatedValue => quantity * unitPrice;

  factory WasteRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return WasteRecord(
      wasteId: (data['wasteId'] ?? doc.id) as String,
      productId: (data['productId'] ?? '') as String,
      productName: (data['productName'] ?? '') as String,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: (data['unit'] ?? 'kg') as String,
      unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0.0,
      wasteDateTime: (data['wasteDateTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: (data['reason'] ?? WasteConstants.reasons.first) as String,
      remarks: (data['remarks'] ?? '') as String,
      recordedBy: (data['recordedBy'] ?? '') as String,
      isVoided: (data['isVoided'] as bool?) ?? false,
      voidReason: data['voidReason'] as String?,
      voidedBy: data['voidedBy'] as String?,
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'wasteId': wasteId,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'wasteDateTime': Timestamp.fromDate(wasteDateTime),
      'reason': reason,
      'remarks': remarks,
      'recordedBy': recordedBy,
      'isVoided': isVoided,
      'voidReason': voidReason,
      'voidedBy': voidedBy,
      'voidedAt': voidedAt != null ? Timestamp.fromDate(voidedAt!) : null,
    };
  }
}
