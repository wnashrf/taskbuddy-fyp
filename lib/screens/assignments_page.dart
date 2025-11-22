import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import '../services/user_service.dart';
import '../services/firestore_service.dart';
import 'tasks_page.dart';

class AssignmentsPage extends StatefulWidget {
  final String courseId;
  final String courseName;
  final bool isOwner;
  final String groupId;
  final String globalCourseId;

  const AssignmentsPage({
    super.key,
    required this.groupId,
    required this.courseId,
    required this.courseName,
    required this.isOwner,
    required this.globalCourseId,
  });

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  final _service = FirestoreService.instance;
  final _auth = FirebaseAuth.instance;

  bool _fabExpanded = false; // track if menu is expanded

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    print("🔥 Logged-in UID: $uid");

    // Optional: check what Firestore returns for that UID
    FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .get()
        .then((snap) {
      print("📦 Found ${snap.docs.length} groups containing me as member");
      for (var doc in snap.docs) {
        print("➡ ${doc.id} | ${doc.data()}");
      }
    });
  }

  Future<void> _copyCode(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join code copied to clipboard')),
      );
    } catch (_) {}
  }

  final Map<String, String> _nameCache = {};

  Future<String> _getUserDisplayName(String uid) async {
    if (uid.isEmpty) return 'Unknown User';

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userSnap.exists) return 'Unknown User';
      final data = userSnap.data();
      final name = data?['name'] ?? data?['displayName'] ?? 'Unknown User';
      return name.toString();
    } catch (e) {
      print('⚠️ Error fetching user name for $uid: $e');
      return 'Unknown User';
    }
  }

  // ===== INDIVIDUAL ASSIGNMENTS =====
  Future<void> _createAssignmentDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? due;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New Assignment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Assignment title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (picked != null) setSt(() => due = picked);
                },
                child: Text(
                  due == null
                      ? 'Pick due date'
                      : 'Due: ${due!.toLocal().toString().split(' ').first}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      try {
        await _service.createAssignment(
          widget.courseId,
          title: titleCtrl.text.trim(),
          dueDate: due,
          addCreatorAsMember: true,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ===== GROUP CREATION =====
  Future<void> _createGroupDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? due;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Group title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (picked != null) setSt(() => due = picked);
                },
                child: Text(
                  due == null
                      ? 'Pick due date'
                      : 'Due: ${due!.toLocal().toString().split(' ').first}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      try {
        await _service.createGroup(
          courseId: widget.courseId,
          title: titleCtrl.text.trim(),
          dueDate: due,
        );
        // 🔥 Add activity log for new group assignment
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final userName = await _getUserDisplayName(uid);

// You need the groupId to write activity
// Since _service.createGroup returns nothing, we must fetch the newly created group
        final query = await FirebaseFirestore.instance
            .collection('groups')
            .where('createdBy', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

// Safety check
        if (query.docs.isNotEmpty) {
          final groupId = query.docs.first.id;

          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .add({
            'actorId': uid,
            'actorName': userName,
            'action': 'created group assignment',
            'taskTitle': titleCtrl.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'groupId': groupId,
          });

          print("🟢 Activity log created for new group assignment ($groupId)");
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ===== JOIN GROUP =====
  Future<void> _joinGroupDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Enter join code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Join')),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final code = ctrl.text.trim();
      try {
        // 🔎 Resolve joinCode → groupId
        final snap = await FirebaseFirestore.instance
            .collection('groups')
            .where('joinCode', isEqualTo: code)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          final groupId = snap.docs.first.id;
          await _service.requestJoinGroup(groupId);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request sent for approval')),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid join code')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  // ===== MAIN BUILD =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.courseName} — Assignments')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section: Individual Assignments
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Individual Assignments",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            // ---- Individual Assignments (restore this) ----
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.assignmentsStream(widget.courseId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No assignments yet.'),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data();
                    final title = d['title'] ?? 'Untitled';
                    return ListTile(
                      leading: const Icon(Icons.assignment),
                      title: Text(title),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TasksPage(
                              isGroup: false,
                              courseId: widget.courseId,
                              assignmentId: doc.id,
                              assignmentTitle: title,
                              courseName: widget.courseName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),


            // ===== GROUP ASSIGNMENTS =====
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Group Assignments",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: Rx.combineLatest2<
                  QuerySnapshot<Map<String, dynamic>>,
                  QuerySnapshot<Map<String, dynamic>>,
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                // Stream A → groups created by current user
                FirebaseFirestore.instance
                    .collection('groups')
                    .where('createdBy',
                    isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                    .snapshots(),

                // Stream B → groups where user is a member
                FirebaseFirestore.instance
                    .collection('groups')
                    .where('members',
                    arrayContains: FirebaseAuth.instance.currentUser!.uid)
                    .snapshots(),

                    (createdBySnap, memberSnap) {
                  final createdDocs = createdBySnap.docs;
                  final memberDocs = memberSnap.docs;

                  // Merge by ID (avoid duplicates)
                  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> merged = {
                    for (var doc in createdDocs) doc.id: doc,
                    for (var doc in memberDocs) doc.id: doc,
                  };

                  final list = merged.values.toList();

                  // Sort newest created first
                  list.sort((a, b) {
                    final tA = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                    final tB = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                    return tB.compareTo(tA); // newest → oldest
                  });

                  return list;
                },
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text("Error: ${snap.error}"));
                }

                final groups = snap.data ?? [];

                if (groups.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("No groups yet. Create or join one."),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final doc = groups[i];
                    final data = doc.data();

                    final title = data['title'] ?? "Untitled Group";
                    final joinCode = data['joinCode'] ?? "N/A";
                    final groupId = doc.id;

                    final isLeader =
                        data['createdBy'] == FirebaseAuth.instance.currentUser!.uid;

                    return ListTile(
                      leading: const Icon(Icons.group),
                      title: Text(title),
                      subtitle: Text("Members: ${data['membersCount'] ?? 1}"),

                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Leader only → Show join code
                          if (isLeader)
                            IconButton(
                              icon: const Icon(Icons.key),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text("Join Code"),
                                    content: Text(
                                      joinCode,
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text("Close"),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(
                                              ClipboardData(text: joinCode));
                                          Navigator.pop(context);
                                        },
                                        icon: const Icon(Icons.copy),
                                        label: const Text("Copy"),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                          // Leader only → Pending join requests
                          if (isLeader)
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('groups')
                                  .doc(groupId)
                                  .collection('joinRequests')
                                  .snapshots(),
                              builder: (context, reqSnap) {
                                final count = reqSnap.data?.docs.length ?? 0;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.group_add),
                                      onPressed: () {
                                        if (count == 0) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text("No pending requests")),
                                          );
                                          return;
                                        }

                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text("Join Requests"),
                                            content: SizedBox(
                                              width: double.maxFinite,
                                              child: ListView(
                                                shrinkWrap: true,
                                                children: reqSnap.data!.docs.map((req) {
                                                  final r = req.data();
                                                  final requester = r['uid'];

                                                  return FutureBuilder<String>(
                                                    future: _getUserDisplayName(requester),
                                                    builder: (context, nameSnap) {
                                                      final displayName = nameSnap.data ?? requester;

                                                      return ListTile(
                                                        title: Text(displayName),
                                                        subtitle: Text(requester), // optional: shows UID below
                                                        trailing: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            IconButton(
                                                              icon: const Icon(Icons.check, color: Colors.green),
                                                              onPressed: () async {
                                                                final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);

                                                                FirebaseFirestore.instance.runTransaction((transaction) async {
                                                                  final snapshot = await transaction.get(groupRef);

                                                                  if (!snapshot.exists) return;

                                                                  final currentMembers = List<String>.from(snapshot['members'] ?? []);
                                                                  final newMembersCount = (snapshot['membersCount'] ?? currentMembers.length) + 1;

                                                                  transaction.update(groupRef, {
                                                                    'members': FieldValue.arrayUnion([requester]),
                                                                    'membersCount': newMembersCount,
                                                                  });

                                                                  // Remove the join request
                                                                  final reqRef = groupRef.collection('joinRequests').doc(requester);
                                                                  transaction.delete(reqRef);
                                                                });

                                                                Navigator.pop(context); // close dialog
                                                              },
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.close, color: Colors.red),
                                                              onPressed: () {
                                                                FirebaseFirestore.instance
                                                                    .collection('groups')
                                                                    .doc(groupId)
                                                                    .collection('joinRequests')
                                                                    .doc(requester)
                                                                    .delete();
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text("Close"),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),

                                    if (count > 0)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TasksPage(
                              isGroup: true,
                              groupId: groupId,
                              courseId: widget.courseId,
                              assignmentId: '',
                              assignmentTitle: title,
                              courseName: widget.courseName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),

      // ===== Expandable FAB =====
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_fabExpanded) ...[
            FloatingActionButton.extended(
              heroTag: "createAssignment",
              onPressed: _createAssignmentDialog,
              icon: const Icon(Icons.assignment),
              label: const Text("Create Assignment"),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.extended(
              heroTag: "createGroup",
              onPressed: _createGroupDialog,
              icon: const Icon(Icons.group_add),
              label: const Text("Create Group"),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.extended(
              heroTag: "joinGroup",
              onPressed: _joinGroupDialog,
              icon: const Icon(Icons.login),
              label: const Text("Join Group"),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: "mainFab",
            onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
            child: Icon(_fabExpanded ? Icons.close : Icons.add),
          ),
        ],
      ),
    );
  }
}
