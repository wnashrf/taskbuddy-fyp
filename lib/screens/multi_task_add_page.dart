import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/ai_split_service.dart';

class MultiTaskAddPage extends StatefulWidget {
  final String questionId;
  final bool isGroup;
  final String parentId;

  const MultiTaskAddPage({
    super.key,
    required this.questionId,
    required this.isGroup,
    required this.parentId,
  });

  @override
  State<MultiTaskAddPage> createState() => _MultiTaskAddPageState();
}

class _MultiTaskAddPageState extends State<MultiTaskAddPage> {
  final _auth = FirebaseAuth.instance;
  final List<Map<String, dynamic>> _tasks = [];

  bool _aiBusy = false;
  bool _loadingExisting = true;
  bool useSharedDeadline = false;
  DateTime? sharedDeadline;

  @override
  void initState() {
    super.initState();
    _loadExistingTasks();
  }

  Future<String> _getCurrentUserDisplayName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return "Member";

    // 1. Try Firestore users/{uid}
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = snap.data();
      final dbName =
      (data?['name'] ?? data?['displayName'] ?? "").toString().trim();

      if (dbName.isNotEmpty) return dbName;
    } catch (_) {}

    // 2. Try FirebaseAuth displayName
    final authName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (authName != null && authName.isNotEmpty) return authName;

    // 3. Default
    return "Member";
  }

  Future<String> _getGroupTitle(String groupId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      return (snap.data()?['title'] ?? 'Group Assignment').toString();
    } catch (e) {
      print('⚠️ Failed to load group title for $groupId: $e');
      return 'Group Assignment';
    }
  }

  Future<DateTime?> _loadAssignmentDeadline() async {
    // Group: groups/{groupId}
    if (widget.isGroup) {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.parentId)
          .get();
      return (doc.data()?['dueDate'] ?? doc.data()?['due']) != null
          ? ((doc.data()?['dueDate'] ?? doc.data()?['due']) as Timestamp).toDate()
          : null;
    }

    // Individual: courses/{courseId}/assignments/{assignmentId}
    final doc = await FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.parentId)              // <- courseId
        .collection('assignments')
        .doc(widget.questionId)            // <- assignmentId in this screen
        .get();

    return (doc.data()?['dueDate'] ?? doc.data()?['due']) != null
        ? ((doc.data()?['dueDate'] ?? doc.data()?['due']) as Timestamp).toDate()
        : null;
  }

  // 🟣 Load tasks already uploaded before (in "editing" stage)
  Future<void> _loadExistingTasks() async {
    try {
      final base = widget.isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.parentId)
          .collection('questions')
          .doc(widget.questionId)
          .collection('tasks')
          : FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.parentId)
          .collection('assignments')
          .doc(widget.questionId)
          .collection('tasks');

      final snapshot = await base.get();

      final existing = snapshot.docs.map((d) {
        final data = d.data();
        return {
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'deadline': (data['dueDate'] ?? data['due']) is Timestamp
              ? ((data['dueDate'] ?? data['due']) as Timestamp).toDate()
              : null,
        };
      }).toList();

      setState(() {
        _tasks
          ..clear()
          ..addAll(existing.isEmpty
              ? [{'title': '', 'description': '', 'deadline': null}]
              : existing);
        _loadingExisting = false;
      });
    } catch (e) {
      setState(() => _loadingExisting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load existing tasks: $e')),
      );
    }
  }

  void _addNewTask() {
    setState(() =>
        _tasks.add({'title': '', 'description': '', 'deadline': null}));
  }

  void _removeTask(int index) {
    setState(() => _tasks.removeAt(index));
  }

  Future<void> _uploadAllTasks() async {
    final validTasks =
    _tasks.where((t) => t['title'].toString().trim().isNotEmpty).toList();
    if (validTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one task title.')));
      return;
    }

    // 🔒 Validate task deadlines against assignment deadline
    final assignmentDue = await _loadAssignmentDeadline();

    if (assignmentDue != null) {
      // Shared deadline mode
      if (useSharedDeadline && sharedDeadline != null) {
        if (sharedDeadline!.isAfter(assignmentDue)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Task deadline (${sharedDeadline!.toLocal().toString().split(' ').first}) '
                    'cannot be after the assignment deadline (${assignmentDue.toLocal().toString().split(' ').first}).',
              ),
            ),
          );
          return;
        }
      } else {
        // Per-task deadlines
        final offending = <String>[];
        for (final t in validTasks) {
          final DateTime? d = t['deadline'] is DateTime ? t['deadline'] : null;
          if (d != null && d.isAfter(assignmentDue)) {
            offending.add((t['title'] ?? '').toString().trim());
          }
        }
        if (offending.isNotEmpty) {
          final first = offending.first.isEmpty ? 'One of your tasks' : offending.first;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$first has a deadline after the assignment deadline '
                    '(${assignmentDue.toLocal().toString().split(' ').first}). '
                    'Please adjust it.',
              ),
            ),
          );
          return;
        }
      }
    }

    final uid = _auth.currentUser?.uid;
    final base = widget.isGroup
        ? FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.parentId)
        .collection('questions')
        .doc(widget.questionId)
        .collection('tasks')
        : FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.parentId)
        .collection('assignments')
        .doc(widget.questionId)
        .collection('tasks');

