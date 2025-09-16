import 'package:cloud_firestore/cloud_firestore.dart';

class PresenceService {
  static final CollectionReference _users =
      FirebaseFirestore.instance.collection('users');

  static Future<void> setOnline({
    required String userId,
    required String userType,
  }) async {
    if (userId.isEmpty) return;
    try {
      await _users.doc(userId).set({
        'isOnline': true,
        'userType': userType,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> setOffline({
    required String userId,
  }) async {
    if (userId.isEmpty) return;
    try {
      await _users.doc(userId).set({
        'isOnline': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}


