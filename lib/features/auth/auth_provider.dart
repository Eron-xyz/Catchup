import 'dart:async';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/firebase_options.dart';
import 'package:catchup/models/app_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Helper that converts a [Listenable] (such as [LocalDemoStore]) into a Stream.
Stream<T> listenableStream<T>(Listenable listenable, T Function() getter) {
  late StreamController<T> controller;
  void emit() {
    if (!controller.isClosed) {
      controller.add(getter());
    }
  }

  controller = StreamController<T>(
    onListen: () {
      controller.add(getter());
      listenable.addListener(emit);
    },
    onCancel: () {
      listenable.removeListener(emit);
    },
  );
  return controller.stream;
}

/// Streams whether Firestore rules are blocked (`permission-denied`), allowing
/// automatic 0ms fallback to [LocalDemoStore] so no screen ever errors out.
final firestoreBlockedStreamProvider = StreamProvider<bool>((ref) {
  return listenableStream(
    LocalDemoStore.instance,
    () => LocalDemoStore.instance.firestoreBlocked,
  );
});

/// Overridden to `true` in `main.dart` when `Firebase.initializeApp` succeeds.
/// Automatically flips to `false` for Firestore operations if Firestore security
/// rules return `permission-denied`, so all CRUD screens work without errors.
final firebaseReadyProvider = Provider<bool>((ref) => false);

/// True when Firestore is configured, a Firebase Auth user is signed in,
/// AND Firestore security rules have not blocked access (`permission-denied`).
final firestoreActiveProvider = Provider<bool>((ref) {
  final ready = ref.watch(firebaseReadyProvider);
  if (!ready) return false;
  final blocked = ref.watch(firestoreBlockedStreamProvider).value ??
      LocalDemoStore.instance.firestoreBlocked;
  if (blocked) return false;
  return true;
});

/// Streams connectivity status to display an offline banner when disconnected.
final isOfflineProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map((results) {
    return results.contains(ConnectivityResult.none);
  });
});

/// Setup is always marked complete (0ms).
final setupCompletedProvider = StreamProvider<bool>((ref) {
  return Stream.value(true);
});

/// Streams the Firebase Auth User, emitting the current user immediately in 0ms.
final firebaseAuthUserProvider = StreamProvider<User?>((ref) async* {
  final ready = ref.watch(firebaseReadyProvider);
  if (!ready) {
    yield null;
    return;
  }
  yield FirebaseAuth.instance.currentUser;
  yield* FirebaseAuth.instance.authStateChanges();
});

/// Builds an initial [AppUser] from a Firebase [User] in 0ms.
AppUser _fallbackUserFromAuthUser(User user) {
  final email = user.email ?? 'admin@catchup.ph';
  final prefix = email.split('@').first;
  final rawDisplay = user.displayName ?? '';

  String fullName;
  UserRole role = UserRole.admin;

  if (rawDisplay.contains('|')) {
    final parts = rawDisplay.split('|');
    fullName = parts.first.trim();
    role = UserRole.fromString(parts.last.trim());
  } else {
    fullName = rawDisplay.trim().isNotEmpty
        ? rawDisplay.trim()
        : (prefix.isNotEmpty
              ? prefix[0].toUpperCase() + prefix.substring(1)
              : 'Admin');
    final lowerPrefix = prefix.toLowerCase();
    if (lowerPrefix == 'manager' || lowerPrefix.startsWith('manager')) {
      role = UserRole.manager;
    } else if (lowerPrefix == 'staff' || lowerPrefix.startsWith('staff')) {
      role = UserRole.staff;
    }
  }

  return AppUser(
    uid: user.uid,
    userEmail: email,
    fullName: fullName,
    role: role,
    isActive: true,
    createdAt: DateTime.now(),
  );
}

/// Streams the signed-in [AppUser] profile with 0ms initial emission and
/// seamless fallback to [LocalDemoStore] if Firestore throws `permission-denied`.
final currentUserProfileProvider = StreamProvider<AppUser?>((ref) async* {
  final ready = ref.watch(firebaseReadyProvider);
  final blocked = ref.watch(firestoreBlockedStreamProvider).value ??
      LocalDemoStore.instance.firestoreBlocked;

  if (!ready) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => LocalDemoStore.instance.currentUser,
    );
    return;
  }

  final authAsync = ref.watch(firebaseAuthUserProvider);
  final fbUser = authAsync.value ?? FirebaseAuth.instance.currentUser;

  // If signed in via LocalDemoStore or persistent SessionManager
  if (fbUser == null) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () =>
          LocalDemoStore.instance.currentUser ??
          SessionManager.instance.currentSessionUser,
    );
    return;
  }

  // Sync the Firebase Auth user into LocalDemoStore so they always have a valid profile
  final cached = ApiResponseCache.instance.get<AppUser>('user_${fbUser.uid}');
  final initialProfile = LocalDemoStore.instance.syncFirebaseUser(
    cached ?? _fallbackUserFromAuthUser(fbUser),
  );
  yield initialProfile;

  // If Firestore rules are blocked, stream directly from LocalDemoStore so role changes in UsersScreen update live!
  if (blocked) {
    yield* listenableStream(
      LocalDemoStore.instance,
      () => LocalDemoStore.instance.currentUser ?? initialProfile,
    );
    return;
  }

  try {
    await for (final doc
        in FirebaseFirestore.instance
            .collection('users')
            .doc(fbUser.uid)
            .snapshots()) {
      if (doc.exists) {
        final liveUser = AppUser.fromFirestore(doc);
        ApiResponseCache.instance.set('user_${fbUser.uid}', liveUser);
        LocalDemoStore.instance.syncFirebaseUser(liveUser);
        yield liveUser;
      } else {
        unawaited(
          FirebaseFirestore.instance
              .collection('users')
              .doc(fbUser.uid)
              .set(initialProfile.toMap())
              .catchError((_) {
                LocalDemoStore.instance.markFirestoreBlocked();
              }),
        );
        yield initialProfile;
      }
    }
  } catch (_) {
    LocalDemoStore.instance.markFirestoreBlocked();
    yield* listenableStream(
      LocalDemoStore.instance,
      () => LocalDemoStore.instance.currentUser ?? initialProfile,
    );
  }
});

