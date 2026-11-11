import 'package:catchup/core/utils/counter_service.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/app_settings.dart';
import 'package:catchup/models/app_user.dart';
import 'package:catchup/models/product.dart';
import 'package:catchup/models/stock_transaction.dart';
import 'package:catchup/models/storage_location.dart';
import 'package:catchup/models/supplier.dart';
import 'package:catchup/models/waste_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides the pooled, persistence-enabled Firestore client instance.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirestoreConnectionPool.instance.db;
});

/// True only when Firebase is configured AND someone is signed in.
bool _signedIn(Ref ref) {
  return ref.watch(firebaseReadyProvider);
}

final counterServiceProvider = Provider<CounterService>((ref) {
  return CounterService(ref.watch(firestoreProvider));
});

/// Streams all active and inactive products with automatic fallback to
/// [LocalDemoStore] if Firestore security rules return `permission-denied`.
final productsStreamProvider = StreamProvider<List<Product>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<Product>.from(LocalDemoStore.instance.products),
    );
    return;
  }

  yield ApiResponseCache.instance.get<List<Product>>('products') ??
      const <Product>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('products')
        .orderBy('productId')
        .limit(500)
        .snapshots()) {
      final list = snap.docs.map(Product.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('products', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<Product>.from(LocalDemoStore.instance.products),
    );
  }
});

/// Streams only active products, memoized by product list identity.
final activeProductsProvider = Provider<List<Product>>((ref) {
  final all = ref.watch(productsStreamProvider).value ?? const <Product>[];
  return ComputationCache.instance.memoize<List<Product>>(
    'active_products',
    Object.hashAll(
      all.map((p) => Object.hash(p.productId, p.isActive, p.productName)),
    ),
    () => all.where((p) => p.isActive).toList(growable: false),
  );
});

/// Streams suppliers with automatic fallback to [LocalDemoStore].
final suppliersStreamProvider = StreamProvider<List<Supplier>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<Supplier>.from(LocalDemoStore.instance.suppliers),
    );
    return;
  }

  yield ApiResponseCache.instance.get<List<Supplier>>('suppliers') ??
      const <Supplier>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('suppliers')
        .orderBy('supplierId')
        .limit(500)
        .snapshots()) {
      final list =
          snap.docs.map(Supplier.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('suppliers', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<Supplier>.from(LocalDemoStore.instance.suppliers),
    );
  }
});

/// Streams storage locations with automatic fallback to [LocalDemoStore].
final storageLocationsStreamProvider =
    StreamProvider<List<StorageLocation>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () =>
          List<StorageLocation>.from(LocalDemoStore.instance.storageLocations),
    );
    return;
  }

  yield ApiResponseCache.instance
          .get<List<StorageLocation>>('storageLocations') ??
      const <StorageLocation>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('storageLocations')
        .orderBy('storageId')
        .limit(250)
        .snapshots()) {
      final list =
          snap.docs.map(StorageLocation.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('storageLocations', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () =>
          List<StorageLocation>.from(LocalDemoStore.instance.storageLocations),
    );
  }
});

/// Streams stock transactions, newest first, with automatic fallback to [LocalDemoStore].
final transactionsStreamProvider =
    StreamProvider<List<StockTransaction>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<StockTransaction>.from(LocalDemoStore.instance.transactions),
    );
    return;
  }

  yield ApiResponseCache.instance
          .get<List<StockTransaction>>('stockTransactions') ??
      const <StockTransaction>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('stockTransactions')
        .orderBy('dateTime', descending: true)
        .limit(500)
        .snapshots()) {
      final list =
          snap.docs.map(StockTransaction.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('stockTransactions', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<StockTransaction>.from(LocalDemoStore.instance.transactions),
    );
  }
});

/// Streams waste records, newest first, with automatic fallback to [LocalDemoStore].
final wasteRecordsStreamProvider =
    StreamProvider<List<WasteRecord>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<WasteRecord>.from(LocalDemoStore.instance.wasteRecords),
    );
    return;
  }

  yield ApiResponseCache.instance.get<List<WasteRecord>>('wasteRecords') ??
      const <WasteRecord>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('wasteRecords')
        .orderBy('wasteDateTime', descending: true)
        .limit(500)
        .snapshots()) {
      final list =
          snap.docs.map(WasteRecord.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('wasteRecords', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<WasteRecord>.from(LocalDemoStore.instance.wasteRecords),
    );
  }
});

/// Streams all users with automatic fallback to [LocalDemoStore].
final usersStreamProvider = StreamProvider<List<AppUser>>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<AppUser>.from(LocalDemoStore.instance.users),
    );
    return;
  }

  yield ApiResponseCache.instance.get<List<AppUser>>('users') ??
      const <AppUser>[];

  try {
    await for (final snap in ref
        .watch(firestoreProvider)
        .collection('users')
        .orderBy('fullName')
        .limit(250)
        .snapshots()) {
      final list = snap.docs.map(AppUser.fromFirestore).toList(growable: false);
      ApiResponseCache.instance.set('users', list);
      yield list;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => List<AppUser>.from(LocalDemoStore.instance.users),
    );
  }
});

