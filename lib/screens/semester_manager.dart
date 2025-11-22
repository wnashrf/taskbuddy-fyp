import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SemesterManager extends StatefulWidget {
  const SemesterManager({super.key});

  @override
  State<SemesterManager> createState() => _SemesterManagerState();
}

class _SemesterManagerState extends State<SemesterManager> {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  Future<void> _createSemester() async {
    final nameCtrl = TextEditingController();
    DateTime? start;
    DateTime? end;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Semester'),
        content: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Semester name'),
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
              if (nameCtrl.text.trim().isEmpty || start == null) return;
              await FirebaseFirestore.instance.collection('semesters').add({
                'name': nameCtrl.text.trim(),
                'startDate': start,
                'endDate': end,
                'createdBy': uid,
                'isActive': false,
              });
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _setActive(String id) async {
    final ref = FirebaseFirestore.instance.collection('semesters');
    final batch = FirebaseFirestore.instance.batch();

    final all = await ref.get();
    for (final doc in all.docs) {
      batch.update(doc.reference, {'isActive': doc.id == id});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Semesters')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('semesters')
            .orderBy('startDate')
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No semesters yet.'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i];
              final name = d['name'] ?? 'Untitled';
              final start = (d['startDate'] as Timestamp).toDate();
              final end = (d['endDate'] as Timestamp?)?.toDate();
              final active = d['isActive'] == true;

              return ListTile(
                title: Text(name,
                    style: TextStyle(
                        fontWeight:
                        active ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(
                  '${DateFormat('dd MMM').format(start)}'
                      '${end != null ? ' – ${DateFormat('dd MMM yyyy').format(end)}' : ''}',
                ),
                trailing: active
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : TextButton(
                  onPressed: () => _setActive(d.id),
                  child: const Text('Set Active'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSemester,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}
