import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int selectedWeek = 1;
  DateTime? semesterStart;
  DateTime? semesterEnd;
  String? activeSemesterId;
  bool isLoading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> allSemesters = [];

  @override
  void initState() {
    super.initState();
    _loadLatestSemester();
  }

  // 🔥 NEW: Auto-detect current week
  int getCurrentWeek() {
    if (semesterStart == null) return 1;

    final today = DateTime.now();

    if (today.isBefore(semesterStart!)) return 1;

    final diffDays = today.difference(semesterStart!).inDays;
    int week = (diffDays ~/ 7) + 1;

    if (week > 14) return 14;
    return week;
  }

  Future<void> _loadLatestSemester() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final semSnap = await FirebaseFirestore.instance
          .collection('semesters')
          .where('createdBy', isEqualTo: uid)
          .orderBy('startDate', descending: true)
          .get();

      if (semSnap.docs.isNotEmpty) {
        final latest = semSnap.docs.first;
        final data = latest.data();

        setState(() {
          allSemesters = semSnap.docs;
          activeSemesterId = latest.id;
          semesterStart = (data['startDate'] as Timestamp).toDate();
          semesterEnd = (data['endDate'] as Timestamp?)?.toDate();

          // 🔥 NEW: Auto-jump week
          selectedWeek = getCurrentWeek();
        });
      } else {
        debugPrint("⚠️ No semesters found.");
      }
    } catch (e, st) {
      debugPrint("🔥 Error loading semesters: $e\n$st");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ================================================================
  // Fetch Assignments
  // ================================================================
  Stream<List<Map<String, dynamic>>> _fetchAssignments() async* {
    if (activeSemesterId == null) {
      yield [];
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final courseSnap = await FirebaseFirestore.instance
        .collection('courses')
        .where('semesterId', isEqualTo: activeSemesterId)
        .get();

    final List<Map<String, dynamic>> allAssignments = [];

    for (final courseDoc in courseSnap.docs) {
      final courseName = courseDoc.data()['name'] ?? "No Course Name";

      // --------------------------
      // 1️⃣ INDIVIDUAL ASSIGNMENTS
      // --------------------------
      try {
        final assignSnap =
        await courseDoc.reference.collection('assignments').get();

        for (final doc in assignSnap.docs) {
          final data = doc.data();

          allAssignments.add({
            'title': data['title'] ?? 'Untitled',
            'dueDate': (data['dueDate'] ?? data['due']) != null
                ? ((data['dueDate'] ?? data['due']) as Timestamp).toDate()
                : null,
            'courseName': courseName,
            'type': 'individual',
          });
        }
      } catch (e) {
        debugPrint("⚠️ Error loading individual assignments: $e");
      }

      // --------------------------
      // 2️⃣ GROUP ASSIGNMENTS
      // --------------------------
      try {
        final groupSnap = await FirebaseFirestore.instance
            .collection('groups')
            .where('courseId', isEqualTo: courseDoc.id)
            .where('members', arrayContains: uid)
            .get();

        for (final g in groupSnap.docs) {
          final gd = g.data();
          final ts = gd['dueDate'] ?? gd['due'];

          allAssignments.add({
            'title': gd['title'] ?? 'Group Assignment',
            'dueDate': ts != null ? (ts as Timestamp).toDate() : null,
            'courseName': courseName,
            'type': 'group-assignment',
          });

          final qSnap = await g.reference.collection('questions').get();

          for (final q in qSnap.docs) {
            final taskSnap = await q.reference.collection('tasks').get();

            for (final t in taskSnap.docs) {
              final td = t.data();

              if (td['assignedTo'] != uid) continue;

              final tts = td['dueDate'] ?? td['due'];

              allAssignments.add({
                'title': td['title'] ?? "Group Task",
                'parentTitle': gd['title'] ?? "Group Assignment",
                'dueDate': tts != null ? (tts as Timestamp).toDate() : null,
                'courseName': courseName,
                'type': 'group-task',
              });
            }
          }
        }
      } catch (e) {
        debugPrint("⚠️ Error loading group data: $e");
      }
    }

    yield allAssignments;
  }

  // 🔢 Calculate week number
  int getWeekNumber(DateTime date) {
    if (semesterStart == null) return 0;
    return ((date.difference(semesterStart!).inDays) / 7).floor() + 1;
  }

  // 📅 Week range display
  String getWeekRange(int week) {
    if (semesterStart == null) return '';
    final start = semesterStart!.add(Duration(days: (week - 1) * 7));
    final end = start.add(const Duration(days: 6));
    final formatter = DateFormat('MMM d');
    return '${formatter.format(start)} – ${formatter.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (semesterStart == null) {
      return const Scaffold(
        body: Center(child: Text("No semester found. Please add one first.")),
      );
    }

    final weeks = List.generate(14, (i) => i + 1);
    final currentWeek = getCurrentWeek();
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F3FF),
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Calendar • "),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activeSemesterId,
                dropdownColor: Colors.white,
                items: allSemesters.map((doc) {
                  final data = doc.data();
                  final name = data['name'] ?? 'Unnamed Semester';
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(name, style: const TextStyle(color: Colors.yellow)),
                  );
                }).toList(),
                onChanged: (newId) {
                  if (newId == null) return;
                  final selected = allSemesters.firstWhere((d) => d.id == newId);
                  final data = selected.data();
                  setState(() {
                    activeSemesterId = newId;
                    semesterStart = (data['startDate'] as Timestamp).toDate();
                    semesterEnd = (data['endDate'] as Timestamp?)?.toDate();

                    // 🔥 NEW: Auto-select correct week
                    selectedWeek = getCurrentWeek();
                  });
                },
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),

      // ===========================================================
      // BODY START
      // ===========================================================
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _fetchAssignments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allAssignments = snapshot.data ?? [];
          // 🔥 Count assignments by week
          final Map<int, int> weekTaskCount = {};

          for (var a in allAssignments) {
            int? week = a['dueWeek'];
            if (a['dueDate'] != null) {
              week = getWeekNumber(a['dueDate']);
            }
            if (week != null && week >= 1 && week <= 14) {
              weekTaskCount[week] = (weekTaskCount[week] ?? 0) + 1;
            }
          }
          final filtered = allAssignments.where((a) {
            int? week = a['dueWeek'];
            if (a['dueDate'] != null) {
              week = getWeekNumber(a['dueDate']);
            }
            return week == selectedWeek;
          }).toList();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===========================================================
                // WEEK SELECTOR
                // ===========================================================
                SizedBox(
                  height: 58,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: weeks.length,
                    itemBuilder: (context, index) {
                      final week = weeks[index];
                      final isSelected = week == selectedWeek;

                      final isPast = week < currentWeek;
                      final isFuture = week > currentWeek;

                      Color bgColor;
                      Color textColor;

                      // Selected week
                      if (isSelected) {
                        bgColor = Colors.deepPurple;
                        textColor = Colors.white;
                      }
                      // Past weeks
                      else if (isPast) {
                        bgColor = Colors.grey.shade300;
                        textColor = Colors.grey.shade700;
                      }
                      // Future weeks
                      else {
                        bgColor = Colors.white;
                        textColor = Colors.deepPurple;
                      }

                      // 🔎 Whether this week has tasks
                      final hasTasks = (weekTaskCount[week] ?? 0) > 0;

// 🔥 Only show red dot for current or future weeks
                      final showDot = hasTasks && week >= currentWeek;

                      return GestureDetector(
                        onTap: () => setState(() => selectedWeek = week),
                        child: Stack(
                          children: [
                            // WEEK CARD
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.deepPurple),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.15),
                                    blurRadius: 3,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  "Week $week",
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),

                            // 🔴 RED DOT
                            if (showDot)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  "Week $selectedWeek (${getWeekRange(selectedWeek)})",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 10),

                // ===========================================================
                // LIST OF ASSIGNMENTS
                // ===========================================================
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                    child: Text("No assignments this week 🗓️"),
                  )
                      : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final a = filtered[i];
                      final dateText = a['dueDate'] != null
                          ? DateFormat('dd MMM yyyy')
                          .format(a['dueDate'])
                          : "Week ${a['dueWeek'] ?? selectedWeek}";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),

                        // ===========================================================
                        //  ASSIGNMENT CARD
                        // ===========================================================
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  // TYPE TAG
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: a['type'] == 'group-task'
                                          ? Colors.orange.shade100
                                          : a['type'] ==
                                          'group-assignment'
                                          ? Colors.blue.shade100
                                          : Colors.green.shade100,
                                      borderRadius:
                                      BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      a['type'] == 'group-task'
                                          ? "TASK"
                                          : a['type'] ==
                                          'group-assignment'
                                          ? "GROUP"
                                          : "INDIVIDUAL",
                                      style: TextStyle(
                                        color: a['type'] == 'group-task'
                                            ? Colors.orange.shade800
                                            : a['type'] ==
                                            'group-assignment'
                                            ? Colors.blue.shade800
                                            : Colors.green.shade800,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),

                                  // MAIN TITLE
                                  Text(
                                    a['type'] == 'group-task'
                                        ? (a['parentTitle'] ??
                                        'Group Assignment')
                                        : a['title'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),

                                  // SUBTASK TITLE
                                  if (a['type'] == 'group-task')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        "Task: ${a['title']}",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 4),

                                  // COURSE
                                  Text(
                                    "Course: ${a['courseName']}",
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 13,
                                    ),
                                  ),

                                  // DUE DATE
                                  Text(
                                    "Due: $dateText",
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
