import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../services/firestore_service.dart';
import 'assignments_page.dart'; // we'll create this next

class CoursesScreen extends StatelessWidget {
  final bool autoOpenLatestSemester;
  final bool autoOpenAddCourseDialog;

  const CoursesScreen({
    super.key,
    this.autoOpenLatestSemester = false,
    this.autoOpenAddCourseDialog = false,
  });

  Stream<int> groupCountStream(String globalCourseId, String myUid) {
    final createdByMe = FirebaseFirestore.instance
        .collection('groups')
        .where('globalCourseId', isEqualTo: globalCourseId)
        .where('createdBy', isEqualTo: myUid)
        .snapshots();

    final memberOf = FirebaseFirestore.instance
        .collection('groups')
        .where('globalCourseId', isEqualTo: globalCourseId)
        .where('members', arrayContains: myUid)
        .snapshots();

    return Rx.combineLatest2<
        QuerySnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>,
        int>(
      createdByMe,
      memberOf,
          (a, b) {
        // ✅ Merge manually by document ID
        final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (var doc in a.docs) {
          allDocs[doc.id] = doc;
        }
        for (var doc in b.docs) {
          allDocs[doc.id] = doc;
        }
        return allDocs.length;
      },
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('semesters')
            .where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .orderBy('startDate', descending: true)
            .snapshots()
            .handleError((e) {
          debugPrint('Semester stream error: $e');
        }),
        builder: (context, semesterSnap) {
          if (semesterSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final semesterDocs = semesterSnap.data?.docs ?? [];

          if (autoOpenLatestSemester && semesterDocs.isNotEmpty) {
            // Delay to allow UI to build first
            Future.microtask(() async {
              final latestSemester = semesterDocs.first;

              // Trigger "Add Course" dialog
              await _showAddCourseDialog(context, latestSemester);
            });
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Semester'),
                onPressed: () async {
                  final nameCtrl = TextEditingController();
                  String namingMode = 'manual';
                  DateTime? start;
                  DateTime? end;

                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Add Semester'),
                      content: StatefulBuilder(
                        builder: (ctx, setState) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Naming Style:'),
                            DropdownButton<String>(
                              value: namingMode,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'manual',
                                  child: Text('Manual (e.g., Semester 5)'),
                                ),
                                DropdownMenuItem(
                                  value: 'monthYear',
                                  child: Text('Month + Year (e.g., Jan 2025)'),
                                ),
                              ],
                              onChanged: (v) => setState(() => namingMode = v!),
                            ),
                            const SizedBox(height: 8),

                            if (namingMode == 'manual')
                              TextField(
                                controller: nameCtrl,
                                decoration:
                                const InputDecoration(labelText: 'Semester name'),
                              ),

                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) setState(() => start = picked);
                              },
                              child: Text(start == null
                                  ? 'Pick start date'
                                  : 'Start: ${DateFormat('dd MMM yyyy').format(start!)}'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: start ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) setState(() => end = picked);
                              },
                              child: Text(end == null
                                  ? 'Pick end date'
                                  : 'End: ${DateFormat('dd MMM yyyy').format(end!)}'),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (start == null) return;

                            final semesterName = namingMode == 'monthYear'
                                ? DateFormat('MMM yyyy').format(start!)
                                : nameCtrl.text.trim().isEmpty
                                ? 'Unnamed Semester'
                                : nameCtrl.text.trim();

                            await FirebaseFirestore.instance.collection('semesters').add({
                              'name': semesterName,
                              'startDate': start,
                              'endDate': end,
                              'createdBy': FirebaseAuth.instance.currentUser!.uid,
                              'namingMode': namingMode,
                            });

                            if (context.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // --- Semester list ---
              if (semesterDocs.isEmpty)
                const Center(child: Text('No semesters yet.')),
              for (int i = 0; i < semesterDocs.length; i++)
                _buildSemesterTile(
                  context,
                  semesterDocs[i],
                  i == 0, // Auto-expand ONLY the latest semester (index 0)
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddCourseDialog(BuildContext context, DocumentSnapshot semesterDoc) async {
    final courseTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Course'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter course name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (courseTitle != null && courseTitle.isNotEmpty) {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      final globalId = const Uuid().v4();
      final semesterId = semesterDoc.id;

      final courseRef = await FirebaseFirestore.instance
          .collection('courses')
          .add({
        'name': courseTitle,
        'ownerId': myUid,
        'globalCourseId': globalId,
        'semesterId': semesterId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await semesterDoc.reference.update({
        'courses': FieldValue.arrayUnion([
          {
            'id': courseRef.id,
            'name': courseTitle,
            'ownerId': myUid,
            'globalCourseId': globalId,
          }
        ]),
      });
    }
  }

  Widget _buildSemesterTile(BuildContext context, DocumentSnapshot semesterDoc, bool expand,) {
    final semester = semesterDoc.data() as Map<String, dynamic>? ?? {};
    final semesterId = semesterDoc.id;
    final courseStream = FirebaseFirestore.instance
        .collection('courses')
        .where('semesterId', isEqualTo: semesterId)
        .snapshots();

    return ExpansionTile(
      initiallyExpanded: expand,
      title: Text(
        semester['name'] ?? 'Unnamed Semester',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: (semester['startDate'] != null && semester['endDate'] != null)
          ? Text(
        "${DateFormat('dd MMM yyyy').format(semester['startDate'].toDate())} – ${DateFormat('dd MMM yyyy').format(semester['endDate'].toDate())}",
        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
      )
          : null,
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: courseStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Loading courses...'),
              );
            }

            final courses = snapshot.data!.docs;
            if (courses.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No courses yet'),
              );
            }

            return Column(
              children: courses.map((courseDoc) {
                final c = courseDoc.data() as Map<String, dynamic>;
                final myUid = FirebaseAuth.instance.currentUser!.uid;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      (c['name'] ?? 'U')[0].toString().toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    ),
                  ),
                  title: Text(c['name'] ?? 'Untitled',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: StreamBuilder<List<int>>(
                    stream: Rx.combineLatest2<int, int, List<int>>(
                      FirebaseFirestore.instance
                          .collection('courses')
                          .doc(courseDoc.id)
                          .collection('assignments')
                          .snapshots()
                          .map((s) => s.docs.length),
                      groupCountStream(c['globalCourseId'], myUid),
                          (a, b) => [a, b],
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Text('Loading...',
                            style: TextStyle(color: Colors.grey, fontSize: 13));
                      }
                      final individualCount = snapshot.data![0];
                      final groupCount = snapshot.data![1];
                      if (individualCount == 0 && groupCount == 0) {
                        return const Text('No assignments yet',
                            style: TextStyle(color: Colors.grey, fontSize: 13));
                      }
                      return Text(
                        '${individualCount > 0 ? '$individualCount individual' : ''}'
                            '${(individualCount > 0 && groupCount > 0) ? ' • ' : ''}'
                            '${groupCount > 0 ? '$groupCount group' : ''}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignmentsPage(
                          courseId: courseDoc.id,
                          courseName: c['name'],
                          groupId: '',
                          isOwner: c['ownerId'] == myUid,
                          globalCourseId: c['globalCourseId'],
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.deepPurple),
            label: const Text(
              "Add Course",
              style: TextStyle(color: Colors.deepPurple),
            ),
            onPressed: () async {
              final courseTitle = await showDialog<String>(
                context: context,
                builder: (context) {
                  final controller = TextEditingController();
                  return AlertDialog(
                    title: const Text('Add Course'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Enter course name',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  );
                },
              );

              if (courseTitle != null && courseTitle.isNotEmpty) {
                final myUid = FirebaseAuth.instance.currentUser!.uid;
                final globalId = const Uuid().v4();
                final semesterId = semesterDoc.id;

                final courseRef = await FirebaseFirestore.instance
                    .collection('courses')
                    .add({
                  'name': courseTitle,
                  'ownerId': myUid,
                  'globalCourseId': globalId,
                  'semesterId': semesterId,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                await semesterDoc.reference.update({
                  'courses': FieldValue.arrayUnion([
                    {
                      'id': courseRef.id,
                      'name': courseTitle,
                      'ownerId': myUid,
                      'globalCourseId': globalId,
                    }
                  ]),
                });
              }
            },
          ),
        ),
      ],
    );
  }
}