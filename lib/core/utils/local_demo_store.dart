import 'package:catchup/models/app_settings.dart';
import 'package:catchup/models/app_user.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:catchup/models/storage_location.dart';
import 'package:catchup/models/supplier.dart';
import 'package:catchup/models/waste_record.dart';
import 'package:flutter/foundation.dart';

/// In-memory store pre-populated with realistic Roxas City, Capiz seafood
/// demo data so the application can be previewed immediately.
class LocalDemoStore extends ChangeNotifier {
  static final LocalDemoStore instance = LocalDemoStore._();

  LocalDemoStore._() {
    seedRoxasDemoData();
  }

  bool setupComplete = true;
  bool firestoreBlocked = false;
  AppUser? currentUser;

  void markFirestoreBlocked() {
    if (!firestoreBlocked) {
      firestoreBlocked = true;
      notifyListeners();
    }
  }

  /// Syncs a Firebase Auth user into the local store so they appear in Users
  /// and maintain their role even when Firestore rules are locked.
  AppUser syncFirebaseUser(AppUser fbUser) {
    final idx = users.indexWhere(
      (u) =>
          u.uid == fbUser.uid ||
          u.userEmail.toLowerCase() == fbUser.userEmail.toLowerCase(),
    );
    if (idx == -1) {
      users.insert(0, fbUser);
      currentUser = fbUser;
    } else {
      currentUser = users[idx];
    }
    notifyListeners();
    return currentUser!;
  }

  final List<AppUser> users = [];
  final List<Product> products = [];
  final List<Supplier> suppliers = [];
  final List<StorageLocation> storageLocations = [];
  final List<StockTransaction> transactions = [];
  final List<WasteRecord> wasteRecords = [];
  AppSettings settings = const AppSettings();

  final Map<String, String> _passwordsByEmail = {};
  final Map<String, int> _counters = {};

