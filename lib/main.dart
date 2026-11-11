import 'package:catchup/core/router/app_router.dart';
import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure in-memory image cache ceiling (100 images / 60 MB) for smooth scrolling.
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 << 20;

  // Initialize persistent Session Manager
  await SessionManager.instance.init();
  final restoredUser = await SessionManager.instance.restoreSession();
  if (restoredUser != null) {
    LocalDemoStore.instance.syncFirebaseUser(restoredUser);
    ApiResponseCache.instance.set('user_${restoredUser.uid}', restoredUser);
  }

  // Initialize Firebase and warm up the pooled Firestore connection & local cache.
  var firebaseReady = false;
  if (!DefaultFirebaseOptions.isPlaceholder) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
      try {
        // Warm up pooled Firestore instance with unlimited offline/response cache.
        FirestoreConnectionPool.instance.db;
      } catch (e) {
        debugPrint('Firestore warmup note: $e');
      }
    } catch (e) {
      debugPrint('Firebase initialization note: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [firebaseReadyProvider.overrideWithValue(firebaseReady)],
      child: const CatchUpApp(),
    ),
  );
}

class CatchUpApp extends ConsumerWidget {
  const CatchUpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use `.select(...)` to prevent root MaterialApp re-renders unless dark mode changes.
    final isDarkMode = ref.watch(
      appSettingsStreamProvider.select((s) => s.value?.isDarkMode ?? false),
    );
    final themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;

    return MaterialApp.router(
      title: 'CatchUP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
