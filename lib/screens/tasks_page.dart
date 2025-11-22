import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter/gestures.dart';
import 'multi_task_add_page.dart';
import 'task_detail_page.dart';
import 'group_activity_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

const String _geminiApiKey = 'AIzaSyA6TAw8Hr3wO2uvl_8VtpwSSXd5EL-BJ2g';

class TasksPage extends StatefulWidget {
  final String courseId;
  final String assignmentId;
  final String assignmentTitle;
  final String courseName;

  final bool isGroup;
  final String? groupId;

  const TasksPage({
    super.key,
    required this.courseId,
    required this.assignmentId,
    required this.assignmentTitle,
    required this.courseName,
    this.isGroup = false,
    this.groupId,
  });

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _auth = FirebaseAuth.instance;
  String? _currentQuestionId;
  String _selectedTab = 'all';
  bool _ranOverdueScan = false;
  final PageStorageBucket _bucket = PageStorageBucket();
  final ScrollController _scrollController = ScrollController();
  bool _locked = false;

  // Cache the question document to avoid repeated fetches
  late Future<DocumentSnapshot<Map<String, dynamic>>>? _questionFuture;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _tasksStream;

  @override
  void initState() {
    super.initState();

    // ✅ Only ensure question once when page loads
    if (!widget.isGroup) {
      _ensureIndividualQuestionExists();
    }

    if (widget.isGroup) {
      _questionFuture = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get()
          .then((snap) => snap.docs.isNotEmpty
          ? snap.docs.first.reference.get()
          : Future.value(null));
    } else {
      _questionFuture = FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.courseId)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get()
          .then((snap) => snap.docs.isNotEmpty
          ? snap.docs.first.reference.get()
          : Future.value(null));
    }
  }

  Future<void> _autoFlagOverdueTasks(CollectionReference<Map<String, dynamic>> tasks) async {
    final now = Timestamp.fromDate(DateTime.now());
    final snap = await tasks.where('dueDate', isLessThan: now).get();

    for (final doc in snap.docs) {
      final d = doc.data();
      final status = (d['status'] ?? 'todo') as String;
      final flagged = (d['flagged'] == true);

      // Only flag if not completed and not already flagged
      if (status != 'done' && !flagged) {
        try {
          await doc.reference.update({
            'flagged': true,                // <-- we DO NOT change status
            'flaggedAt': FieldValue.serverTimestamp(),
          });

          // (Optional) also write a task log entry so it appears in feeds
          await doc.reference.collection('logs').add({
            'type': 'status',
            'uid': FirebaseAuth.instance.currentUser?.uid,
            'name': FirebaseAuth.instance.currentUser?.displayName ?? 'Member',
            'message': 'Task became overdue.',
            'timestamp': FieldValue.serverTimestamp(),
            // keep groupId extraction consistent with your existing code
            'groupId': () {
              final seg = doc.reference.path.split('/');
              final gi = seg.indexOf('groups');
              return (gi != -1 && gi + 1 < seg.length) ? seg[gi + 1] : null;
            }(),
          });
        } catch (_) {
          // avoid throwing—best effort
        }
      }
    }
  }

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
      print('⚠️ Error fetching display name for $uid: $e');
      return 'Unknown User';
    }
  }

  Future<void> _deleteAttachment({
    required Map<String, dynamic> fileData,
    required DocumentReference<Map<String, dynamic>> questionRef,
  }) async {
    try {
      // 1️⃣ Delete from Firebase Storage if URL/path available
      if (fileData['url'] != null) {
        final storage = FirebaseStorage.instance;
        final ref = storage.refFromURL(fileData['url']);
        await ref.delete();
      }

      // 2️⃣ Remove from Firestore array
      await questionRef.update({
        'attachments': FieldValue.arrayRemove([fileData]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment deleted successfully.')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting attachment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete file.')),
        );
      }
    }
  }

  String _sanitizeFilename(String raw) {
    final noBad = raw.replaceAll(RegExp(r'[^\w\.\-]+'), '_');
    return noBad.isEmpty ? 'file' : noBad;
  }

  Future<List<PlatformFile>> _pickQuestionFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true, // we only need bytes to upload
    );
    return res?.files ?? <PlatformFile>[];
  }

  Future<List<Map<String, dynamic>>> _uploadQuestionFiles({
    required List<PlatformFile> files,
    required String containerPath, // full Firestore *path* of the question doc
  }) async {
    if (files.isEmpty) return [];

    final uid = _auth.currentUser?.uid ?? 'anon';
    final storage = FirebaseStorage.instance;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Put under: questions_uploads/<hash of containerPath>/...
    final pathHash = containerPath.hashCode & 0x7fffffff;
    final baseRef = storage.ref().child('question_uploads/$pathHash');

    final List<Map<String, dynamic>> out = [];
    for (final f in files) {
      final name = _sanitizeFilename(f.name);
      final ext = name.split('.').length > 1 ? name.split('.').last.toLowerCase() : '';
      final ref = baseRef.child('${now}_$uid\_$name');

      // We prefer bytes (no storage permission required)
      if (f.bytes == null) continue; // safety: user canceled
      final metadata = SettableMetadata(
        contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
        customMetadata: {'owner': uid, 'source': 'taskbuddy'},
      );

      await ref.putData(f.bytes!, metadata);
      final url = await ref.getDownloadURL();

      out.add({
        'name': name,
        'url': url,
        'type': ext == 'pdf' ? 'pdf' : 'image',
        'size': f.size,
        'uploadedAt': Timestamp.now(),
        'uploadedBy': uid,
      });
    }
    return out;
  }

  // ─────────────────────────── Show Group Members ───────────────────────────
  Future<void> _showGroupMembersDialog() async {
    if (!widget.isGroup || widget.groupId == null) return;
    final groupRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId!);

    final groupDoc = await groupRef.get();
    final groupData = groupDoc.data();
    if (groupData == null) return;

    final members = List<String>.from(groupData['members'] ?? []);
    final leader = groupData['createdBy'];
    final myUid = _auth.currentUser?.uid;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Group Members'),
        content: members.isEmpty
            ? const Text('No members found.')
            : SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (context, index) {
              final uid = members[index];
              return FutureBuilder<String>(
                future: _getUserDisplayName(uid),
                builder: (context, snap) {
                  final name = snap.data ?? 'Loading...';

                  String label = name;
                  if (uid == leader && uid == myUid) {
                    label += ' (Leader, Me)';
                  } else if (uid == leader) {
                    label += ' (Leader)';
                  } else if (uid == myUid) {
                    label += ' (Me)';
                  }

                  return ListTile(
                    leading: Icon(
                      uid == leader
                          ? Icons.star_rounded
                          : Icons.person_outline,
                      color: uid == leader
                          ? Colors.amber
                          : Colors.grey[700],
                    ),
                    title: Text(label),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _extractQuestionFromFile(PlatformFile file) async {
    try {
      if (_geminiApiKey.isEmpty) return null;
      if (file.bytes == null) return null;

      final ext = (file.extension ?? '').toLowerCase();

      // ---------------------------------------------------------
      // OPTION 2: PDF ➜ IMAGE(S) before sending to Gemini Vision
      // ---------------------------------------------------------
      List<Uint8List> images = [];

      if (ext == 'pdf') {
        final pdfDocument = await PdfDocument.openData(file.bytes!);
        final pageCount = pdfDocument.pagesCount;

        // convert ALL pages or only first?
        // -> to keep it fast, convert only first page for now
        final page = await pdfDocument.getPage(1);

        final pdfPageImage = await page.render(
          width: page.width,
          height: page.height,
          format: PdfPageImageFormat.png,
        );

        images.add(pdfPageImage!.bytes);
        await page.close();
        await pdfDocument.close();
      }
      else {
        // if it's already an image
        images.add(file.bytes!);
      }

      if (images.isEmpty) return null;

      final model = GenerativeModel(
        model: "gemini-2.5-flash",
        apiKey: _geminiApiKey,
      );

      final prompt = '''
You are extracting a question from a screenshot or PDF.

Return ONLY valid JSON. No explanation, no backticks.

If the text does not contain a clear title or description, return empty strings.

Format:
{
"title": "<short title>",
"description": "<full description>"
}
''';

      // Only send first page IMAGE to Gemini (best performance)
      final imgBytes = images.first;

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart("image/png", imgBytes),
        ])
      ]);

      final text = response.text;
      if (text == null || text.trim().isEmpty) return null;

      String raw = text.trim();

      // remove any code fences
      raw = raw.replaceAll(RegExp(r'```.*?```', dotAll: true), '');
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();

      // remove leading/trailing junk
      raw = raw.replaceAll(RegExp(r'^[^{]*'), '');
      raw = raw.replaceAll(RegExp(r'[^}]*$'), '');

      final decoded = json.decode(raw);

      return {
        "title": decoded["title"] ?? "",
        "description": decoded["description"] ?? "",
      };
    } catch (e) {
      debugPrint("Option 2 extraction failed: $e");
      return null;
    }
  }

  // ─────────────────────────── Upload/Reupload Question ───────────────────────────
  Future<void> _uploadQuestionDialog() async {
    final isEditing = _currentQuestionId != null;

    // Load existing question (only when editing)
    String oldTitle = '';
    String oldDesc = '';
    List<Map<String, dynamic>> oldAttachments = [];

    if (isEditing) {
      final snap = await (widget.isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)
          .collection('questions')
          .doc(_currentQuestionId!)
          .get()
          : FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.courseId)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('questions')
          .doc(_currentQuestionId!)
          .get());

      final d = snap.data();
      if (d != null) {
        oldTitle = d['title'] ?? '';
        oldDesc = d['description'] ?? '';
        oldAttachments = List<Map<String, dynamic>>.from(d['attachments'] ?? []);
      }
    }

    final titleCtrl = TextEditingController(text: oldTitle);
    final descCtrl = TextEditingController(text: oldDesc);
    List<PlatformFile> pickedFiles = [];
    bool isExtracting = false;
    String? extractError;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing ? "Edit Question" : "Upload Question",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isEditing
                    ? "Update details or replace files"
                    : "Fill details and attach task files",
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              )
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Title
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: "Question Title",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description field
                  TextField(
                    controller: descCtrl,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: "Question Description",
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // New Attachments Section
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "New Attachments",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...pickedFiles.map((file) => Chip(
                        label: Text(file.name),
                        backgroundColor: Colors.deepPurple.shade50,
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () =>
                            setSB(() => pickedFiles.remove(file)),
                      )),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final f = await _pickQuestionFiles();
                          if (f.isNotEmpty) setSB(() => pickedFiles.addAll(f));

                          // 🔮 Run AI extraction only if fields are empty
                          if (f.isNotEmpty) {
                            setSB(() {
                              isExtracting = true;
                              extractError = null;
                            });

                            try {
                              final primary = f.first; // use the first file selected
                              final extracted = await _extractQuestionFromFile(primary);

                              if (extracted != null) {
                                setSB(() {
                                  titleCtrl.text = extracted['title'] ?? titleCtrl.text;
                                  descCtrl.text = extracted['description'] ?? descCtrl.text;
                                });
                              } else {
                                setSB(() {
                                  extractError = 'Could not extract question details from this file.';
                                });
                              }
                            } catch (e) {
                              setSB(() {
                                extractError = 'Something went wrong during AI extraction.';
                              });
                            } finally {
                              setSB(() {
                                isExtracting = false;
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.attach_file),
                        label: const Text("Attach Files"),
                      )
                    ],
                  ),

                  if (isExtracting) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Analyzing attachment with AI...',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                  if (extractError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      extractError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],

                  if (isEditing && oldAttachments.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Existing Attachments",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...oldAttachments.map(
                          (a) => Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              a['type'] == 'pdf'
                                  ? Icons.picture_as_pdf
                                  : Icons.image,
                              color: Colors.deepPurple,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(a['name'] ?? 'Attachment')),
                          ],
                        ),
                      ),
                    )
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                isEditing ? "Save Changes" : "Upload",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final title = titleCtrl.text.trim();
    final desc = descCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title before uploading.')),
      );
      return;
    }

    // Firestore reference
    final col = widget.isGroup
        ? FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId!)
        .collection('questions')
        : FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.courseId)
        .collection('assignments')
        .doc(widget.assignmentId)
        .collection('questions');

    DocumentReference qRef;

    if (isEditing) {
      qRef = col.doc(_currentQuestionId!);
      await qRef.update({
        'title': title,
        'description': desc,
        'updatedAt': Timestamp.now(),
      });
    } else {
      qRef = await col.add({
        'title': title,
        'description': desc,
        'createdAt': Timestamp.now(),
        'createdBy': _auth.currentUser?.uid,
        'locked': false,
      });

      // FIX — ensure UI + logic both know the correct question ID
      setState(() {
        _currentQuestionId = qRef.id;
      });
    }

    // Upload new attachments
    if (pickedFiles.isNotEmpty) {
      final uploaded = await _uploadQuestionFiles(
        files: pickedFiles,
        containerPath: qRef.path,
      );

      if (uploaded.isNotEmpty) {
        await qRef.update({
          'attachments': FieldValue.arrayUnion(uploaded),
        });
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isEditing ? "Updated successfully" : "Uploaded")),
    );

    setState(() {});
  }

  // ─────────────────────────── Add Task Dialog ───────────────────────────
  void _openMultiTaskPage() {
    if (_currentQuestionId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload a question first.')));
      return;
    }

    if (widget.isGroup && widget.groupId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiTaskAddPage(
          questionId: _currentQuestionId!,
          isGroup: widget.isGroup,
          parentId: widget.isGroup ? widget.groupId! : widget.courseId,
        ),
      ),
    );
  }

  // ─────────────────────────── Lock / Unlock ───────────────────────────
  Future<void> _setLocked(bool lock) async {
    if (widget.isGroup && widget.groupId == null) return;
    if (_currentQuestionId == null) return;
    final ref = widget.isGroup
        ? FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId!)
        .collection('questions')
        .doc(_currentQuestionId)
        : FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.courseId)
        .collection('assignments')
        .doc(widget.assignmentId)
        .collection('questions')
        .doc(_currentQuestionId);
    await ref.update({'locked': lock});
  }

  void _initTaskStream(String questionId) {
    _tasksStream = widget.isGroup
        ? FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId!)
        .collection('questions')
        .doc(questionId)
        .collection('tasks')
        .snapshots()
        : FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.courseId)
        .collection('assignments')
        .doc(widget.assignmentId)
        .collection('questions')
        .doc(questionId)
        .collection('tasks')
        .snapshots();
  }

  // ─────────────────────────── Calculate Overall Progress ───────────────────────────
  double _calculateOverallProgress(List<QueryDocumentSnapshot> tasks) {
    if (tasks.isEmpty) return 0.0;

    double total = 0;
    for (var t in tasks) {
      final status = t['status'] ?? 'todo';
      if (status == 'done') total += 1;
      else if (status == 'doing') total += 0.5;
    }
    return total / tasks.length;
  }

  // ─────────────────────────── Build Tabs Section ───────────────────────────
  Widget _buildTabs(CollectionReference<Map<String, dynamic>> tasksRef,
      void Function(void Function()) setInnerState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─────── Filter bar ───────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _tab('all', 'All Tasks', Icons.list_alt, setInnerState),
              _tab('todo', 'To-Do', Icons.task_alt, setInnerState),
              _tab('doing', 'In Progress', Icons.timelapse, setInnerState),
              _tab('done', 'Completed', Icons.check_circle, setInnerState),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ─────── Task list (live updates) ───────
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: tasksRef.snapshots(),
          builder: (context, taskSnap) {
            if (taskSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!taskSnap.hasData || taskSnap.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tasks available yet.'),
              );
            }

            final taskDocs = taskSnap.data!.docs;

            // Filter by selected tab (all / todo / doing / done)
            final filtered = _selectedTab == 'all'
                ? taskDocs
                : taskDocs.where((d) => d['status'] == _selectedTab).toList();

            if (filtered.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tasks in this category.'),
              );
            }

            return _TaskListView(
              storageKey: 'tab-$_selectedTab',
              tasks: filtered.cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
            );
          },
        ),
      ],
    );
  }

  Widget _tab(
      String key,
      String label,
      IconData icon,
      void Function(void Function()) setInnerState,
      ) {
    final selected = _selectedTab == key;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          if (_selectedTab != key) {
            setInnerState(() => _selectedTab = key);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6), // <-- less curve here
            border: Border.all(
              color: selected ? Colors.deepPurple : Colors.grey.shade400,
              width: 1.2,
            ),
            boxShadow: selected
                ? [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── Build Poll ───────────────────────────
  Widget _poll(CollectionReference<Map<String, dynamic>> tasks, bool locked) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tasks.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No tasks yet.');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Task Poll',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...docs.map((d) {
              final t = d.data();
              final claimed = t['assignedTo'] != null;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    claimed ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: claimed ? Colors.green : Colors.grey,
                  ),
                  title: Text(t['title'] ?? ''),
                  subtitle: Text(t['description'] ?? ''),
                  trailing: locked
                      ? claimed
                      ? Text(
                    'Taken by ${t['assignedName'] ?? 'Member'}',
                    style: const TextStyle(color: Colors.grey),
                  )
                      : ElevatedButton(
                    onPressed: () async {
                      final uid = _auth.currentUser?.uid;
                      final name = _auth.currentUser?.displayName ?? 'Member';
                      await d.reference.update({
                        'assignedTo': uid,
                        'assignedName': name,
                        'status': 'todo', // Initialize as To-Do
                      });
                    },
                    child: const Text('Claim'),
                  )
                      : const Text('Editing...'),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _ensureIndividualQuestionExists() async {
    if (widget.isGroup) return; // only for individual
    final col = FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.courseId)
        .collection('assignments')
        .doc(widget.assignmentId)
        .collection('questions');

    final snap = await col.limit(1).get();
    if (snap.docs.isEmpty) {
      final newDoc = await col.add({
        'title': 'Individual Task',
        'description': 'Your personal assignment tasks.',
        'createdBy': _auth.currentUser?.uid,
        'createdAt': Timestamp.now(),
        'locked': true, // individual tasks can start immediately
      });
      setState(() => _currentQuestionId = newDoc.id);
    } else {
      setState(() => _currentQuestionId = snap.docs.first.id);
    }
  }

  Widget _buildTaskBody(
      BuildContext context,
      AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>?> groupSnap,
      bool isLeader,
      ) {
    final user = _auth.currentUser;

    Future<void> _loadLatestQuestionId() async {
      if (_currentQuestionId != null) return;

      final query = widget.isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1)
          : FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.courseId)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final qId = snapshot.docs.first.id;
        setState(() {
          _currentQuestionId = qId;
          if (widget.isGroup) {
            _questionFuture = FirebaseFirestore.instance
                .collection('groups')
                .doc(widget.groupId!)
                .collection('questions')
                .doc(qId)
                .get();
          } else {
            _questionFuture = FirebaseFirestore.instance
                .collection('courses')
                .doc(widget.courseId)
                .collection('assignments')
                .doc(widget.assignmentId)
                .collection('questions')
                .doc(qId)
                .get();
          }
        });
      }
    }

    return Builder(
      builder: (context) {
        _loadLatestQuestionId();

        final questionRef = widget.isGroup
            ? FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId!)
            .collection('questions')
            .doc(_currentQuestionId)
            : FirebaseFirestore.instance
            .collection('courses')
            .doc(widget.courseId)
            .collection('assignments')
            .doc(widget.assignmentId)
            .collection('questions')
            .doc(_currentQuestionId);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: (_currentQuestionId == null)
              ? const Stream.empty()
              : questionRef.snapshots(),
          builder: (context, qSnap) {
            if (_currentQuestionId == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        widget.isGroup
                            ? 'No question has been uploaded yet.\nOnly the group leader can upload one.'
                            : 'Setting up your personal assignment...',
                        textAlign: TextAlign.center,
                        style:
                        const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      if (widget.isGroup && isLeader)
                        ElevatedButton.icon(
                          onPressed: _uploadQuestionDialog,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload Question'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            if (!qSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final q = qSnap.data!.data() ?? {};
            final locked = q['locked'] == true;

            if (_locked != locked) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _locked = locked;
                  });
                }
              });
            }

            final tasks = widget.isGroup
                ? FirebaseFirestore.instance
                .collection('groups')
                .doc(widget.groupId!)
                .collection('questions')
                .doc(_currentQuestionId)
                .collection('tasks')
                : FirebaseFirestore.instance
                .collection('courses')
                .doc(widget.courseId)
                .collection('assignments')
                .doc(widget.assignmentId)
                .collection('questions')
                .doc(_currentQuestionId)
                .collection('tasks');

            if (!_ranOverdueScan) {
              _ranOverdueScan = true;
              _autoFlagOverdueTasks(tasks);
            }

            return StatefulBuilder(
              builder: (context, setInnerState) {
                return SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // --- Question title & description ---
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurple.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    q['title'] ?? 'Untitled Question',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ),
                                if (!widget.isGroup || isLeader)
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded,
                                        color: Colors.deepPurple),
                                    tooltip: 'Reupload / Edit Question',
                                    onPressed: _uploadQuestionDialog,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              q['description'] ?? 'No description provided.',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            // --- Attachments section ---
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final List atts = (q['attachments'] ?? []) as List;
                                if (atts.isEmpty) return const SizedBox.shrink();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Attachments',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...atts.map((a) {
                                      final Map data = a as Map;
                                      final String name = (data['name'] ?? 'file') as String;
                                      final String url = (data['url'] ?? '') as String;
                                      final String type = (data['type'] ?? 'file') as String;

                                      IconData ico;
                                      if (type == 'pdf') {
                                        ico = Icons.picture_as_pdf;
                                      } else {
                                        ico = Icons.image_outlined;
                                      }

                                      return Card(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        child: ListTile(
                                          leading: Icon(ico, color: Colors.deepPurple),
                                          title: Text(name, overflow: TextOverflow.ellipsis),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.open_in_new),
                                                tooltip: 'Open file',
                                                onPressed: () async {
                                                  final uri = Uri.tryParse(url);
                                                  if (uri != null) {
                                                    try {
                                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                    } catch (_) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('Unable to open file.')),
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                              if (isLeader)
                                                IconButton(
                                                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                                                  tooltip: 'Delete file',
                                                  onPressed: () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text('Delete Attachment'),
                                                        content: Text('Are you sure you want to delete "$name"?'),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () => Navigator.pop(ctx, false),
                                                              child: const Text('Cancel')),
                                                          ElevatedButton(
                                                            onPressed: () => Navigator.pop(ctx, true),
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: Colors.red,
                                                            ),
                                                            child: const Text('Delete'),
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (confirm == true) {
                                                      // Get current question reference
                                                      final qRef = widget.isGroup
                                                          ? FirebaseFirestore.instance
                                                          .collection('groups')
                                                          .doc(widget.groupId!)
                                                          .collection('questions')
                                                          .doc(_currentQuestionId)
                                                          : FirebaseFirestore.instance
                                                          .collection('courses')
                                                          .doc(widget.courseId)
                                                          .collection('assignments')
                                                          .doc(widget.assignmentId)
                                                          .collection('questions')
                                                          .doc(_currentQuestionId);

                                                      await _deleteAttachment(
                                                        fileData: Map<String, dynamic>.from(data),
                                                        questionRef: qRef,
                                                      );
                                                      setState(() {}); // refresh UI
                                                    }
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // --- Overall progress ---

                      if (widget.isGroup && locked)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: tasks.snapshots(),
                          builder: (context, taskSnap) {
                            final docs = taskSnap.data?.docs ?? const [];
                            final overall = _calculateOverallProgress(docs);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Overall Progress',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: overall,
                                  backgroundColor: Colors.grey.shade300,
                                  color: overall == 1.0
                                      ? Colors.green
                                      : Colors.deepPurple,
                                  minHeight: 10,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(overall * 100).toStringAsFixed(0)}% completed',
                                  style: TextStyle(
                                      color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),

                      // --- Assignment deadline ---
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: widget.isGroup
                            ? StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('groups')
                              .doc(widget.groupId!)
                              .snapshots(),
                          builder: (context, snap) {
                            if (!snap.hasData)
                              return const SizedBox.shrink();
                            final data = snap.data!.data();
                            final due =
                            (data?['dueDate'] as Timestamp?)?.toDate();
                            if (due == null)
                              return const SizedBox.shrink();
                            return Text(
                              'Assignment Deadline: ${due.toLocal().toString().split(' ').first}',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            );
                            final bool deadlinePassed = due.isBefore(DateTime.now());
                          },
                        )
                            : StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('courses')
                              .doc(widget.courseId)
                              .collection('assignments')
                              .doc(widget.assignmentId)
                              .snapshots(),
                          builder: (context, snap) {
                            if (!snap.hasData)
                              return const SizedBox.shrink();
                            final data = snap.data!.data();
                            final due =
                            (data?['dueDate'] as Timestamp?)?.toDate();
                            if (due == null)
                              return const SizedBox.shrink();
                            return Text(
                              'Assignment Deadline: ${due.toLocal().toString().split(' ').first}',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // --- Poll and controls ---
                      if (widget.isGroup) ...[
                        _poll(tasks, locked),
                        const SizedBox(height: 12),

                        if (isLeader) ...[
                          locked
                              ? ElevatedButton.icon(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text(
                                      'Redistribute Tasks?'),
                                  content: const Text(
                                      'This will unlock the poll and clear all claimed tasks.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child:
                                      const Text('Redistribute'),
                                    ),
                                  ],
                                ),
                              );

                              if (ok == true) {
                                final snapshot = await tasks.get();
                                for (final doc in snapshot.docs) {
                                  await doc.reference.update({
                                    'assignedTo': null,
                                    'assignedName': null,
                                    'status': 'todo',
                                  });
                                }

                                await _setLocked(false);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                    content:
                                    Text('Editing reopened.')));
                              }
                            },
                            icon: const Icon(Icons.lock_open),
                            label:
                            const Text('Redistribute Tasks'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          )
                              : StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: tasks.snapshots(),
                            builder: (context, taskSnap) {
                              final hasTasks =
                                  taskSnap.data?.docs.isNotEmpty ??
                                      false;
                              return ElevatedButton.icon(
                                onPressed: hasTasks
                                    ? () async {
                                  final ok =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text(
                                          'Finalize Distribution?'),
                                      content: const Text(
                                          'Members will be able to claim tasks once finalized.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx, false),
                                          child: const Text(
                                              'Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx, true),
                                          child: const Text(
                                              'Finalize'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (ok == true) {
                                    await _setLocked(true);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Distribution finalized!')));
                                  }
                                }
                                    : null,
                                icon: const Icon(Icons.lock),
                                label: const Text(
                                    'Finalize Distribution'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasTasks
                                      ? Colors.deepPurple
                                      : Colors.grey.shade400,
                                  foregroundColor: Colors.white,
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 16),

                        if (locked) _buildTabs(tasks, setInnerState),
                      ] else ...[
                        const SizedBox(height: 8),
                        const Text(
                          'This is an individual assignment.\nYou can manage your personal tasks below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox.shrink(),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─────────────────────────── Build ───────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    Future<void> _loadLatestQuestionId() async {
      if (_currentQuestionId != null) return;

      final query = widget.isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1)
          : FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.courseId)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('questions')
          .orderBy('createdAt', descending: true)
          .limit(1);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final qId = snapshot.docs.first.id;
        setState(() {
          _currentQuestionId = qId;
          _questionFuture = FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId!)
              .collection('questions')
              .doc(qId)
              .get();
        });
      }
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: widget.isGroup
          ? FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)       // safe because isGroup == true
          .get()
          : Future.value(null),
      builder: (context, groupSnap) {
        final leaderId = groupSnap.data?.data()?['createdBy'];
        final isLeader = widget.isGroup && leaderId != null && _auth.currentUser?.uid == leaderId;

        final qRef = widget.isGroup
            ? FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId!)
            .collection('questions')
            .orderBy('createdAt', descending: true)
            .limit(1)
            : FirebaseFirestore.instance
            .collection('courses')
            .doc(widget.courseId)
            .collection('assignments')
            .doc(widget.assignmentId)
            .collection('questions')
            .orderBy('createdAt', descending: true)
            .limit(1);

        return DefaultTabController(
          // two tabs for group mode, one for individual
          length: widget.isGroup ? 2 : 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${widget.assignmentTitle} — Tasks'),
              bottom: widget.isGroup
                  ? PreferredSize(
                preferredSize: const Size.fromHeight(85), // 🔼 slightly taller
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 6), // 🔼 add breathing space
                  child: SizedBox(
                    height: 56, // ✅ reduce the visible tab height
                    child: const TabBar(
                      indicatorColor: Colors.deepPurple,
                      labelColor: Colors.deepPurple,
                      unselectedLabelColor: Colors.grey,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      tabs: [
                        Tab(
                          icon: Icon(Icons.task_outlined, size: 18),
                          text: 'Tasks',
                        ),
                        Tab(
                          icon: Icon(Icons.history, size: 18),
                          text: 'Group Activity',
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  : null,
              actions: [
                if (widget.isGroup)
                  IconButton(
                    onPressed: _showGroupMembersDialog,
                    icon: const Icon(Icons.people_alt_outlined),
                    tooltip: 'View Group Members',
                  ),
              ],
            ),

            // 🧭 Swipe between pages
            body: TabBarView(
              physics: const BouncingScrollPhysics(),
              children: [
                // your entire existing tasks content
                Builder(
                  builder: (context) {
                    _loadLatestQuestionId();
                    // keep your full original body content here (no need to move anything else)
                    return _buildTaskBody(context, groupSnap, isLeader);
                  },
                ),
                if (widget.isGroup)
                  GroupActivityPage(groupId: widget.groupId!)
                else
                  const SizedBox(),
              ],
            ),
            floatingActionButton: widget.isGroup
                ? SpeedDial(
              icon: Icons.add,
              activeIcon: Icons.close,
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              spacing: 8,
              spaceBetweenChildren: 6,
              tooltip: 'Quick Actions',
              children: [
                SpeedDialChild(
                  child: const Icon(Icons.playlist_add_check),
                  backgroundColor: Colors.deepPurple.shade100,
                  label: 'Add Task',
                  onTap: () {
                    if (_currentQuestionId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Upload a question first.')),
                      );
                      return;
                    }

                    if (_locked) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You can only add tasks while the task poll is in editing state.'),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MultiTaskAddPage(
                          questionId: _currentQuestionId!,
                          isGroup: widget.isGroup,
                          parentId: widget.groupId!,
                        ),
                      ),
                    );
                  },
                ),
              ],
            )
                : null,
          ),
        );
      },
    );
  }
}

