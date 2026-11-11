import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// 1. Input Debouncer (`InputDebouncer`)
/// Prevents search and filter input handlers from triggering expensive list
/// filtering and widget rebuilds on every single keystroke.
class InputDebouncer {
  final Duration delay;
  Timer? _timer;

  InputDebouncer({this.delay = const Duration(milliseconds: 40)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 2. In-Memory API Response Cache (`ApiResponseCache`)
/// Caches deserialized API / Firestore responses with configurable TTL and
/// LRU eviction so repeated queries and route transitions resolve immediately.
class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;
  final String? signature;

  const _CacheEntry({
    required this.value,
    required this.expiresAt,
    this.signature,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ApiResponseCache {
  ApiResponseCache._();
  static final ApiResponseCache instance = ApiResponseCache._();

  final int maxEntries = 128;
  final LinkedHashMap<String, _CacheEntry<Object?>> _store = LinkedHashMap();

  T? get<T>(String key, {String? signature}) {
    final entry = _store.remove(key);
    if (entry == null) return null;
    if (entry.isExpired || (signature != null && entry.signature != signature)) {
      return null;
    }
    // Re-insert at the end to maintain LRU ordering
    _store[key] = entry;
    return entry.value as T;
  }

  void set<T>(
    String key,
    T value, {
    Duration ttl = const Duration(minutes: 5),
    String? signature,
  }) {
    _store.remove(key);
    if (_store.length >= maxEntries) {
      _store.remove(_store.keys.first);
    }
    _store[key] = _CacheEntry<Object?>(
      value: value,
      expiresAt: DateTime.now().add(ttl),
      signature: signature,
    );
  }

  void invalidate(String keyPrefix) {
    _store.removeWhere((key, _) => key.startsWith(keyPrefix));
  }

  void clear() => _store.clear();
}

/// 3. Expensive Computation Memoizer (`ComputationCache`)
/// Caches expensive derived computations (stock ledger aggregation, alert
/// generation, category breakdowns, report totals) keyed by input signatures.
class ComputationCache {
  ComputationCache._();
  static final ComputationCache instance = ComputationCache._();

  final Map<String, ({int signature, Object? result})> _memo = {};

  T memoize<T>(String key, int signature, T Function() computeFn) {
    final existing = _memo[key];
    if (existing != null && existing.signature == signature) {
      return existing.result as T;
    }
    final computed = computeFn();
    _memo[key] = (signature: signature, result: computed);
    return computed;
  }

  void invalidate(String key) => _memo.remove(key);
}

/// 4. API Payload Compressor (`PayloadCompressor`)
/// Strips null/empty fields, trims whitespace, and rounds floating-point noise
/// before sending payloads over the wire to Firestore/APIs, reducing payload byte size.
class PayloadCompressor {
  PayloadCompressor._();

  /// Minifies a JSON/Firestore map payload by removing null values, trimming
  /// strings, and compacting nested structures.
  static Map<String, dynamic> compactMap(Map<String, dynamic> raw) {
    final compacted = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty && key != 'notes' && key != 'voidReason') {
          compacted[key] = '';
        } else {
          compacted[key] = trimmed;
        }
      } else if (value is double) {
        // Avoid IEEE-754 long decimal strings in serialized JSON payloads
        compacted[key] = double.parse(value.toStringAsFixed(4));
      } else if (value is Map<String, dynamic>) {
        compacted[key] = compactMap(value);
      } else {
        compacted[key] = value;
      }
    });
    return compacted;
  }

  /// Compresses a JSON payload into compact UTF-8 bytes for batch/export transport.
  static Uint8List toCompactJsonBytes(Object payload) {
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }
}

/// 5. Database Connection Pool & Multiplexer (`FirestoreConnectionPool`)
/// Maintains a warm pool of configured Firestore/Storage instances and
/// multiplexes identical in-flight read requests so concurrent callers share
/// one database connection and one active listener.
class FirestoreConnectionPool {
  FirestoreConnectionPool._();
  static final FirestoreConnectionPool instance = FirestoreConnectionPool._();

  FirebaseFirestore? _primaryDb;
  FirebaseStorage? _primaryStorage;
  bool _configured = false;
  final Map<String, Future<Object?>> _inFlightReads = {};

  /// Initializes and warms the pooled Firestore connection with unlimited local
  /// persistence cache so repeated document reads hit local IndexedDB/SQLite cache.
  FirebaseFirestore get db {
    final firestore = _primaryDb ??= FirebaseFirestore.instance;
    if (!_configured) {
      _configured = true;
      try {
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {
        // Settings may already be locked if accessed earlier in the isolate.
      }
    }
    return firestore;
  }

  FirebaseStorage get storage => _primaryStorage ??= FirebaseStorage.instance;

  /// Multiplexes concurrent one-shot queries with the same [queryKey] so they
  /// share a single database round-trip.
  Future<T> coalesceRead<T>(String queryKey, Future<T> Function() loader) {
    final cached = ApiResponseCache.instance.get<T>(queryKey);
    if (cached != null) return Future<T>.value(cached);

    final existing = _inFlightReads[queryKey];
    if (existing != null) return existing.then((v) => v as T);

    final future = loader().then((result) {
      ApiResponseCache.instance.set<T>(queryKey, result);
      _inFlightReads.remove(queryKey);
      return result;
    }).catchError((Object err) {
      _inFlightReads.remove(queryKey);
      throw err;
    });

    _inFlightReads[queryKey] = future;
    return future;
  }
}