/// Streams application settings with automatic fallback to [LocalDemoStore].
final appSettingsStreamProvider = StreamProvider<AppSettings>((ref) async* {
  ref.keepAlive();
  final useFirestore = ref.watch(firestoreActiveProvider);
  if (!useFirestore || !_signedIn(ref)) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => LocalDemoStore.instance.settings,
    );
    return;
  }

  yield ApiResponseCache.instance.get<AppSettings>('appSettings') ??
      LocalDemoStore.instance.settings;

  try {
    await for (final doc in ref
        .watch(firestoreProvider)
        .collection('settings')
        .doc('general')
        .snapshots()) {
      final settings = AppSettings.fromFirestore(doc);
      ApiResponseCache.instance.set('appSettings', settings);
      yield settings;
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => LocalDemoStore.instance.settings,
    );
  }
});

/// Computes and memoizes dynamic Stock on Hand per productId:
/// Current stock = total Incoming - total Outgoing - total Waste.
final calculatedStockMapProvider = Provider<Map<String, double>>((ref) {
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  final transactions =
      ref.watch(transactionsStreamProvider).value ?? const <StockTransaction>[];
  final wasteRecords =
      ref.watch(wasteRecordsStreamProvider).value ?? const <WasteRecord>[];

  final signature = Object.hash(
    products.length,
    Object.hashAll(products.map((p) => p.productId)),
    transactions.length,
    transactions.isEmpty ? '' : transactions.first.transactionId,
    transactions.fold<int>(0, (acc, t) => acc ^ (t.isVoided ? 1 : 0)),
    wasteRecords.length,
    wasteRecords.isEmpty ? '' : wasteRecords.first.wasteId,
    wasteRecords.fold<int>(0, (acc, w) => acc ^ (w.isVoided ? 1 : 0)),
  );

  return ComputationCache.instance.memoize<Map<String, double>>(
    'calculated_stock_map',
    signature,
    () {
      final Map<String, double> stockMap = {
        for (final p in products) p.productId: 0.0,
      };

      for (final tx in transactions) {
        if (tx.isVoided || tx.isReversal) continue;
        final current = stockMap[tx.productId] ?? 0.0;
        if (tx.isIncoming) {
          stockMap[tx.productId] = current + tx.quantity;
        } else if (tx.isOutgoing) {
          stockMap[tx.productId] = current - tx.quantity;
        }
      }

      for (final w in wasteRecords) {
        if (w.isVoided) continue;
        final current = stockMap[w.productId] ?? 0.0;
        stockMap[w.productId] = current - w.quantity;
      }

      return Map.unmodifiable(stockMap);
    },
  );
});

/// Alert item shown in the top notification bell and Dashboard Alerts panel.
class SystemAlert {
  final String title;
  final String subtitle;
  final String route;
  final bool isCritical;

  const SystemAlert({
    required this.title,
    required this.subtitle,
    required this.route,
    this.isCritical = false,
  });
}

/// Computes and memoizes live alerts for low stock, out of stock, below reorder
/// point, and storage location condition or >7 day inspection issues.
final systemAlertsProvider = Provider<List<SystemAlert>>((ref) {
  final products = ref.watch(activeProductsProvider);
  final stockMap = ref.watch(calculatedStockMapProvider);
  final storages = ref.watch(storageLocationsStreamProvider).value ??
      const <StorageLocation>[];

  final signature = Object.hash(
    products.length,
    Object.hashAll(stockMap.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(
      storages.map((s) => Object.hash(s.storageId, s.condition, s.lastChecked)),
    ),
  );

  return ComputationCache.instance.memoize<List<SystemAlert>>(
    'system_alerts',
    signature,
    () {
      final List<SystemAlert> alerts = [];

      for (final p in products) {
        final stock = stockMap[p.productId] ?? p.currentStock;
        if (stock <= 0) {
          alerts.add(
            SystemAlert(
              title: 'Out of Stock: ${p.productName} (${p.productId})',
              subtitle:
                  'Current stock is 0 ${p.unit}. Minimum: ${p.minimumStock} ${p.unit}.',
              route: '/inventory',
              isCritical: true,
            ),
          );
        } else if (stock <= p.minimumStock) {
          alerts.add(
            SystemAlert(
              title: 'Low Stock: ${p.productName} (${p.productId})',
              subtitle:
                  'Current: $stock ${p.unit} (Minimum: ${p.minimumStock} ${p.unit}).',
              route: '/inventory',
              isCritical: true,
            ),
          );
        } else if (stock <= p.reorderPoint) {
          alerts.add(
            SystemAlert(
              title: 'Reorder Point Reached: ${p.productName}',
              subtitle:
                  'Current: $stock ${p.unit} (Reorder Point: ${p.reorderPoint} ${p.unit}).',
              route: '/inventory',
            ),
          );
        }
      }

      for (final st in storages) {
        if (st.hasConditionIssue) {
          alerts.add(
            SystemAlert(
              title: 'Storage Condition: ${st.storageName} (${st.storageId})',
              subtitle:
                  'Status is "${st.condition}" (${st.temperatureMinC}°C to ${st.temperatureMaxC}°C).',
              route: '/storage',
              isCritical: st.condition == 'Out of Order',
            ),
          );
        }
        if (st.isOverdueCheck) {
          final days = DateTime.now().difference(st.lastChecked).inDays;
          alerts.add(
            SystemAlert(
              title: 'Inspection Overdue: ${st.storageName}',
              subtitle: 'Not checked in the last $days days.',
              route: '/storage',
            ),
          );
        }
      }

      return List.unmodifiable(alerts);
    },
  );
});