// 🔹 Load group title once if this is a group assignment
    String groupTitle = 'Group Assignment';
    if (widget.isGroup) {
      groupTitle = await _getGroupTitle(widget.parentId);
    }

    final existing = await base.get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }

    for (final t in validTasks) {
      await base.add({
        'title': t['title'],
        'description': t['description'],
        'dueDate': (useSharedDeadline && sharedDeadline != null)
            ? Timestamp.fromDate(sharedDeadline!)
            : (t['deadline'] != null
            ? Timestamp.fromDate(t['deadline'])
            : null),
        'status': 'todo',
        'assignedTo': null,
        'createdBy': uid,
        'createdAt': Timestamp.now(),
      });
      // 🔥 ADD ACTIVITY LOG (Only for Group Assignments)
      // 🔥 ADD ACTIVITY LOG (Only for Group Assignments)
      if (widget.isGroup && uid != null) {
        final userName = await _getCurrentUserDisplayName();

        final groupRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.parentId);

        await groupRef.collection('activity').add({
          'actorId': uid,
          'actorName': userName,
          'action': 'added task',
          // ⬇️ Use "in <groupTitle>" instead of raw task title
          'taskTitle': 'in $groupTitle',
          'createdAt': FieldValue.serverTimestamp(),
          'groupId': widget.parentId,
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All tasks saved and uploaded successfully')));
    Navigator.pop(context);
  }

  Future<({String title, String desc, int memberCount})> _loadInputsForAI() async {
    final qRef = widget.isGroup
        ? FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.parentId)
        .collection('questions')
        .doc(widget.questionId)
        : FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.parentId)
        .collection('assignments')
        .doc(widget.questionId);

    final qSnap = await qRef.get();
    final data = qSnap.data() ?? {};
    final title = (data['title'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();

    int memberCount = 1;
    if (widget.isGroup) {
      final gSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.parentId)
          .get();
      final g = gSnap.data() ?? {};
      final List members = List.from(g['members'] ?? []);
      memberCount = members.isEmpty ? 1 : members.length;
    }

    return (title: title, desc: desc, memberCount: memberCount);
  }

  Future<void> _onAISplitPressed() async {
    try {
      setState(() => _aiBusy = true);

      // ===== Load question and default member count =====
      final inputs = await _loadInputsForAI();
      if (inputs.title.isEmpty && inputs.desc.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please upload the question first.')),
        );
        return;
      }

      // ===== Hybrid prompt: confirm or override task count =====
      int? desiredCount = await showDialog<int>(
        context: context,
        barrierDismissible: true, // allow tap outside to close
        builder: (context) {
          final controller =
          TextEditingController(text: inputs.memberCount.toString());
          return WillPopScope(
            // handle Android back button
            onWillPop: () async {
              Navigator.pop(context, null); // return null on back
              return false;
            },
            child: AlertDialog(
              title: const Text('Confirm Task Count'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This group currently has ${inputs.memberCount} member(s).\n\n'
                        'How many tasks should the AI generate?',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Number of tasks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, inputs.memberCount), // Use default
                  child: const Text('Use Default'),
                ),
                TextButton(
                  onPressed: () {
                    final n = int.tryParse(controller.text.trim());
                    Navigator.pop(context, (n != null && n > 0) ? n : null);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        },
      );

      // ===== If user cancelled, stop process =====
      if (desiredCount == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI Split cancelled.')),
          );
        }
        return;
      }

      // ===== Call Gemini to generate tasks =====
      final suggestions = await AISplitService.instance.splitIntoTasks(
        questionTitle: inputs.title,
        questionDescription: inputs.desc,
        memberCount: desiredCount,
      );

      // ===== Update the UI =====
      setState(() {
        _tasks
          ..clear()
          ..addAll(suggestions.map((t) => {
            'title': t['title'] ?? '',
            'description': t['description'] ?? '',
            'deadline': null,
          }));
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'AI created ${suggestions.length} task(s). Review & upload.')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('AI split failed: $e')));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }



  Future<void> _pickSharedDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: sharedDeadline ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() => sharedDeadline = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Multiple Tasks'),
        actions: [
          TextButton.icon(
            onPressed: _aiBusy ? null : _onAISplitPressed,
            icon: _aiBusy
                ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: const Text('AI Split'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Shared Deadline Section =====
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deadline Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Switch(
                      value: useSharedDeadline,
                      onChanged: (v) async {
                        setState(() => useSharedDeadline = v);
                        if (v && sharedDeadline == null) {
                          await _pickSharedDeadline();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Apply same deadline to all tasks',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (useSharedDeadline)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: TextButton.icon(
                      onPressed: _pickSharedDeadline,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(sharedDeadline == null
                          ? 'Pick shared deadline'
                          : 'Deadline: ${sharedDeadline!.toLocal().toString().split(' ').first}'),
                    ),
                  ),
              ],
            ),
          ),

          // ===== Task Tiles =====
          ...List.generate(_tasks.length, (i) {
            final task = _tasks[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 3,
              child: ExpansionTile(
                title: TextField(
                  decoration: InputDecoration(
                    labelText: 'Task ${i + 1} Title',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  controller: TextEditingController(text: task['title']),
                  onChanged: (v) => task['title'] = v,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                      controller:
                      TextEditingController(text: task['description']),
                      onChanged: (v) => task['description'] = v,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!useSharedDeadline)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: now,
                              firstDate: now,
                              lastDate: DateTime(now.year + 3),
                            );
                            if (picked != null) {
                              setState(() => task['deadline'] = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(task['deadline'] == null
                              ? 'Set Deadline'
                              : 'Deadline: ${task['deadline'].toString().split(' ').first}'),
                        ),
                        IconButton(
                          onPressed: () => _removeTask(i),
                          icon: const Icon(Icons.delete,
                              color: Colors.redAccent),
                        ),
                      ],
                    ),
                  if (useSharedDeadline)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => _removeTask(i),
                        icon: const Icon(Icons.delete,
                            color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),

          // ===== Add Task Button =====
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _addNewTask,
            icon: const Icon(Icons.add),
            label: const Text('Add Another Task'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: Colors.deepPurple.shade200, width: 1.5),
              foregroundColor: Colors.deepPurple,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),

          // ===== Upload Button =====
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _uploadAllTasks,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload All Tasks'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
