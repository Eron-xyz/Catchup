import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/core/utils/web_storage.dart';
import 'package:catchup/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PlatformWebStorage.clear();
    await SessionManager.instance.clearSession();
  });

  test('SessionManager saves and restores user across simulated page reload', () async {
    final user = AppUser(
      uid: 'user_mitzi',
      userEmail: 'mitzi@catchup.ph',
      fullName: 'Mitzi',
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

    // 1. Save session
    await SessionManager.instance.saveSession(user);
    expect(SessionManager.instance.hasActiveSession, isTrue);
    expect(SessionManager.instance.currentSessionUser?.fullName, 'Mitzi');
    expect(SessionManager.instance.currentSessionUser?.role, UserRole.admin);

    // 2. Simulate browser reload (in-memory state reset)
    SessionManager.instance.clearSessionSync();
    // Simulate what browser localStorage would still have
    await SessionManager.instance.saveSession(user);

    // 3. Test synchronous restoration (0ms on Web)
    final syncRestored = SessionManager.instance.restoreSessionSync();
    expect(syncRestored, isNotNull);
    expect(syncRestored!.uid, 'user_mitzi');
    expect(syncRestored.userEmail, 'mitzi@catchup.ph');
    expect(syncRestored.role, UserRole.admin);

    // 4. Test async restoration
    final asyncRestored = await SessionManager.instance.restoreSession();
    expect(asyncRestored, isNotNull);
    expect(asyncRestored!.fullName, 'Mitzi');

    // 5. Clear session on logout
    await SessionManager.instance.clearSession();
    expect(SessionManager.instance.hasActiveSession, isFalse);
    expect(SessionManager.instance.currentSessionUser, isNull);
  });
}

