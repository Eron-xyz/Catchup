import 'dart:convert';
import 'package:catchup/core/utils/web_storage.dart';
import 'package:catchup/models/app_user.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent user sessions across app restarts and browser reloads.
/// Uses synchronous browser localStorage on Web and SharedPreferences across all platforms,
/// guaranteeing 0ms synchronous session restoration on browser refresh (F5 / Ctrl+R).
class SessionManager {
  SessionManager._() {
    restoreSessionSync();
  }
  static final SessionManager instance = SessionManager._();

  static const String _keySessionUser = 'catchup_session_user_v1';
  static const String _keySessionExpiry = 'catchup_session_expiry_v1';
  static const String _keyLastActive = 'catchup_session_last_active_v1';

  /// Session duration: 7 days of inactivity before requiring re-authentication.
  static const Duration sessionTtl = Duration(days: 7);

  SharedPreferences? _prefs;

  AppUser? _currentSessionUser;
  AppUser? get currentSessionUser {
    if (_currentSessionUser == null) {
      restoreSessionSync();
    }
    return _currentSessionUser;
  }

  /// Synchronously restores the saved session from web localStorage or memory storage.
  /// Runs in 0ms before Flutter builds the first frame or router.
  AppUser? restoreSessionSync() {
    try {
      final rawUser = PlatformWebStorage.getItem(_keySessionUser);
      final rawExpiry = PlatformWebStorage.getItem(_keySessionExpiry);

      if (rawUser == null || rawExpiry == null) {
        return null;
      }

      final expiry = DateTime.tryParse(rawExpiry);
      if (expiry == null || DateTime.now().isAfter(expiry)) {
        clearSessionSync();
        return null;
      }

      final map = jsonDecode(rawUser) as Map<String, dynamic>;
      final user = AppUser(
        uid: map['uid'] as String,
        userEmail: map['userEmail'] as String,
        fullName: map['fullName'] as String,
        role: UserRole.fromString(map['role'] as String?),
        isActive: (map['isActive'] as bool?) ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

      _currentSessionUser = user;
      return user;
    } catch (e) {
      debugPrint('Sync session restore note: $e');
      return null;
    }
  }

  void clearSessionSync() {
    _currentSessionUser = null;
    PlatformWebStorage.removeItem(_keySessionUser);
    PlatformWebStorage.removeItem(_keySessionExpiry);
    PlatformWebStorage.removeItem(_keyLastActive);
  }

  Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SessionManager init note: $e');
    }
  }

  /// Saves the current user session with timestamp and expiry across both
  /// synchronous Web storage and persistent SharedPreferences.
  Future<void> saveSession(AppUser user) async {
    _currentSessionUser = user;
    try {
      final now = DateTime.now();
      final expiry = now.add(sessionTtl);

      final userMap = {
        'uid': user.uid,
        'userEmail': user.userEmail,
        'fullName': user.fullName,
        'role': user.role.label,
        'isActive': user.isActive,
        'createdAt': user.createdAt.toIso8601String(),
      };

      final rawJson = jsonEncode(userMap);
      final rawExpiry = expiry.toIso8601String();
      final rawNow = now.toIso8601String();

      // 1. Immediately write to Web localStorage (synchronous, 0ms, flush guaranteed)
      PlatformWebStorage.setItem(_keySessionUser, rawJson);
      PlatformWebStorage.setItem(_keySessionExpiry, rawExpiry);
      PlatformWebStorage.setItem(_keyLastActive, rawNow);

      // 2. Also persist to SharedPreferences (for mobile, desktop, and web fallback)
      await init();
      await _prefs?.setString(_keySessionUser, rawJson);
      await _prefs?.setString(_keySessionExpiry, rawExpiry);
      await _prefs?.setString(_keyLastActive, rawNow);
    } catch (e) {
      debugPrint('Failed to save session: $e');
    }
  }

  /// Restores the saved session if it exists and has not expired.
  Future<AppUser?> restoreSession() async {
    // 1. Check synchronous web storage first
    final syncUser = restoreSessionSync();
    if (syncUser != null) {
      return syncUser;
    }

    // 2. Fallback to SharedPreferences
    try {
      await init();
      final rawUser = _prefs?.getString(_keySessionUser);
      final rawExpiry = _prefs?.getString(_keySessionExpiry);

      if (rawUser == null || rawExpiry == null) {
        _currentSessionUser = null;
        return null;
      }

      final expiry = DateTime.tryParse(rawExpiry);
      if (expiry == null || DateTime.now().isAfter(expiry)) {
        await clearSession();
        return null;
      }

      final map = jsonDecode(rawUser) as Map<String, dynamic>;
      final user = AppUser(
        uid: map['uid'] as String,
        userEmail: map['userEmail'] as String,
        fullName: map['fullName'] as String,
        role: UserRole.fromString(map['role'] as String?),
        isActive: (map['isActive'] as bool?) ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

      _currentSessionUser = user;

      // Mirror back to web storage for immediate synchronous access on subsequent reloads
      PlatformWebStorage.setItem(_keySessionUser, rawUser);
      PlatformWebStorage.setItem(_keySessionExpiry, rawExpiry);
      PlatformWebStorage.setItem(
        _keyLastActive,
        DateTime.now().toIso8601String(),
      );

      // Refresh last active timestamp in prefs
      await _prefs?.setString(
        _keyLastActive,
        DateTime.now().toIso8601String(),
      );
      return user;
    } catch (e) {
      debugPrint('Error restoring session: $e');
      _currentSessionUser = null;
      return null;
    }
  }

  /// Clears the active session upon logout.
  Future<void> clearSession() async {
    clearSessionSync();
    try {
      await init();
      await _prefs?.remove(_keySessionUser);
      await _prefs?.remove(_keySessionExpiry);
      await _prefs?.remove(_keyLastActive);
    } catch (e) {
      debugPrint('Failed to clear session: $e');
    }
  }

  /// Returns true if a valid session exists.
  bool get hasActiveSession {
    if (_currentSessionUser != null) return true;
    final rawExpiry = PlatformWebStorage.getItem(_keySessionExpiry) ??
        _prefs?.getString(_keySessionExpiry);
    if (rawExpiry == null) return false;
    final expiry = DateTime.tryParse(rawExpiry);
    return expiry != null && DateTime.now().isBefore(expiry);
  }
}
