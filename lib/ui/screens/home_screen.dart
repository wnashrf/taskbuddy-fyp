import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'courses_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String? _userName;
  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _listenForUser();
  }

  void _goToAddCourseFlow(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoursesScreen(
          autoOpenLatestSemester: true,
          autoOpenAddCourseDialog: true,
        ),
      ),
    );
  }

  void _listenForUser() {
    _auth.authStateChanges().listen((user) async {
      if (user == null) return;
      final uid = user.uid;
      final userDoc = await _db.collection('users').doc(uid).get();

      final firestoreName = userDoc.data()?['name'];
      final fallback = user.displayName ?? user.email ?? 'User';

      setState(() {
        _userName = firestoreName?.toString().trim().isNotEmpty == true
            ? firestoreName
            : fallback;
      });
    });
  }

  // =======================================================
  // ===================== STREAMS ==========================
  // =======================================================

  /// Tasks assigned to me
  Stream<QuerySnapshot<Map<String, dynamic>>> _myTasksStream() {
    return _db
        .collectionGroup('tasks')
        .where('assignedTo', isEqualTo: _uid)
        .orderBy('dueDate')
        .snapshots();
  }

  /// Group IDs where I am a member
  Stream<List<String>> _myGroupIdsStream() {
    return _db
        .collection('groups')
        .where('members', arrayContains: _uid)
        .snapshots()
        .map((snap) {
      final ids = snap.docs.map((d) => d.id).toList();
      print("🎉 Valid groupIds for user = $ids");
      return ids;
    });
  }

  /// Activity from all my groups
  Stream<QuerySnapshot<Map<String, dynamic>>> _activityStream(
      List<String> groupIds) {
    print("🔥 activityStream received groupIds = $groupIds");

    if (groupIds.isEmpty) {
      print("❌ No groups → return empty stream");
      return const Stream.empty();
    }

    final limited = groupIds.take(10).toList();
    print("🔥 Querying activity where groupId IN $limited");

    return _db
        .collectionGroup('activity')
        .where('groupId', whereIn: limited)
        .orderBy('createdAt', descending: true)
        .limit(15)
        .snapshots();
  }

  // =======================================================
  // ===================== UI ==============================
  // =======================================================

  @override
  Widget build(BuildContext context) {
    final greetingName = _userName ?? '...';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F3FF),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _myTasksStream(),
          builder: (context, tasksSnap) {
            // -------- Compute Summary --------
            int todo = 0, inProg = 0, done = 0;
            double overallProgress = 0;
            final upcoming = <Map<String, dynamic>>[];

            if (tasksSnap.hasData) {
              final docs = tasksSnap.data!.docs.map((d) => d.data()).toList();

              for (final t in docs) {
                final status = (t['status'] ?? 'todo') as String;

                if (status == 'done') {
                  done++;
                } else if (status == 'doing' || status == 'in_progress') {
                  inProg++;
                } else {
                  todo++;
                }

                double p = switch (status) {
                  'done' => 1.0,
                  'doing' => 0.5,
                  'in_progress' => 0.5,
                  _ => 0.0,
                };
                overallProgress += p;
              }

              final total = docs.length;
              overallProgress =
              total == 0 ? 0 : (overallProgress / total).clamp(0.0, 1.0);

              for (final t in docs) {
                Timestamp? ts = t['dueDate'];
                final dt = ts?.toDate() ?? DateTime(2100);

                upcoming.add({
                  'title': t['title'] ?? 'Untitled task',
                  'due': DateFormat('MMM d').format(dt),
                  'progress': switch (t['status']) {
                    'done' => 1.0,
                    'doing' => 0.5,
                    _ => 0.0,
                  },
                  'dueSort': dt.millisecondsSinceEpoch,
                });
              }

              upcoming.sort((a, b) => a['dueSort'].compareTo(b['dueSort']));
            }

            // =======================================================
            // ===================== PAGE LAYOUT ======================
            // =======================================================

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.deepPurple.shade100,
                        child: const Icon(Icons.person,
                            color: Colors.deepPurple, size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Good Evening, $greetingName 👋",
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text("Here's your current progress:",
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ----- Task Summary -----
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Task Summary",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: overallProgress,
                            backgroundColor: Colors.grey.shade300,
                            color: Colors.deepPurple,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "$inProg In Progress • $todo To-Do • $done Completed",
                            style: TextStyle(
                                color: Colors.grey.shade800, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ----- Upcoming Deadlines -----
                  const Text("Upcoming Deadlines",
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: upcoming.length.clamp(0, 3),
                      itemBuilder: (context, index) {
                        final item = upcoming[index];
                        return _deadlineCard(item);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ----- Quick Actions -----
                  const Text("Quick Actions",
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildQuickAction(
                        context,
                        icon: Icons.group_add_rounded,
                        label: "New Group",
                        color: Colors.deepPurpleAccent,
                        onTap: () => _goToAddCourseFlow(context),
                      ),
                      _buildQuickAction(
                        context,
                        icon: Icons.menu_book_rounded,
                        label: "My Courses",
                        color: Colors.teal,
                        onTap: () =>
                            Navigator.pushNamed(context, '/courses'),
                      ),
                      _buildQuickAction(
                        context,
                        icon: Icons.calendar_month_rounded,
                        label: "Calendar",
                        color: Colors.orange,
                        onTap: () =>
                            Navigator.pushNamed(context, '/calendar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // =======================================================
                  // ===================== RECENT ACTIVITY =================
                  // =======================================================

                  const Text("Recent Group Activity",
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  Container(
                    height: 280, // ⬅️ fixed section height
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: StreamBuilder<List<String>>(
                      stream: _myGroupIdsStream(),
                      builder: (context, groupSnap) {
                        final ids = groupSnap.data ?? const <String>[];

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _activityStream(ids),
                          builder: (context, actSnap) {
                            if (!actSnap.hasData || actSnap.data!.docs.isEmpty) {
                              return Center(
                                child: Text(
                                  "No recent activity.",
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              );
                            }

                            final items = actSnap.data!.docs.map((d) => d.data()).toList();

                            return ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final a = items[index];
                                final who = a['actorName'] ?? 'Someone';
                                final action = a['action'] ?? 'did something';
                                final task = a['taskTitle'] ?? '';
                                final time = _timeAgo(a['createdAt']);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.deepPurple.shade100,
                                        child: const Icon(Icons.person,
                                            color: Colors.deepPurple, size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "$who $action",
                                              style: const TextStyle(
                                                  fontSize: 14, fontWeight: FontWeight.w500),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(task,
                                                style: TextStyle(
                                                    color: Colors.grey.shade700, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      Text(time,
                                          style: TextStyle(
                                              color: Colors.grey.shade600, fontSize: 12)),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // =======================================================
  // ===================== HELPERS ==========================
  // =======================================================

  Widget _deadlineCard(Map<String, dynamic> item) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item['title'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Text("Due: ${item['due']}",
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 13)),
          const Spacer(),
          LinearProgressIndicator(
            value: (item['progress'] as double).clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade300,
            color: (item['progress'] as double) >= 1.0
                ? Colors.green
                : Colors.deepPurple,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(
            "${((item['progress'] as double) * 100).toStringAsFixed(0)}% complete",
            style: TextStyle(
                color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 3,
            offset: const Offset(0, 2))
      ],
    ),
    child:
    Text(msg, style: TextStyle(color: Colors.grey.shade700)),
  );

  Widget _buildQuickAction(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800)),
            ],
          ),
        ),
      ),
    );
  }

  // Time formatting
  String _timeAgo(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
