import 'package:catchup/core/utils/performance_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Stock transaction (Incoming or Outgoing).
/// Transactions are immutable after saving; Admin/Manager can void one with a reason,
/// which creates a reversing entry and keeps the history.
class StockTransaction {
  final String transactionId; // T001...
  final String type; // 'Incoming' or 'Outgoing'
  final String productId;
  final String productName;
  final double quantity;
  final String unit;
  final String? supplierId;
  final String? supplierName;
  final String storageId;
  final String storageName;
  final DateTime dateTime;
  final String notes;
  final String recordedBy; // User email or name
  final bool isVoided;
  final String? voidReason;
  final String? voidedBy;
  final DateTime? voidedAt;
  final bool isReversal;
  final String? reversesTransactionId;

  const StockTransaction({
    required this.transactionId,
    required this.type,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unit,
    this.supplierId,
    this.supplierName,
    required this.storageId,
    required this.storageName,
    required this.dateTime,
    required this.notes,
    required this.recordedBy,
    this.isVoided = false,
    this.voidReason,
    this.voidedBy,
    this.voidedAt,
    this.isReversal = false,
    this.reversesTransactionId,
  });

  bool get isIncoming => type == 'Incoming';
  bool get isOutgoing => type == 'Outgoing';

  factory StockTransaction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return StockTransaction(
      transactionId: (data['transactionId'] ?? doc.id) as String,
      type: (data['type'] ?? 'Incoming') as String,
      productId: (data['productId'] ?? '') as String,
      productName: (data['productName'] ?? '') as String,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: (data['unit'] ?? 'kg') as String,
      supplierId: data['supplierId'] as String?,
      supplierName: data['supplierName'] as String?,
      storageId: (data['storageId'] ?? '') as String,
      storageName: (data['storageName'] ?? '') as String,
      dateTime: (data['dateTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: (data['notes'] ?? '') as String,
      recordedBy: (data['recordedBy'] ?? '') as String,
      isVoided: (data['isVoided'] as bool?) ?? false,
      voidReason: data['voidReason'] as String?,
      voidedBy: data['voidedBy'] as String?,
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
      isReversal: (data['isReversal'] as bool?) ?? false,
      reversesTransactionId: data['reversesTransactionId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return PayloadCompressor.compactMap({
      'transactionId': transactionId,
      'type': type,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unit': unit,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'storageId': storageId,
      'storageName': storageName,
      'dateTime': Timestamp.fromDate(dateTime),
      'notes': notes,
      'recordedBy': recordedBy,
      'isVoided': isVoided,
      'voidReason': voidReason,
      'voidedBy': voidedBy,
      'voidedAt': voidedAt != null ? Timestamp.fromDate(voidedAt!) : null,
      'isReversal': isReversal,
      'reversesTransactionId': reversesTransactionId,
    });
  }
}