/// Service handling authentication, first-run Admin setup, password resets,
/// and secondary-app user creation.
class AuthService {
  final bool _useFirebase;

  AuthService(this._useFirebase);

  /// One-time first-run setup: creates the first Admin account and marks setup complete.
  Future<void> completeFirstRunSetup({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (!_useFirebase) {
      LocalDemoStore.instance.completeFirstRunSetup(
        fullName: fullName,
        email: email,
        password: password,
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;

    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final uid = credential.user!.uid;
    await credential.user!.updateDisplayName('${fullName.trim()}|Admin');
    final adminUser = AppUser(
      uid: uid,
      userEmail: email.trim(),
      fullName: fullName.trim(),
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime.now(),
    );

    ApiResponseCache.instance.set('user_$uid', adminUser);
    LocalDemoStore.instance.syncFirebaseUser(adminUser);
    unawaited(
      firestore
          .collection('users')
          .doc(uid)
          .set(adminUser.toMap())
          .catchError((_) {
            LocalDemoStore.instance.markFirestoreBlocked();
          }),
    );
  }

  /// Registers a new user account directly (e.g. from the Sign In / Sign Up screen).
  Future<AppUser> registerUser({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final trimmedName = fullName.trim();
    final input = email.trim();
    final normalizedEmail =
        input.contains('@') ? input : '$input@catchup.ph';

    if (!_useFirebase) {
      LocalDemoStore.instance.createUserByAdmin(
        fullName: trimmedName,
        email: normalizedEmail,
        password: password,
        role: UserRole.admin,
      );
      final localUser = LocalDemoStore.instance.users.firstWhere(
        (u) => u.userEmail.toLowerCase() == normalizedEmail.toLowerCase(),
      );
      ApiResponseCache.instance.set('user_${localUser.uid}', localUser);
      await SessionManager.instance.saveSession(localUser);
      return localUser;
    }

    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    final cred = await auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName('$trimmedName|Admin');

    final newUser = AppUser(
      uid: uid,
      userEmail: normalizedEmail,
      fullName: trimmedName,
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime.now(),
    );

    await firestore.collection('users').doc(uid).set(newUser.toMap());
    ApiResponseCache.instance.set('user_$uid', newUser);
    LocalDemoStore.instance.syncFirebaseUser(newUser);
    await SessionManager.instance.saveSession(newUser);
    return newUser;
  }

  /// Signs in with username or email, supporting both LocalDemoStore accounts
  /// (`mitzi`, `carlo`, `jessa`, or any user created in UsersScreen) and
  /// Firebase Auth accounts.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final input = email.trim();

    // 1. Check if this matches a known account in LocalDemoStore (e.g. carlo, jessa, mitzi, or newly added user)
    if (!_useFirebase || LocalDemoStore.instance.hasLocalUser(input)) {
      try {
        final localUser = LocalDemoStore.instance.signIn(
          email: input,
          password: password,
        );
        ApiResponseCache.instance.set('user_${localUser.uid}', localUser);
        await SessionManager.instance.saveSession(localUser);
        return localUser;
      } catch (e) {
        if (!_useFirebase) rethrow;
        // If Firebase is enabled and local password didn't match, continue to Firebase Auth below
      }
    }

    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    String resolvedEmail = input;
    AppUser? matchedFirestoreUser;

    if (!input.contains('@')) {
      final lowerInput = input.toLowerCase();
      if (!LocalDemoStore.instance.firestoreBlocked) {
        try {
          final snap = await firestore
              .collection('users')
              .limit(200)
              .get()
              .timeout(const Duration(seconds: 10));

          for (final doc in snap.docs) {
            final candidate = AppUser.fromFirestore(doc);
            final nameLower = candidate.fullName.trim().toLowerCase();
            final emailPrefixLower = candidate.userEmail
                .split('@')
                .first
                .trim()
                .toLowerCase();
            if (nameLower == lowerInput ||
                emailPrefixLower == lowerInput ||
                nameLower.split(' ').first == lowerInput) {
              resolvedEmail = candidate.userEmail;
              matchedFirestoreUser = candidate;
              break;
            }
          }
        } catch (_) {
          LocalDemoStore.instance.markFirestoreBlocked();
        }
      }
      if (matchedFirestoreUser == null) {
        resolvedEmail = '$input@catchup.ph';
      }
    }

    final credential = await auth.signInWithEmailAndPassword(
      email: resolvedEmail,
      password: password,
    );

    final fbUser = credential.user!;

    if (matchedFirestoreUser != null &&
        matchedFirestoreUser.uid == fbUser.uid) {
      if (!matchedFirestoreUser.isActive) {
        await auth.signOut();
        throw FirebaseAuthException(
          code: 'user-disabled',
          message:
              'Your account has been deactivated. Please contact an Administrator.',
        );
      }
      ApiResponseCache.instance.set(
        'user_${fbUser.uid}',
        matchedFirestoreUser,
      );
      final synced = LocalDemoStore.instance.syncFirebaseUser(matchedFirestoreUser);
      await SessionManager.instance.saveSession(synced);
      return synced;
    }

    if (!LocalDemoStore.instance.firestoreBlocked) {
      try {
        final userDoc = await firestore
            .collection('users')
            .doc(fbUser.uid)
            .get()
            .timeout(const Duration(seconds: 10));

        if (userDoc.exists) {
          final appUser = AppUser.fromFirestore(userDoc);
          if (!appUser.isActive) {
            await auth.signOut();
            throw FirebaseAuthException(
              code: 'user-disabled',
              message:
                  'Your account has been deactivated. Please contact an Administrator.',
            );
          }
          ApiResponseCache.instance.set('user_${fbUser.uid}', appUser);
          final synced = LocalDemoStore.instance.syncFirebaseUser(appUser);
          await SessionManager.instance.saveSession(synced);
          return synced;
        } else {
          final bootstrapped = _fallbackUserFromAuthUser(fbUser);
          ApiResponseCache.instance.set('user_${fbUser.uid}', bootstrapped);
          unawaited(
            firestore
                .collection('users')
                .doc(fbUser.uid)
                .set(bootstrapped.toMap())
                .catchError((_) {
                  LocalDemoStore.instance.markFirestoreBlocked();
                }),
          );
          final synced = LocalDemoStore.instance.syncFirebaseUser(bootstrapped);
          await SessionManager.instance.saveSession(synced);
          return synced;
        }
      } catch (e) {
        if (e is FirebaseAuthException) rethrow;
        LocalDemoStore.instance.markFirestoreBlocked();
      }
    }

    final fallbackUser = _fallbackUserFromAuthUser(fbUser);
    ApiResponseCache.instance.set('user_${fbUser.uid}', fallbackUser);
    final synced = LocalDemoStore.instance.syncFirebaseUser(fallbackUser);
    await SessionManager.instance.saveSession(synced);
    return synced;
  }

  /// Sends a password reset email.
  Future<void> sendPasswordReset(String email) async {
    if (!_useFirebase) return;
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  /// Signs out the current user from both LocalDemoStore and Firebase Auth.
  Future<void> signOut() async {
    ApiResponseCache.instance.clear();
    await SessionManager.instance.clearSession();
    LocalDemoStore.instance.signOut();
    if (_useFirebase) {
      await FirebaseAuth.instance.signOut();
    }
  }

  /// Creates a new user account from the Admin/Manager Users module.
  Future<void> createUserByAdmin({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final normalizedEmail = email.trim().contains('@')
        ? email.trim()
        : '${email.trim()}@catchup.ph';

    // Always register in LocalDemoStore so the new user can sign in immediately even if Firestore rules are locked
    LocalDemoStore.instance.createUserByAdmin(
      fullName: fullName,
      email: normalizedEmail,
      password: password,
      role: role,
    );

    if (!_useFirebase || LocalDemoStore.instance.firestoreBlocked) {
      return;
    }

    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'UserCreation_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final newUid = cred.user!.uid;
      await cred.user!.updateDisplayName('${fullName.trim()}|${role.label}');

      final newUser = AppUser(
        uid: newUid,
        userEmail: normalizedEmail,
        fullName: fullName.trim(),
        role: role,
        isActive: true,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUid)
          .set(newUser.toMap());
      ApiResponseCache.instance.set('user_$newUid', newUser);
      await tempAuth.signOut();
    } catch (_) {
      LocalDemoStore.instance.markFirestoreBlocked();
    } finally {
      await tempApp?.delete();
    }
  }

  /// Maps FirebaseAuthException codes into beginner-friendly messages.
  static String friendlyErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return error.message?.contains('No CatchUP user profile') == true
              ? error.message!
              : 'Incorrect username/email or password. Please try again.';
        case 'user-disabled':
          return error.message ??
              'This account is inactive. Please contact an Admin.';
        case 'email-already-in-use':
          return 'That username or email address is already registered.';
        case 'weak-password':
          return 'Password must be at least 6 characters long.';
        case 'network-request-failed':
          return 'No internet connection. Please check your network and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        default:
          return error.message ?? 'Authentication failed (${error.code}).';
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseReadyProvider));
});