  /// Seeds realistic Roxas City, Capiz seafood products, suppliers, storage
  /// locations, transactions, waste records, and user accounts (including Mitzi).
  void seedRoxasDemoData() {
    users.clear();
    products.clear();
    suppliers.clear();
    storageLocations.clear();
    transactions.clear();
    wasteRecords.clear();
    _passwordsByEmail.clear();
    _counters.clear();

    final now = DateTime.now();

    // 1. Users (Admin Mitzi with password 12345, plus Manager and Staff)
    final adminMitzi = AppUser(
      uid: 'user_1',
      userEmail: 'mitzi@catchup.ph',
      fullName: 'Mitzi',
      role: UserRole.admin,
      isActive: true,
      createdAt: now.subtract(const Duration(days: 30)),
    );
    final managerCarlo = AppUser(
      uid: 'user_2',
      userEmail: 'carlo@catchup.ph',
      fullName: 'Carlo Dela Cruz',
      role: UserRole.manager,
      isActive: true,
      createdAt: now.subtract(const Duration(days: 20)),
    );
    final staffJessa = AppUser(
      uid: 'user_3',
      userEmail: 'jessa@catchup.ph',
      fullName: 'Jessa Villanueva',
      role: UserRole.staff,
      isActive: true,
      createdAt: now.subtract(const Duration(days: 15)),
    );

    users.addAll([adminMitzi, managerCarlo, staffJessa]);
    _passwordsByEmail['mitzi@catchup.ph'] = '12345';
    _passwordsByEmail['carlo@catchup.ph'] = '12345';
    _passwordsByEmail['jessa@catchup.ph'] = '12345';
    setupComplete = true;
    currentUser = null;

    // 2. Suppliers (Roxas City, Capiz)
    suppliers.addAll([
      Supplier(
        supplierId: 'S001',
        supplierName: 'Baybay Seafood Harvest Co.',
        contactPerson: 'Ramon Bermejo',
        phone: '09174528810',
        email: 'baybayharvest@capizseafood.ph',
        address: 'Brgy. Baybay, Roxas City, Capiz',
        notes: 'Daily morning bangus, prawns, and blue crab deliveries',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 25)),
      ),
      Supplier(
        supplierId: 'S002',
        supplierName: 'Libas Fishing Port Traders',
        contactPerson: 'Elena Fuentes',
        phone: '09186342190',
        email: 'elena.libasport@gmail.com',
        address: 'Libas Fishing Port, Roxas City, Capiz',
        notes: 'Fresh squid, diwal, and yellowfin tuna',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 22)),
      ),
      Supplier(
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        contactPerson: 'Noel Andrade',
        phone: '09983124578',
        email: 'culasishellfish@yahoo.com',
        address: 'Brgy. Culasi, Roxas City, Capiz',
        notes: 'Talaba (oysters), scallops, and dried danggit',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 18)),
      ),
    ]);
    _counters['suppliers'] = 3;

    // 3. Storage Locations
    storageLocations.addAll([
      StorageLocation(
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        storageType: 'Chiller',
        temperatureMinC: 0.0,
        temperatureMaxC: 4.0,
        stockRotationMethod: 'FIFO',
        lastChecked: now.subtract(const Duration(hours: 6)),
        condition: 'Normal',
        notes: 'Fresh fish and crustaceans for daily dispatch',
        createdAt: now.subtract(const Duration(days: 25)),
      ),
      StorageLocation(
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        storageType: 'Freezer',
        temperatureMinC: -22.0,
        temperatureMaxC: -18.0,
        stockRotationMethod: 'FEFO',
        lastChecked: now.subtract(const Duration(days: 1)),
        condition: 'Normal',
        notes: 'Frozen tiger prawns and squid rings',
        createdAt: now.subtract(const Duration(days: 25)),
      ),
      StorageLocation(
        storageId: 'ST003',
        storageName: 'Shellfish Ice Box C',
        storageType: 'Ice Box',
        temperatureMinC: 0.0,
        temperatureMaxC: 2.0,
        stockRotationMethod: 'FIFO',
        lastChecked: now.subtract(const Duration(days: 8)),
        condition: 'Needs Attention',
        notes: 'Seal gasket needs replacement; check ice level twice daily',
        createdAt: now.subtract(const Duration(days: 20)),
      ),
      StorageLocation(
        storageId: 'ST004',
        storageName: 'Dry Storage Rack D',
        storageType: 'Dry Storage',
        temperatureMinC: 20.0,
        temperatureMaxC: 25.0,
        stockRotationMethod: 'FIFO',
        lastChecked: now.subtract(const Duration(days: 2)),
        condition: 'Normal',
        notes: 'Dried danggit, pusit, and vacuum-packed seafood',
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ]);
    _counters['storageLocations'] = 4;

    // 4. Products (P001 - P006)
    products.addAll([
      Product(
        productId: 'P001',
        productName: 'Capiz Milkfish (Bangus)',
        category: 'Fish',
        type: 'Fish',
        unit: 'kg',
        price: 195.0,
        minimumStock: 25.0,
        reorderPoint: 40.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 82.0,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
      Product(
        productId: 'P002',
        productName: 'Tiger Prawns (Lukon)',
        category: 'Crustaceans',
        type: 'Crustacean',
        unit: 'kg',
        price: 560.0,
        minimumStock: 15.0,
        reorderPoint: 25.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 36.0,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
      Product(
        productId: 'P003',
        productName: 'Angel Wings Clam (Diwal)',
        category: 'Shellfish',
        type: 'Shellfish',
        unit: 'kg',
        price: 420.0,
        minimumStock: 15.0,
        reorderPoint: 20.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 11.0, // Low stock -> triggers alert!
        createdAt: now.subtract(const Duration(days: 18)),
      ),
      Product(
        productId: 'P004',
        productName: 'Blue Swimming Crab (Alimasag)',
        category: 'Crustaceans',
        type: 'Crustacean',
        unit: 'kg',
        price: 380.0,
        minimumStock: 12.0,
        reorderPoint: 20.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 28.0,
        createdAt: now.subtract(const Duration(days: 17)),
      ),
      Product(
        productId: 'P005',
        productName: 'Fresh White Squid (Pusit)',
        category: 'Mollusks',
        type: 'Mollusk',
        unit: 'kg',
        price: 310.0,
        minimumStock: 15.0,
        reorderPoint: 22.0,
        productMovement: 'Slow Moving',
        isActive: true,
        currentStock: 22.0,
        createdAt: now.subtract(const Duration(days: 16)),
      ),
      Product(
        productId: 'P006',
        productName: 'Sun-Dried Rabbitfish (Danggit)',
        category: 'Dried Seafood',
        type: 'Dried Fish',
        unit: 'kg',
        price: 680.0,
        minimumStock: 10.0,
        reorderPoint: 15.0,
        productMovement: 'Slow Moving',
        isActive: true,
        currentStock: 18.0,
        createdAt: now.subtract(const Duration(days: 14)),
      ),
      Product(
        productId: 'P007',
        productName: 'Capiz Oysters (Talaba)',
        category: 'Shellfish',
        type: 'Shellfish',
        unit: 'kg',
        price: 110.0,
        minimumStock: 30.0,
        reorderPoint: 45.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 65.0,
        createdAt: now.subtract(const Duration(days: 13)),
      ),
      Product(
        productId: 'P008',
        productName: 'Yellowfin Tuna Loin (Tambakol)',
        category: 'Fish',
        type: 'Fish',
        unit: 'kg',
        price: 450.0,
        minimumStock: 15.0,
        reorderPoint: 25.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 34.0,
        createdAt: now.subtract(const Duration(days: 12)),
      ),
      Product(
        productId: 'P009',
        productName: 'Red Snapper (Maya-Maya)',
        category: 'Fish',
        type: 'Fish',
        unit: 'kg',
        price: 390.0,
        minimumStock: 12.0,
        reorderPoint: 20.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 26.0,
        createdAt: now.subtract(const Duration(days: 11)),
      ),
      Product(
        productId: 'P010',
        productName: 'Mud Crab (Alimango)',
        category: 'Crustaceans',
        type: 'Crustacean',
        unit: 'kg',
        price: 620.0,
        minimumStock: 10.0,
        reorderPoint: 18.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 24.0,
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      Product(
        productId: 'P011',
        productName: 'Capiz Bay Scallops (Tikab)',
        category: 'Shellfish',
        type: 'Shellfish',
        unit: 'kg',
        price: 290.0,
        minimumStock: 15.0,
        reorderPoint: 25.0,
        productMovement: 'Fast Moving',
        isActive: true,
        currentStock: 30.0,
        createdAt: now.subtract(const Duration(days: 9)),
      ),
      Product(
        productId: 'P012',
        productName: 'Dried Squid (uga Pusit)',
        category: 'Dried Seafood',
        type: 'Dried Mollusk',
        unit: 'kg',
        price: 720.0,
        minimumStock: 8.0,
        reorderPoint: 14.0,
        productMovement: 'Slow Moving',
        isActive: true,
        currentStock: 16.0,
        createdAt: now.subtract(const Duration(days: 8)),
      ),
    ]);
    _counters['products'] = 12;

    // 5. Stock Transactions (Incoming & Outgoing across the last 6 days)
    // Net stock per product matches:
    // P001: +120 - 35 - 3 (waste) = 82 kg
    // P002: +55 - 19 = 36 kg
    // P003: +25 - 12 - 2 (waste) = 11 kg
    // P004: +40 - 12 = 28 kg
    // P005: +32 - 10 = 22 kg
    // P006: +24 - 6 = 18 kg
    transactions.addAll([
      StockTransaction(
        transactionId: 'T010',
        type: 'Outgoing',
        productId: 'P001',
        productName: 'Capiz Milkfish (Bangus)',
        quantity: 15.0,
        unit: 'kg',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(hours: 3)),
        notes: 'Morning restaurant prep & grill station',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T009',
        type: 'Incoming',
        productId: 'P004',
        productName: 'Blue Swimming Crab (Alimasag)',
        quantity: 40.0,
        unit: 'kg',
        supplierId: 'S001',
        supplierName: 'Baybay Seafood Harvest Co.',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 1, hours: 2)),
        notes: 'Fresh catch from Baybay boats',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T008',
        type: 'Outgoing',
        productId: 'P004',
        productName: 'Blue Swimming Crab (Alimasag)',
        quantity: 12.0,
        unit: 'kg',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 1)),
        notes: 'Steamed crab platter orders',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T007',
        type: 'Outgoing',
        productId: 'P002',
        productName: 'Tiger Prawns (Lukon)',
        quantity: 19.0,
        unit: 'kg',
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        dateTime: now.subtract(const Duration(days: 2)),
        notes: 'Hotel banquet order dispatch',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T006',
        type: 'Incoming',
        productId: 'P005',
        productName: 'Fresh White Squid (Pusit)',
        quantity: 32.0,
        unit: 'kg',
        supplierId: 'S002',
        supplierName: 'Libas Fishing Port Traders',
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        dateTime: now.subtract(const Duration(days: 3, hours: 4)),
        notes: 'Grade A whole squid',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T005',
        type: 'Outgoing',
        productId: 'P005',
        productName: 'Fresh White Squid (Pusit)',
        quantity: 10.0,
        unit: 'kg',
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        dateTime: now.subtract(const Duration(days: 3)),
        notes: 'Calamares and grilled pusit kitchen prep',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T004',
        type: 'Incoming',
        productId: 'P003',
        productName: 'Angel Wings Clam (Diwal)',
        quantity: 25.0,
        unit: 'kg',
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        storageId: 'ST003',
        storageName: 'Shellfish Ice Box C',
        dateTime: now.subtract(const Duration(days: 4, hours: 3)),
        notes: 'Seasonal diwal harvest',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T003',
        type: 'Outgoing',
        productId: 'P003',
        productName: 'Angel Wings Clam (Diwal)',
        quantity: 12.0,
        unit: 'kg',
        storageId: 'ST003',
        storageName: 'Shellfish Ice Box C',
        dateTime: now.subtract(const Duration(days: 4)),
        notes: 'Seafood platter special',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T002',
        type: 'Incoming',
        productId: 'P002',
        productName: 'Tiger Prawns (Lukon)',
        quantity: 55.0,
        unit: 'kg',
        supplierId: 'S001',
        supplierName: 'Baybay Seafood Harvest Co.',
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        dateTime: now.subtract(const Duration(days: 5, hours: 2)),
        notes: 'Jumbo tiger prawns',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T001',
        type: 'Incoming',
        productId: 'P001',
        productName: 'Capiz Milkfish (Bangus)',
        quantity: 120.0,
        unit: 'kg',
        supplierId: 'S001',
        supplierName: 'Baybay Seafood Harvest Co.',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 5, hours: 5)),
        notes: 'First pond harvest delivery',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T011',
        type: 'Outgoing',
        productId: 'P001',
        productName: 'Capiz Milkfish (Bangus)',
        quantity: 20.0,
        unit: 'kg',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 4, hours: 1)),
        notes: 'Deboned bangus orders',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T012',
        type: 'Incoming',
        productId: 'P006',
        productName: 'Sun-Dried Rabbitfish (Danggit)',
        quantity: 24.0,
        unit: 'kg',
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        storageId: 'ST004',
        storageName: 'Dry Storage Rack D',
        dateTime: now.subtract(const Duration(days: 5)),
        notes: 'Vacuum-sealed packs',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T013',
        type: 'Outgoing',
        productId: 'P006',
        productName: 'Sun-Dried Rabbitfish (Danggit)',
        quantity: 6.0,
        unit: 'kg',
        storageId: 'ST004',
        storageName: 'Dry Storage Rack D',
        dateTime: now.subtract(const Duration(days: 2, hours: 3)),
        notes: 'Pasalubong counter display',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T014',
        type: 'Incoming',
        productId: 'P007',
        productName: 'Capiz Oysters (Talaba)',
        quantity: 65.0,
        unit: 'kg',
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        storageId: 'ST003',
        storageName: 'Shellfish Ice Box C',
        dateTime: now.subtract(const Duration(days: 2, hours: 5)),
        notes: 'Freshly harvested Culasi talaba sacks',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T015',
        type: 'Incoming',
        productId: 'P008',
        productName: 'Yellowfin Tuna Loin (Tambakol)',
        quantity: 34.0,
        unit: 'kg',
        supplierId: 'S002',
        supplierName: 'Libas Fishing Port Traders',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 3, hours: 1)),
        notes: 'Sashimi-grade tuna loin blocks',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T016',
        type: 'Incoming',
        productId: 'P009',
        productName: 'Red Snapper (Maya-Maya)',
        quantity: 26.0,
        unit: 'kg',
        supplierId: 'S002',
        supplierName: 'Libas Fishing Port Traders',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 3, hours: 6)),
        notes: 'Whole gutted red snapper',
        recordedBy: 'jessa@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T017',
        type: 'Incoming',
        productId: 'P010',
        productName: 'Mud Crab (Alimango)',
        quantity: 24.0,
        unit: 'kg',
        supplierId: 'S001',
        supplierName: 'Baybay Seafood Harvest Co.',
        storageId: 'ST001',
        storageName: 'Main Walk-In Chiller A',
        dateTime: now.subtract(const Duration(days: 4, hours: 2)),
        notes: 'Live tied mud crabs from Pontevedra ponds',
        recordedBy: 'mitzi@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T018',
        type: 'Incoming',
        productId: 'P011',
        productName: 'Capiz Bay Scallops (Tikab)',
        quantity: 30.0,
        unit: 'kg',
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        storageId: 'ST002',
        storageName: 'Deep Blast Freezer B',
        dateTime: now.subtract(const Duration(days: 4, hours: 5)),
        notes: 'Half-shell cleaned scallops for baked scallops',
        recordedBy: 'carlo@catchup.ph',
      ),
      StockTransaction(
        transactionId: 'T019',
        type: 'Incoming',
        productId: 'P012',
        productName: 'Dried Squid (uga Pusit)',
        quantity: 16.0,
        unit: 'kg',
        supplierId: 'S003',
        supplierName: 'Culasi Shellfish & Dried Goods',
        storageId: 'ST004',
        storageName: 'Dry Storage Rack D',
        dateTime: now.subtract(const Duration(days: 5, hours: 1)),
        notes: 'Sun-dried whole squid packs',
        recordedBy: 'jessa@catchup.ph',
      ),
    ]);
    _counters['stockTransactions'] = 19;

    // 6. Waste Records (W001 - W002)
    wasteRecords.addAll([
      WasteRecord(
        wasteId: 'W002',
        productId: 'P003',
        productName: 'Angel Wings Clam (Diwal)',
        quantity: 2.0,
        unit: 'kg',
        unitPrice: 420.0,
        wasteDateTime: now.subtract(const Duration(days: 1, hours: 4)),
        reason: 'Damaged',
        remarks: 'Cracked shells during ice box transfer',
        recordedBy: 'jessa@catchup.ph',
      ),
      WasteRecord(
        wasteId: 'W001',
        productId: 'P001',
        productName: 'Capiz Milkfish (Bangus)',
        quantity: 3.0,
        unit: 'kg',
        unitPrice: 195.0,
        wasteDateTime: now.subtract(const Duration(days: 3, hours: 2)),
        reason: 'Spoiled',
        remarks: 'Bruised gills rejected during quality check',
        recordedBy: 'carlo@catchup.ph',
      ),
    ]);
    _counters['wasteRecords'] = 2;

    notifyListeners();
  }

  /// Generates sequential IDs starting at 0 -> P001, T001, S001, ST001, W001.
  String nextId(String key, String prefix) {
    final current = _counters[key] ?? 0;
    final next = current + 1;
    _counters[key] = next;
    return '$prefix${next.toString().padLeft(3, '0')}';
  }

  /// First-run setup: creates the first Admin user and marks setupComplete = true.
  AppUser completeFirstRunSetup({
    required String fullName,
    required String email,
    required String password,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final admin = AppUser(
      uid: 'user_${users.length + 1}',
      userEmail: email.trim(),
      fullName: fullName.trim(),
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime.now(),
    );
    users.add(admin);
    _passwordsByEmail[cleanEmail] = password;
    setupComplete = true;
    currentUser = admin;
    notifyListeners();
    return admin;
  }

  bool hasLocalUser(String emailOrUsername) {
    final clean = emailOrUsername.trim().toLowerCase();
    return users.any((u) {
      final emailLower = u.userEmail.toLowerCase();
      final prefixLower = emailLower.split('@').first;
      final nameLower = u.fullName.toLowerCase();
      final firstNameLower = nameLower.split(' ').first;
      return (emailLower == clean ||
              prefixLower == clean ||
              nameLower == clean ||
              firstNameLower == clean) &&
          _passwordsByEmail.containsKey(emailLower);
    });
  }

  AppUser signIn({required String email, required String password}) {
    final cleanEmail = email.trim().toLowerCase();
    // Allow signing in by email ('carlo@catchup.ph'), prefix ('carlo'), or full name
    final user = users.where((u) {
      final emailLower = u.userEmail.toLowerCase();
      final prefixLower = emailLower.split('@').first;
      final nameLower = u.fullName.toLowerCase();
      final firstNameLower = nameLower.split(' ').first;
      return emailLower == cleanEmail ||
          prefixLower == cleanEmail ||
          nameLower == cleanEmail ||
          firstNameLower == cleanEmail;
    }).firstOrNull;
    final storedPass = user != null
        ? _passwordsByEmail[user.userEmail.toLowerCase()]
        : null;
    if (user == null || storedPass != password) {
      throw Exception('Incorrect username/email or password. Please try again.');
    }
    if (!user.isActive) {
      throw Exception(
        'Your account has been deactivated. Please contact an Administrator.',
      );
    }
    currentUser = user;
    notifyListeners();
    return user;
  }

  void signOut() {
    currentUser = null;
    notifyListeners();
  }

  void createUserByAdmin({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    if (users.any((u) => u.userEmail.toLowerCase() == cleanEmail)) {
      throw Exception('That email address is already registered.');
    }
    final u = AppUser(
      uid: 'user_${users.length + 1}',
      userEmail: email.trim(),
      fullName: fullName.trim(),
      role: role,
      isActive: true,
      createdAt: DateTime.now(),
    );
    users.add(u);
    _passwordsByEmail[cleanEmail] = password;
    notifyListeners();
  }

  void updateUser(
    String uid, {
    String? fullName,
    UserRole? role,
    bool? isActive,
  }) {
    final idx = users.indexWhere((u) => u.uid == uid);
    if (idx == -1) return;
    users[idx] = users[idx].copyWith(
      fullName: fullName,
      role: role,
      isActive: isActive,
    );
    if (currentUser?.uid == uid) {
      currentUser = users[idx];
    }
    notifyListeners();
  }

  void saveProduct(Product product) {
    final idx = products.indexWhere((p) => p.productId == product.productId);
    if (idx == -1) {
      products.add(product);
    } else {
      products[idx] = product;
    }
    notifyListeners();
  }

  void toggleProductActive(String productId) {
    final idx = products.indexWhere((p) => p.productId == productId);
    if (idx == -1) return;
    final p = products[idx];
    products[idx] = Product(
      productId: p.productId,
      productName: p.productName,
      category: p.category,
      type: p.type,
      unit: p.unit,
      price: p.price,
      minimumStock: p.minimumStock,
      reorderPoint: p.reorderPoint,
      productMovement: p.productMovement,
      photoUrl: p.photoUrl,
      isActive: !p.isActive,
      currentStock: p.currentStock,
      createdAt: p.createdAt,
    );
    notifyListeners();
  }

  void saveSupplier(Supplier supplier) {
    final idx =
        suppliers.indexWhere((s) => s.supplierId == supplier.supplierId);
    if (idx == -1) {
      suppliers.add(supplier);
    } else {
      suppliers[idx] = supplier;
    }
    notifyListeners();
  }

  void toggleSupplierActive(String supplierId) {
    final idx = suppliers.indexWhere((s) => s.supplierId == supplierId);
    if (idx == -1) return;
    final s = suppliers[idx];
    suppliers[idx] = Supplier(
      supplierId: s.supplierId,
      supplierName: s.supplierName,
      contactPerson: s.contactPerson,
      phone: s.phone,
      email: s.email,
      address: s.address,
      notes: s.notes,
      isActive: !s.isActive,
      createdAt: s.createdAt,
    );
    notifyListeners();
  }

  void saveStorageLocation(StorageLocation location) {
    final idx = storageLocations
        .indexWhere((st) => st.storageId == location.storageId);
    if (idx == -1) {
      storageLocations.add(location);
    } else {
      storageLocations[idx] = location;
    }
    notifyListeners();
  }

  void markStorageChecked(String storageId) {
    final idx =
        storageLocations.indexWhere((st) => st.storageId == storageId);
    if (idx == -1) return;
    final st = storageLocations[idx];
    storageLocations[idx] = StorageLocation(
      storageId: st.storageId,
      storageName: st.storageName,
      storageType: st.storageType,
      temperatureMinC: st.temperatureMinC,
      temperatureMaxC: st.temperatureMaxC,
      stockRotationMethod: st.stockRotationMethod,
      lastChecked: DateTime.now(),
      condition: st.condition,
      notes: st.notes,
      createdAt: st.createdAt,
    );
    notifyListeners();
  }

  void toggleStorageLocationActive(String storageId) {
    final idx =
        storageLocations.indexWhere((st) => st.storageId == storageId);
    if (idx == -1) return;
    final st = storageLocations[idx];
    storageLocations[idx] = st.copyWith(isActive: !st.isActive);
    notifyListeners();
  }

  void permanentlyDeleteProduct(String productId) {
    products.removeWhere((p) => p.productId == productId);
    notifyListeners();
  }

  void permanentlyDeleteSupplier(String supplierId) {
    suppliers.removeWhere((s) => s.supplierId == supplierId);
    notifyListeners();
  }

  void permanentlyDeleteStorageLocation(String storageId) {
    storageLocations.removeWhere((st) => st.storageId == storageId);
    notifyListeners();
  }

  void permanentlyDeleteUser(String uid) {
    users.removeWhere((u) => u.uid == uid);
    notifyListeners();
  }

  void recordTransaction(StockTransaction tx) {
    transactions.insert(0, tx);
    final idx = products.indexWhere((p) => p.productId == tx.productId);
    if (idx != -1) {
      final p = products[idx];
      final newStock = tx.isIncoming
          ? p.currentStock + tx.quantity
          : p.currentStock - tx.quantity;
      products[idx] = Product(
        productId: p.productId,
        productName: p.productName,
        category: p.category,
        type: p.type,
        unit: p.unit,
        price: p.price,
        minimumStock: p.minimumStock,
        reorderPoint: p.reorderPoint,
        productMovement: p.productMovement,
        photoUrl: p.photoUrl,
        isActive: p.isActive,
        currentStock: newStock,
        createdAt: p.createdAt,
      );
    }
    notifyListeners();
  }

  void voidTransaction(StockTransaction tx, String reason, String voidedBy) {
    final idx =
        transactions.indexWhere((t) => t.transactionId == tx.transactionId);
    if (idx == -1) return;

    final pIdx = products.indexWhere((p) => p.productId == tx.productId);
    if (pIdx != -1) {
      final p = products[pIdx];
      final newStock = tx.isIncoming
          ? p.currentStock - tx.quantity
          : p.currentStock + tx.quantity;
      if (newStock < 0) {
        throw Exception(
          'Cannot void this Incoming transaction because current stock is lower than ${tx.quantity} ${tx.unit}.',
        );
      }
      products[pIdx] = Product(
        productId: p.productId,
        productName: p.productName,
        category: p.category,
        type: p.type,
        unit: p.unit,
        price: p.price,
        minimumStock: p.minimumStock,
        reorderPoint: p.reorderPoint,
        productMovement: p.productMovement,
        photoUrl: p.photoUrl,
        isActive: p.isActive,
        currentStock: newStock,
        createdAt: p.createdAt,
      );
    }

    transactions[idx] = StockTransaction(
      transactionId: tx.transactionId,
      type: tx.type,
      productId: tx.productId,
      productName: tx.productName,
      quantity: tx.quantity,
      unit: tx.unit,
      supplierId: tx.supplierId,
      supplierName: tx.supplierName,
      storageId: tx.storageId,
      storageName: tx.storageName,
      dateTime: tx.dateTime,
      notes: tx.notes,
      recordedBy: tx.recordedBy,
      isVoided: true,
      voidReason: reason,
      voidedBy: voidedBy,
      voidedAt: DateTime.now(),
    );

    final reversalId = nextId('stockTransactions', 'T');
    final reversal = StockTransaction(
      transactionId: reversalId,
      type: tx.isIncoming ? 'Outgoing' : 'Incoming',
      productId: tx.productId,
      productName: tx.productName,
      quantity: tx.quantity,
      unit: tx.unit,
      supplierId: tx.supplierId,
      supplierName: tx.supplierName,
      storageId: tx.storageId,
      storageName: tx.storageName,
      dateTime: DateTime.now(),
      notes: 'REVERSAL of ${tx.transactionId}: $reason',
      recordedBy: voidedBy,
      isReversal: true,
      reversesTransactionId: tx.transactionId,
    );
    transactions.insert(0, reversal);
    notifyListeners();
  }

  void recordWaste(WasteRecord record) {
    wasteRecords.insert(0, record);
    final idx = products.indexWhere((p) => p.productId == record.productId);
    if (idx != -1) {
      final p = products[idx];
      products[idx] = Product(
        productId: p.productId,
        productName: p.productName,
        category: p.category,
        type: p.type,
        unit: p.unit,
        price: p.price,
        minimumStock: p.minimumStock,
        reorderPoint: p.reorderPoint,
        productMovement: p.productMovement,
        photoUrl: p.photoUrl,
        isActive: p.isActive,
        currentStock: p.currentStock - record.quantity,
        createdAt: p.createdAt,
      );
    }
    notifyListeners();
  }

  void voidWaste(WasteRecord w, String reason, String voidedBy) {
    final idx = wasteRecords.indexWhere((r) => r.wasteId == w.wasteId);
    if (idx == -1) return;
    wasteRecords[idx] = WasteRecord(
      wasteId: w.wasteId,
      productId: w.productId,
      productName: w.productName,
      quantity: w.quantity,
      unit: w.unit,
      unitPrice: w.unitPrice,
      wasteDateTime: w.wasteDateTime,
      reason: w.reason,
      remarks: w.remarks,
      recordedBy: w.recordedBy,
      isVoided: true,
      voidReason: reason,
      voidedBy: voidedBy,
      voidedAt: DateTime.now(),
    );

    final pIdx = products.indexWhere((p) => p.productId == w.productId);
    if (pIdx != -1) {
      final p = products[pIdx];
      products[pIdx] = Product(
        productId: p.productId,
        productName: p.productName,
        category: p.category,
        type: p.type,
        unit: p.unit,
        price: p.price,
        minimumStock: p.minimumStock,
        reorderPoint: p.reorderPoint,
        productMovement: p.productMovement,
        photoUrl: p.photoUrl,
        isActive: p.isActive,
        currentStock: p.currentStock + w.quantity,
        createdAt: p.createdAt,
      );
    }
    notifyListeners();
  }

  void saveSettings(AppSettings newSettings) {
    settings = newSettings;
    notifyListeners();
  }
}
