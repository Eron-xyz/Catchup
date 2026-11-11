import 'package:catchup/models/product.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppSettings {
  final String businessName;
  final String address;
  final String contactNumber;
  final double defaultLowStockThreshold;
  final List<String> units;
  final List<String> categories;
  final String currency;
  final bool isDarkMode;
  final String sidebarAccent;

  const AppSettings({
    this.businessName = 'CatchUP Seafood Trading',
    this.address = 'Baybay, Roxas City, Capiz, Philippines',
    this.contactNumber = '0917-452-8810',
    this.defaultLowStockThreshold = 10.0,
    this.units = ProductConstants.defaultUnits,
    this.categories = ProductConstants.defaultCategories,
    this.currency = 'PHP',
    this.isDarkMode = false,
    this.sidebarAccent = 'rust',
  });

  factory AppSettings.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>>? doc,
  ) {
    final data = doc?.data();
    if (data == null) return const AppSettings();
    return AppSettings(
      businessName:
          (data['businessName'] ?? 'CatchUP Seafood Trading') as String,
      address:
          (data['address'] ?? 'Baybay, Roxas City, Capiz, Philippines') as String,
      contactNumber: (data['contactNumber'] ?? '0917-452-8810') as String,
      defaultLowStockThreshold:
          (data['defaultLowStockThreshold'] as num?)?.toDouble() ?? 10.0,
      units: (data['units'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ProductConstants.defaultUnits,
      categories: (data['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ProductConstants.defaultCategories,
      currency: (data['currency'] ?? 'PHP') as String,
      isDarkMode: (data['isDarkMode'] as bool?) ?? false,
      sidebarAccent: (data['sidebarAccent'] ?? 'rust') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessName': businessName,
      'address': address,
      'contactNumber': contactNumber,
      'defaultLowStockThreshold': defaultLowStockThreshold,
      'units': units,
      'categories': categories,
      'currency': currency,
      'isDarkMode': isDarkMode,
      'sidebarAccent': sidebarAccent,
    };
  }

  AppSettings copyWith({
    String? businessName,
    String? address,
    String? contactNumber,
    double? defaultLowStockThreshold,
    List<String>? units,
    List<String>? categories,
    String? currency,
    bool? isDarkMode,
    String? sidebarAccent,
  }) {
    return AppSettings(
      businessName: businessName ?? this.businessName,
      address: address ?? this.address,
      contactNumber: contactNumber ?? this.contactNumber,
      defaultLowStockThreshold:
          defaultLowStockThreshold ?? this.defaultLowStockThreshold,
      units: units ?? this.units,
      categories: categories ?? this.categories,
      currency: currency ?? this.currency,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      sidebarAccent: sidebarAccent ?? this.sidebarAccent,
    );
  }
}
