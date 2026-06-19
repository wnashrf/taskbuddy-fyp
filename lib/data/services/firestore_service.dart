import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

class FirestoreService {
  FirestoreService._();
  static final instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception('Not signed in');
    return u.uid;
  }

  // ===== Helper: generate random join code =====
  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    return List.generate(length, (i) {
      final rand = (now + i * 37) % chars.length;
      return chars[rand];
    }).join();
  }

  // ===== COURSES =====
  Future<String> createCourse({required String name}) async {
    final courseRef = _db.collection('courses').doc();

    // create a stable global key for everyone in the same real course
    final globalCourseId = name.trim().toLowerCase().replaceAll(' ', '_');

    await courseRef.set({
      'name': name.trim(),
      'ownerId': _uid,
      'members': [_uid],
      'membersCount': 1,
      'globalCourseId': globalCourseId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await courseRef.collection('members').doc(_uid).set({
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    return courseRef.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myCoursesStream() {
    return _db
        .collection('courses')
        .where('members', arrayContains: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ===== ASSIGNMENTS (individual, under courses) =====
  Future<String> createAssignment(
      String courseId, {
        required String title,
        DateTime? dueDate,
        bool addCreatorAsMember = true,
      }) async {
    final aRef =
    _db.collection('courses').doc(courseId).collection('assignments').doc();
    await aRef.set({
      'title': title.trim(),
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _uid,
      'members': addCreatorAsMember ? [_uid] : [],
      'membersCount': addCreatorAsMember ? 1 : 0,
    });
    return aRef.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> assignmentsStream(
      String courseId,
      ) {
    return _db
        .collection('courses')
        .doc(courseId)
        .collection('assignments')
        .where('members', arrayContains: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> assignmentTasksStream(
      String courseId,
      String assignmentId, {
        String? status,
      }) {
    var query = _db
        .collection('courses')
        .doc(courseId)
        .collection('assignments')
        .doc(assignmentId)
        .collection('tasks')
        .orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots();
  }

  Future<void> createAssignmentTask(
      String courseId,
      String assignmentId, {
        required Map<String, dynamic> data,
      }) async {
    final taskRef = _db
        .collection('courses')
        .doc(courseId)
        .collection('assignments')
        .doc(assignmentId)
        .collection('tasks')
        .doc();

    // Merge in server timestamp if not provided
    data['createdAt'] ??= FieldValue.serverTimestamp();
    data['createdBy'] ??= _uid;

    await taskRef.set(data);
  }

  // ===== GROUPS (global collaborative assignments) =====
  Future<String> createGroup({
    required String courseId,
    required String title,
    DateTime? dueDate,
  }) async {
    final groupRef = _db.collection('groups').doc();
    // get the course doc first to fetch its globalCourseId
    final courseDoc = await _db.collection('courses').doc(courseId).get();
    final globalCourseId = courseDoc.data()?['globalCourseId'];

    await groupRef.set({
      'courseId': courseId,
      'globalCourseId': globalCourseId,  // ✅ NEW FIELD
      'title': title.trim(),
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _uid,
      'members': [_uid],
      'membersCount': 1,
      'joinCode': _generateJoinCode(),
    });
    return groupRef.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myGroupsStream(String courseId) {
    return _db
        .collection('groups')
        .where('courseId', isEqualTo: courseId)
        .where(Filter.or(
      Filter('createdBy', isEqualTo: _uid),
      Filter('members', arrayContains: _uid),
    ))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ===== GROUP JOIN REQUESTS =====
  Future<void> requestJoinGroup(String groupId) async {
    final groupRef = _db.collection('groups').doc(groupId);
    await groupRef.collection('joinRequests').doc(_uid).set({
      'uid': _uid,
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> groupJoinRequestsStream(
      String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('joinRequests')
        .orderBy('requestedAt', descending: true)
        .snapshots();
  }

  Future<void> approveJoinGroup(String groupId, String requesterUid) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final reqRef = groupRef.collection('joinRequests').doc(requesterUid);

    await _db.runTransaction((tx) async {
      final s = await tx.get(groupRef);
      final d = s.data() as Map<String, dynamic>;
      final List members = List.from(d['members'] ?? []);
      if (!members.contains(requesterUid)) {
        members.add(requesterUid);
        tx.update(groupRef, {
          'members': members,
          'membersCount': FieldValue.increment(1),
        });
      }
      tx.delete(reqRef);
    });
  }

  Future<void> rejectJoinGroup(String groupId, String requesterUid) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('joinRequests')
        .doc(requesterUid)
        .delete();
  }

  // ===== GROUP TASKS =====
  Stream<QuerySnapshot<Map<String, dynamic>>> groupTasksStream(
      String groupId, {
        String? status,
      }) {
    var query = _db
        .collection('groups')
        .doc(groupId)
        .collection('tasks')
        .orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots();
  }

  Future<void> createGroupTask(
      String groupId, {
        required Map<String, dynamic> data,
      }) async {
    final taskRef =
    _db.collection('groups').doc(groupId).collection('tasks').doc();

    // Add timestamps and creator info if not in map
    data['createdAt'] ??= FieldValue.serverTimestamp();
    data['createdBy'] ??= _uid;

    await taskRef.set(data);
  }
}
