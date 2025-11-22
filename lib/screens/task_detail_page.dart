import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TaskDetailPage extends StatefulWidget {
  final DocumentReference taskRef;

  const TaskDetailPage({super.key, required this.taskRef});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final _auth = FirebaseAuth.instance;
  final _controller = TextEditingController();

  late DocumentReference taskRef;
  late CollectionReference logsRef;

  String actorName = "Member"; // default, will be overwritten
  User? user;

  @override
  void initState() {
    super.initState();
    taskRef = widget.taskRef;
    logsRef = taskRef.collection("logs");

    user = _auth.currentUser;
    _loadActorName();
  }

  // ✅ Smarter name loader: users.name → users.displayName → auth.displayName → "Member"
  Future<void> _loadActorName() async {
    if (user == null) return;

    String resolvedName = '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .get();

      final data = doc.data();
      if (data != null) {
        resolvedName =
            (data['name'] ?? data['displayName'] ?? '').toString().trim();
      }

      if (resolvedName.isEmpty) {
        resolvedName = user!.displayName?.trim() ?? '';
      }
    } catch (e) {
      debugPrint('⚠️ Error loading actor name: $e');
    }

    if (resolvedName.isEmpty) {
      resolvedName = 'Member';
    }

    if (!mounted) return;
    setState(() {
      actorName = resolvedName;
    });
  }

  // Extract groupId safely
  Future<String?> _findRootId(DocumentReference ref) async {
    final segments = ref.path.split("/");
    final idx = segments.indexOf("groups");
    if (idx != -1 && idx + 1 < segments.length) {
      return segments[idx + 1];
    }
    return null;
  }

  // Load group assignment title from groups/{groupId}
  Future<String> _getGroupTitle(String groupId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      return (snap.data()?['title'] ?? 'Group Assignment').toString();
    } catch (e) {
      debugPrint('⚠️ Failed to load group title for $groupId: $e');
      return 'Group Assignment';
    }
  }

  // ----------------------------------------------------
  // COMMENT POST
  // ----------------------------------------------------
  Future<void> _postUpdate() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;

    final uid = user?.uid;
    final groupId = await _findRootId(widget.taskRef);

    await logsRef.add({
      'uid': uid,
      'name': actorName,
      'message': msg,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'comment',
      'groupId': groupId,
    });

    _controller.clear();

    // ALSO write to activity feed if part of a group
    if (groupId != null) {
      // 🔹 Load the group assignment title
      final groupTitle = await _getGroupTitle(groupId);

      await FirebaseFirestore.instance
          .collection("groups")
          .doc(groupId)
          .collection("activity")
          .add({
        'actorId': uid,
        'actorName': actorName,
        'action': "commented",
        // 🔹 Instead of raw comment text, show "in <group assignment name>"
        'taskTitle': 'in $groupTitle',
        'createdAt': FieldValue.serverTimestamp(),
        'groupId': groupId,
      });
    }
  }

  // ----------------------------------------------------
  // STATUS UPDATE
  // ----------------------------------------------------
  Future<void> _updateStatus(String value) async {
    if (user == null) return;

    // make sure we have the latest name (just in case)
    if (actorName == 'Member') {
      await _loadActorName();
    }

    final taskSnap = await taskRef.get();
    final taskData = taskSnap.data() as Map<String, dynamic>;
    final title = taskData["title"] ?? "Untitled";

    // UPDATE TASK
    await taskRef.update({
      "status": value,
      "updatedBy": user!.uid,
      "updatedAt": FieldValue.serverTimestamp(),
    });

    final groupId = await _findRootId(taskRef);

    final readable = value == "todo"
        ? "To-Do"
        : value == "doing"
        ? "In Progress"
        : "Completed";

    final msg = "Changed status to $readable";

    // Write inside task logs
    await logsRef.add({
      "uid": user!.uid,
      "name": actorName,
      "message": msg,
      "timestamp": FieldValue.serverTimestamp(),
      "type": "status",
      "groupId": groupId,
    });

    // Write to group logs
    if (groupId != null) {
      await FirebaseFirestore.instance
          .collection("groups")
          .doc(groupId)
          .collection("logs")
          .add({
        "uid": user!.uid,
        "name": actorName,
        "message": msg,
        "timestamp": FieldValue.serverTimestamp(),
        "type": "status",
        "groupId": groupId,
      });

      // 🔥 Write to ACTIVITY feed with assignment title
      final groupTitle = await _getGroupTitle(groupId);

      await FirebaseFirestore.instance
          .collection("groups")
          .doc(groupId)
          .collection("activity")
          .add({
        "actorId": user!.uid,
        "actorName": actorName,
        "action": "updated task status",
        "taskTitle": "in $groupTitle",   // ⭐ FIXED
        "createdAt": FieldValue.serverTimestamp(),
        "groupId": groupId,
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case "done":
        return Colors.green;
      case "doing":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // ----------------------------------------------------
  // UI
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Task Details")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: taskRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final title = data["title"] ?? "Untitled";
          final desc = data["description"] ?? "";
          final status = data["status"] ?? "todo";
          final assignedTo = data["assignedTo"];
          final isMine = assignedTo == user?.uid;

          return Column(
            children: [
              // HEADER
              Card(
                margin: const EdgeInsets.all(12),
                child: ListTile(
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(desc),
                  trailing: isMine
                      ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                            value: "todo", child: Text("To-Do")),
                        DropdownMenuItem(
                            value: "doing", child: Text("In Progress")),
                        DropdownMenuItem(
                            value: "done", child: Text("Completed")),
                      ],
                      onChanged: (v) {
                        if (v != null) _updateStatus(v);
                      },
                    ),
                  )
                      : const Text("Locked",
                      style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic)),
                ),
              ),

              // COMMENT BOX
              if (isMine)
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              hintText: "Write an update...",
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.deepPurple),
                          onPressed: _postUpdate)
                    ],
                  ),
                ),

              const Divider(height: 1),

              // ACTIVITY STREAM
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: logsRef
                      .orderBy("timestamp", descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(child: Text("No activity yet."));
                    }

                    return ListView.builder(
                      reverse: true,
                      itemCount: docs.length,
                      itemBuilder: (c, i) {
                        final log =
                        docs[i].data() as Map<String, dynamic>;
                        final ts = (log["timestamp"] as Timestamp?)
                            ?.toDate()
                            .toLocal();
                        final msg = log["message"] ?? "";

                        final type = log["type"];
                        final icon = type == "status"
                            ? Icons.check_circle_outline
                            : Icons.chat_bubble_outline;

                        return ListTile(
                          leading: Icon(icon,
                              color: type == "status"
                                  ? Colors.deepPurple
                                  : Colors.grey[700]),
                          title: Text(msg),
                          subtitle: Text(
                            "${log["name"] ?? "Member"} • ${ts?.toString().split(".").first ?? ""}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
