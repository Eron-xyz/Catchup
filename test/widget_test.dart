import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/widgets/app_sidebar.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/features/dashboard/dashboard_screen.dart';
import 'package:catchup/features/inventory/inventory_screen.dart';
import 'package:catchup/features/products/products_screen.dart';
import 'package:catchup/features/reports/reports_screen.dart';
import 'package:catchup/features/storage/storage_locations_screen.dart';
import 'package:catchup/features/suppliers/suppliers_screen.dart';
import 'package:catchup/features/transactions/transactions_screen.dart';
import 'package:catchup/features/waste/waste_records_screen.dart';
import 'package:catchup/models/app_settings.dart';
import 'package:catchup/models/app_user.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:catchup/models/storage_location.dart';
import 'package:catchup/models/supplier.dart';
import 'package:catchup/models/waste_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PH phone validator accepts 09XXXXXXXXX only', () {
    expect(AppValidators.phPhone('09171234567'), isNull);
    expect(AppValidators.phPhone('9171234567'), isNotNull);
    expect(AppValidators.phPhone('0917123456'), isNotNull);
  });

  test('Dates use MM/DD/YYYY and 12-hour time', () {
    expect(AppFormatters.formatDate(DateTime(2026, 3, 5)), '03/05/2026');
    expect(
      AppFormatters.formatDateTime(DateTime(2026, 3, 5, 14, 30)),
      '03/05/2026 02:30 PM',
    );
  });

  testWidgets('Sidebar enforces role visibility for Admin, Manager, and Staff', (
    tester,
  ) async {
    // Tall viewport so the lazy sidebar ListView builds every menu item.
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppUser makeUser(UserRole role) => AppUser(
      uid: 'u1',
      userEmail: '${role.name}@catchup.ph',
      fullName: 'Test ${role.label}',
      role: role,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

    Future<void> pumpSidebar(UserRole role) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSidebar(
              currentLocation: '/dashboard',
              user: makeUser(role),
              onNavigate: (_) {},
              onLogout: () {},
            ),
          ),
        ),
      );
    }

    void expectMenus(Set<String> visible) {
      const all = [
        'Dashboard',
        'Inventory',
        'Transactions',
        'Products',
        'Suppliers',
        'Storage Locations',
        'Waste Records',
        'Reports',
        'Users',
        'Settings',
      ];
      for (final label in all) {
        expect(
          find.text(label),
          visible.contains(label) ? findsOneWidget : findsNothing,
          reason: '$label visibility',
        );
      }
    }

    // 1. Staff: Dashboard, Inventory, Storage Locations, Waste Records only
    await pumpSidebar(UserRole.staff);
    expectMenus({
      'Dashboard',
      'Inventory',
      'Storage Locations',
      'Waste Records',
    });

    // 2. Manager: everything except Inventory, Storage Locations, Waste Records
    await pumpSidebar(UserRole.manager);
    expectMenus({
      'Dashboard',
      'Transactions',
      'Products',
      'Suppliers',
      'Reports',
      'Users',
      'Settings',
    });

    // 3. Admin: all 10 modules
    await pumpSidebar(UserRole.admin);
    expectMenus({
      'Dashboard',
      'Inventory',
      'Transactions',
      'Products',
      'Suppliers',
      'Storage Locations',
      'Waste Records',
      'Reports',
      'Users',
      'Settings',
    });
  });
  testWidgets('All modules render empty states and 0s when no data exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final admin = AppUser(
      uid: 'admin1',
      userEmail: 'admin@catchup.ph',
      fullName: 'Maria Santos',
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

    final emptyOverrides = [
      currentUserProfileProvider.overrideWith((ref) => Stream.value(admin)),
      productsStreamProvider.overrideWith((ref) => Stream.value(<Product>[])),
      suppliersStreamProvider.overrideWith((ref) => Stream.value(<Supplier>[])),
      storageLocationsStreamProvider.overrideWith(
        (ref) => Stream.value(<StorageLocation>[]),
      ),
      transactionsStreamProvider.overrideWith(
        (ref) => Stream.value(<StockTransaction>[]),
      ),
      wasteRecordsStreamProvider.overrideWith(
        (ref) => Stream.value(<WasteRecord>[]),
      ),
      usersStreamProvider.overrideWith((ref) => Stream.value(<AppUser>[admin])),
      appSettingsStreamProvider.overrideWith(
        (ref) => Stream.value(const AppSettings()),
      ),
    ];

    // Dashboard empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good day, Maria Santos!'), findsOneWidget);
    expect(
      find.text('No data yet. Record your first transaction to see the chart.'),
      findsWidgets,
    );

    // Inventory empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No inventory items yet'), findsOneWidget);

    // Products empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: ProductsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No products yet. Tap Add Product to get started.'),
      findsOneWidget,
    );

    // Suppliers empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: SuppliersScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No suppliers yet. Tap Add Supplier to get started.'),
      findsOneWidget,
    );

    // Storage Locations empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(
          home: Scaffold(body: StorageLocationsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No storage locations yet. Tap Add Storage Location to get started.',
      ),
      findsOneWidget,
    );

    // Transactions empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: TransactionsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Record Transaction'), findsOneWidget);

    // Waste Records empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: WasteRecordsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Record Waste'), findsOneWidget);

    // Reports empty state
    await tester.pumpWidget(
      ProviderScope(
        overrides: emptyOverrides,
        child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No records for this period.'), findsOneWidget);
  });

  test(
    'Calculated stock = Incoming - Outgoing - Waste (ignoring voided)',
    () async {
      final p1 = Product(
        productId: 'P001',
        productName: 'Bangus',
        category: 'Fish',
        type: 'Fish',
        unit: 'kg',
        price: 180,
        minimumStock: 10,
        reorderPoint: 15,
        productMovement: 'Fast Moving',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      final txs = [
        StockTransaction(
          transactionId: 'T001',
          type: 'Incoming',
          productId: 'P001',
          productName: 'Bangus',
          quantity: 50,
          unit: 'kg',
          storageId: 'ST001',
          storageName: 'Chiller 1',
          dateTime: DateTime(2026, 1, 2),
          notes: '',
          recordedBy: 'staff@catchup.ph',
        ),
        StockTransaction(
          transactionId: 'T002',
          type: 'Outgoing',
          productId: 'P001',
          productName: 'Bangus',
          quantity: 15,
          unit: 'kg',
          storageId: 'ST001',
          storageName: 'Chiller 1',
          dateTime: DateTime(2026, 1, 3),
          notes: '',
          recordedBy: 'staff@catchup.ph',
        ),
        // Voided transaction should not affect stock
        StockTransaction(
          transactionId: 'T003',
          type: 'Outgoing',
          productId: 'P001',
          productName: 'Bangus',
          quantity: 10,
          unit: 'kg',
          storageId: 'ST001',
          storageName: 'Chiller 1',
          dateTime: DateTime(2026, 1, 3),
          notes: '',
          recordedBy: 'staff@catchup.ph',
          isVoided: true,
        ),
      ];

      final waste = [
        WasteRecord(
          wasteId: 'W001',
          productId: 'P001',
          productName: 'Bangus',
          quantity: 5,
          unit: 'kg',
          wasteDateTime: DateTime(2026, 1, 4),
          reason: 'Spoiled',
          remarks: '',
          recordedBy: 'staff@catchup.ph',
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          productsStreamProvider.overrideWith((ref) => Stream.value([p1])),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(txs)),
          wasteRecordsStreamProvider.overrideWith((ref) => Stream.value(waste)),
        ],
      );
      addTearDown(container.dispose);

      // Keep providers alive and wait for the stream values to arrive
      container.listen(calculatedStockMapProvider, (_, _) {});
      await container.read(productsStreamProvider.future);
      await container.read(transactionsStreamProvider.future);
      await container.read(wasteRecordsStreamProvider.future);

      final map = container.read(calculatedStockMapProvider);
      // 50 Incoming - 15 Outgoing - 5 Waste = 30 kg
      expect(map['P001'], 30.0);
    },
  );
}
