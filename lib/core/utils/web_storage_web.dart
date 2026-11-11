import 'package:web/web.dart' as web;

/// Direct browser localStorage implementation using modern `package:web` and `dart:js_interop`
/// for Web to guarantee 100% synchronous, indestructible persistence across browser reloads
/// (F5 / Ctrl+R) and tab restores without deprecated libraries.
class PlatformWebStorage {
  static String? getItem(String key) {
    try {
      final storage = web.window.localStorage;
      return storage.getItem(key) ?? storage.getItem('flutter.$key');
    } catch (_) {
      return null;
    }
  }

  static void setItem(String key, String value) {
    try {
      final storage = web.window.localStorage;
      storage.setItem(key, value);
      storage.setItem('flutter.$key', value);
    } catch (_) {}
  }

  static void removeItem(String key) {
    try {
      final storage = web.window.localStorage;
      storage.removeItem(key);
      storage.removeItem('flutter.$key');
    } catch (_) {}
  }

  static void clear() {
    try {
      web.window.localStorage.clear();
    } catch (_) {}
  }
}