class _FilteredTaskList extends StatefulWidget {
  final Query<Map<String, dynamic>> taskQuery;

  const _FilteredTaskList({required this.taskQuery});

  @override
  State<_FilteredTaskList> createState() => _FilteredTaskListState();
}

class _FilteredTaskListState extends State<_FilteredTaskList> {
  String _selectedTab = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter bar (horizontal)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _tab('all', 'All Tasks', Icons.list_alt),
              _tab('todo', 'To-Do', Icons.task_alt),
              _tab('doing', 'In Progress', Icons.timelapse),
              _tab('done', 'Completed', Icons.check_circle),
            ],
          ),
        ),

        // Task list
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.taskQuery.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            final filtered = _selectedTab == 'all'
                ? docs
                : docs.where((d) => d['status'] == _selectedTab).toList();

            if (filtered.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tasks in this category.'),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final t = filtered[i];
                final data = t.data();
                final isMine = data['assignedTo'] ==
                    FirebaseAuth.instance.currentUser?.uid;

                final bg = switch (data['status']) {
                  'done' => Colors.green.shade50,
                  'doing' => Colors.amber.shade50,
                  _ => Colors.grey.shade100,
                };

                return Card(
                  color: bg,
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: isMine
                        ? const BorderSide(color: Colors.deepPurple, width: 1)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    title: Text(data['title'] ?? 'Untitled'),
                    subtitle: Text((data['status'] ?? 'todo').toUpperCase()),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _tab(String key, String label, IconData icon) {
    final selected = _selectedTab == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: Icon(icon, size: 18),
        selected: selected,
        onSelected: (_) => setState(() => _selectedTab = key),
      ),
    );
  }
}

