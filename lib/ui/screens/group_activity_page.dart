import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupActivityPage extends StatelessWidget {
  final String groupId;
  const GroupActivityPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final logsStream = FirebaseFirestore.instance
        .collectionGroup('logs')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: logsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('No activity yet.'));
        }

        final docs = snap.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final msg = data['message'] ?? '';
            final name = data['name'] ?? 'Member';
            final type = data['type'] ?? 'comment';
            final time = (data['timestamp'] as Timestamp?)?.toDate();

            final isStatus = type == 'status';
            final icon = isStatus
                ? Icons.check_circle_outline
                : Icons.chat_bubble_outline;
            final color = isStatus ? Colors.deepPurple : Colors.grey[700];

            return ListTile(
              leading: Icon(icon, color: color),
              title: Text(msg),
              subtitle: Text(
                '$name • ${time?.toLocal().toString().split(".").first ?? ""}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        );
      },
    );
  }
}
