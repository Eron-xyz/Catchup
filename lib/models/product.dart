import 'package:catchup/core/utils/performance_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductConstants {
  static const List<String> defaultCategories = [
    'Fish',
    'Crustaceans',
    'Mollusks',
    'Shellfish',
    'Dried Seafood',
    'Processed Seafood',
    'Frozen Seafood',
    'Fresh Seafood',
    'Canned Seafood',
    'Other Seafood',
  ];

  static const List<String> defaultUnits = [
    'kg',
    'g',
    'pcs',
    'box',
    'pack',
    'can',
  ];

  static const List<String> movements = [
    'Fast Moving',
    'Slow Moving',
  ];
}

class Product {
  final String productId; // e.g., P001
  final String productName;
  final String category;
  final String type; // e.g., Fish, Crustacean, Mollusk
  final String unit; // kg, g, pcs, box, pack, can
  final double price; // PHP
  final double minimumStock;
  final double reorderPoint;
  final String productMovement; // Fast Moving / Slow Moving
  final String? photoUrl;
  final bool isActive;
  final double currentStock; // Maintained via Firestore transactions (Incoming - Outgoing - Waste)
  final DateTime createdAt;

  const Product({
    required this.productId,
    required this.productName,
    required this.category,
    required this.type,
    required this.unit,
    required this.price,
    required this.minimumStock,
    required this.reorderPoint,
    required this.productMovement,
    this.photoUrl,
    required this.isActive,
    this.currentStock = 0,
    required this.createdAt,
  });

  bool get isOutOfStock => currentStock <= 0;
  bool get isLowStock => currentStock > 0 && currentStock <= minimumStock;
  bool get isBelowReorderPoint => currentStock <= reorderPoint;

  String get stockStatusLabel {
    if (currentStock <= 0) return 'Out of stock';
    if (currentStock <= minimumStock) return 'Low';
    return 'OK';
  }

  factory Product.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Product(
      productId: (data['productId'] ?? doc.id) as String,
      productName: (data['productName'] ?? '') as String,
      category: (data['category'] ?? ProductConstants.defaultCategories.first) as String,
      type: (data['type'] ?? '') as String,
      unit: (data['unit'] ?? ProductConstants.defaultUnits.first) as String,
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      minimumStock: (data['minimumStock'] as num?)?.toDouble() ?? 0.0,
      reorderPoint: (data['reorderPoint'] as num?)?.toDouble() ?? 0.0,
      productMovement: (data['productMovement'] ?? 'Fast Moving') as String,
      photoUrl: data['photoUrl'] as String?,
      isActive: (data['isActive'] as bool?) ?? true,
      currentStock: (data['currentStock'] as num?)?.toDouble() ?? 0.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return PayloadCompressor.compactMap({
      'productId': productId,
      'productName': productName,
      'category': category,
      'type': type,
      'unit': unit,
      'price': price,
      'minimumStock': minimumStock,
      'reorderPoint': reorderPoint,
      'productMovement': productMovement,
      'photoUrl': photoUrl,
      'isActive': isActive,
      'currentStock': currentStock,
      'createdAt': Timestamp.fromDate(createdAt),
    });
  }
}
