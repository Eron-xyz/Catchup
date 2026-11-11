import 'package:cloud_firestore/cloud_firestore.dart';

/// Generates sequential custom IDs (P001, T001, S001, ST001, W001)
/// using a `counters` collection in Cloud Firestore.
/// Starts at 0 so the first generated ID is 001.
class CounterService {
  final FirebaseFirestore _firestore;

  CounterService(this._firestore);

  /// Atomically increments the counter for [counterKey] and returns the formatted ID
  /// (e.g. prefix 'P' -> 'P001').
  /// Can be called inside an existing [Transaction] or standalone.
  Future<String> getNextId({
    required String counterKey,
    required String prefix,
    Transaction? transaction,
  }) async {
    final docRef = _firestore.collection('counters').doc(counterKey);

    if (transaction != null) {
      final snap = await transaction.get(docRef);
      final current = (snap.data()?['current'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      transaction.set(docRef, {'current': next}, SetOptions(merge: true));
      return '$prefix${next.toString().padLeft(3, '0')}';
    } else {
      return _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = (snap.data()?['current'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        tx.set(docRef, {'current': next}, SetOptions(merge: true));
        return '$prefix${next.toString().padLeft(3, '0')}';
      });
    }
  }
}
