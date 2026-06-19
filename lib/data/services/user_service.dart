import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureUserDoc() async {
  final user = FirebaseAuth.instance.currentUser!;
  final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final snap = await ref.get();

  if (!snap.exists) {
    // First time signup → create profile doc
    await ref.set({
      'displayName': user.displayName ?? '',
      'email': user.email,
      'photoURL': user.photoURL,
      'role': 'student', // default role
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    });
  } else {
    // Existing user → just update their "lastSeen"
    await ref.update({
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}
