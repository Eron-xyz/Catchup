import 'dart:async';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/core/widgets/app_shell_layout.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/features/auth/first_run_setup_screen.dart';
import 'package:catchup/features/auth/login_screen.dart';
import 'package:catchup/features/dashboard/dashboard_screen.dart';
import 'package:catchup/features/inventory/inventory_screen.dart';
import 'package:catchup/features/products/products_screen.dart';
import 'package:catchup/features/reports/reports_screen.dart'
    deferred as reports_chunk;
import 'package:catchup/features/settings/settings_screen.dart'
    deferred as settings_chunk;
import 'package:catchup/features/storage/storage_locations_screen.dart'
    deferred as storage_chunk;
import 'package:catchup/features/suppliers/suppliers_screen.dart'
    deferred as suppliers_chunk;
import 'package:catchup/features/transactions/transactions_screen.dart';
import 'package:catchup/features/users/users_screen.dart'
    deferred as users_chunk;
import 'package:catchup/features/waste/waste_records_screen.dart'
    deferred as waste_chunk;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Lazy-loads a deferred Dart/JS code chunk on demand and pre-warms all chunks
/// in the background so route navigation resolves in 0ms.
class _DeferredChunkLoader extends StatefulWidget {
  final String chunkKey;
  final Future<void> Function() loadLibrary;
  final WidgetBuilder builder;

  const _DeferredChunkLoader({
    required this.chunkKey,
    required this.loadLibrary,
    required this.builder,
  });

  static final Set<String> loadedChunks = <String>{};
  static bool _prewarmed = false;

  static void prewarmAll() {
    if (_prewarmed) return;
    _prewarmed = true;
    void warm(String key, Future<void> Function() loader) {
      unawaited(
        loader().then<void>((_) {
          loadedChunks.add(key);
        }).catchError((_) {}),
      );
    }

    warm('suppliers', suppliers_chunk.loadLibrary);
    warm('storage', storage_chunk.loadLibrary);
    warm('waste', waste_chunk.loadLibrary);
    warm('reports', reports_chunk.loadLibrary);
    warm('users', users_chunk.loadLibrary);
    warm('settings', settings_chunk.loadLibrary);
  }

  @override
  State<_DeferredChunkLoader> createState() => _DeferredChunkLoaderState();
}

class _DeferredChunkLoaderState extends State<_DeferredChunkLoader> {
  Future<void>? _loadFuture;

  @override
  void initState() {
    super.initState();
    if (!_DeferredChunkLoader.loadedChunks.contains(widget.chunkKey)) {
      _loadFuture = widget.loadLibrary().then((_) {
        _DeferredChunkLoader.loadedChunks.add(widget.chunkKey);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_DeferredChunkLoader.loadedChunks.contains(widget.chunkKey)) {
      return widget.builder(context);
    }
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return widget.builder(context);
        }
        return const CatchUpModuleSkeleton();
      },
    );
  }
}

Page<dynamic> _buildSmoothPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.012, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Page<dynamic> _buildAuthPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeIn),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// App routes + redirect rules with 0ms synchronous auth resolution.
final routerProvider = Provider<GoRouter>((ref) {
  // Eagerly pre-warm deferred chunks in the background so tab clicks are 0ms.
  _DeferredChunkLoader.prewarmAll();

  final refresh = ValueNotifier<int>(0);
  void bump([_, _]) => refresh.value++;
  ref.listen(firebaseAuthUserProvider, bump);
  ref.listen(currentUserProfileProvider, bump);
  LocalDemoStore.instance.addListener(bump);
  ref.onDispose(() {
    LocalDemoStore.instance.removeListener(bump);
    refresh.dispose();
  });

  final useFirebase = ref.read(firebaseReadyProvider);
  final sessionUser = SessionManager.instance.currentSessionUser ??
      LocalDemoStore.instance.currentUser;
  final signedInOnBoot = sessionUser != null ||
      (useFirebase && FirebaseAuth.instance.currentUser != null);

  return GoRouter(
    initialLocation: signedInOnBoot ? '/dashboard' : '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final useFb = ref.read(firebaseReadyProvider);
      final authUser = useFb
          ? (ref.read(firebaseAuthUserProvider).value ??
                FirebaseAuth.instance.currentUser)
          : null;
      final activeUser = SessionManager.instance.currentSessionUser ??
          LocalDemoStore.instance.currentUser;

      // 1. Signed out -> go straight to Login
      if (authUser == null && activeUser == null) {
        return loc == '/login' ? null : '/login';
      }

      // 2. Signed in -> resolve profile synchronously
      final user = ref.read(currentUserProfileProvider).value ?? activeUser;
      if (user != null && !user.isActive) {
        ref.read(authServiceProvider).signOut();
        return loc == '/login' ? null : '/login';
      }

      if (loc == '/splash' || loc == '/login' || loc == '/setup') {
        return '/dashboard';
      }

      // 3. Role guard: strictly enforce each role's allowed modules
      if (user != null && !user.canAccessRoute(loc)) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _buildAuthPage(
          key: state.pageKey,
          child: const _SplashScreen(),
        ),
      ),
      GoRoute(
        path: '/setup',
        pageBuilder: (context, state) => _buildAuthPage(
          key: state.pageKey,
          child: const FirstRunSetupScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildAuthPage(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShellLayout(
          currentLocation: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: const DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/inventory',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: InventoryScreen(
                initialLowStockOnly:
                    state.uri.queryParameters['lowStock'] == 'true',
              ),
            ),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: const TransactionsScreen(),
            ),
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: const ProductsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => _buildSmoothPage(
                  key: state.pageKey,
                  child: ProductDetailScreen(
                    productId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/suppliers',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'suppliers',
                loadLibrary: suppliers_chunk.loadLibrary,
                builder: (_) => suppliers_chunk.SuppliersScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/storage',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'storage',
                loadLibrary: storage_chunk.loadLibrary,
                builder: (_) => storage_chunk.StorageLocationsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/waste',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'waste',
                loadLibrary: waste_chunk.loadLibrary,
                builder: (_) => waste_chunk.WasteRecordsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'reports',
                loadLibrary: reports_chunk.loadLibrary,
                builder: (_) => reports_chunk.ReportsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'users',
                loadLibrary: users_chunk.loadLibrary,
                builder: (_) => users_chunk.UsersScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: _DeferredChunkLoader(
                chunkKey: 'settings',
                loadLibrary: settings_chunk.loadLibrary,
                builder: (_) => settings_chunk.SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CatchUpLoadingIndicator(message: 'Loading...'),
    );
  }
}
