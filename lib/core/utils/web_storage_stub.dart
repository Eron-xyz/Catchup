/// Stub implementation for non-web platforms (Android, iOS, Windows, macOS, Linux).
class PlatformWebStorage {
  static final Map<String, String> _memoryStorage = {};

  static String? getItem(String key) => _memoryStorage[key];

  static void setItem(String key, String value) {
    _memoryStorage[key] = value;
  }

  static void removeItem(String key) {
    _memoryStorage.remove(key);
  }

  static void clear() {
    _memoryStorage.clear();
  }
}