class _TaskListView extends StatefulWidget {
  final String storageKey;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks;

  const _TaskListView({
    required this.storageKey,
    required this.tasks,
  });

  @override
  State<_TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<_TaskListView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ✅ tells Flutter to keep this subtree alive

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView.builder(
      key: PageStorageKey(widget.storageKey), // ✅ stable identity per tab
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: widget.tasks.length,
        itemBuilder: (context, index) {
          final t = widget.tasks[index];
          final data = t.data();
          final assignedTo = data['assignedTo'];
          final isMine = assignedTo == FirebaseAuth.instance.currentUser?.uid;
          final Timestamp? dueTs = data['dueDate'] as Timestamp?;
          final DateTime? due = dueTs?.toDate();
          final String status = (data['status'] ?? 'todo') as String;
          final bool isOverdue = due != null && DateTime.now().isAfter(due) && status != 'done';
          final bool flagged = data['flagged'] == true;

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskDetailPage(taskRef: t.reference),
                ),
              );
            },
            child: Card(
              color: data['status'] == 'done'
                  ? Colors.green.shade50
                  : data['status'] == 'doing'
                  ? Colors.amber.shade50
                  : Colors.grey.shade100,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: isMine
                    ? const BorderSide(color: Colors.deepPurple, width: 1)
                    : BorderSide.none,
              ),
              child: ListTile(
                leading: const Icon(Icons.work_outline, color: Colors.black54),
                title: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              data['title'] ?? 'Untitled',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOverdue) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                                  SizedBox(width: 4),
                                  Text('Overdue', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (isMine)
                      const Text(
                        ' (Me)',
                        style: TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                subtitle: due == null
                    ? null
                    : Text(
                  isOverdue
                      ? 'Deadline: ${due.toLocal().toString().split(" ").first} (overdue)'
                      : 'Deadline: ${due.toLocal().toString().split(" ").first}',
                  style: TextStyle(
                    color: isOverdue ? Colors.red : Colors.black54,
                    fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
    );
  }
}
