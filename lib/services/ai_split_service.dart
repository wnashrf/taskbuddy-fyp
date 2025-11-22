import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles communication with Google Gemini API to fairly divide a question
/// into N subtasks (no member assignment).
class AISplitService {
  AISplitService._();
  static final instance = AISplitService._();

  // TODO: Replace with your real Gemini API key from https://aistudio.google.com/app/apikey
  static const _apiKey = 'AIzaSyA6TAw8Hr3wO2uvl_8VtpwSSXd5EL-BJ2g';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent';

  /// Splits a question into [memberCount] fair subtasks.
  Future<List<Map<String, dynamic>>> splitIntoTasks({
    required String questionTitle,
    required String questionDescription,
    required int memberCount,
  }) async {
    final prompt = _buildPrompt(
      title: questionTitle,
      description: questionDescription,
      n: memberCount,
    );

    final uri = Uri.parse('$_endpoint?key=$_apiKey');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "role": "user",
            "parts": [
              {"text": prompt}
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.2
        }
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    }

    final body = jsonDecode(res.body);
    final text =
        body['candidates'][0]['content']['parts'][0]['text'] as String? ?? '';

    final jsonString = _extractJson(text);
    final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    final tasks = (parsed['tasks'] as List)
        .map<Map<String, dynamic>>((e) => {
      'title': e['title'] ?? '',
      'description': e['description'] ?? '',
      'estimated_minutes': e['estimated_minutes']
    })
        .toList();

    if (tasks.length != memberCount) {
      return _forceToN(tasks, memberCount);
    }
    return tasks;
  }

  String _buildPrompt({
    required String title,
    required String description,
    required int n,
  }) {
    return '''
You are an assistant that divides a student project question into exactly $n fair subtasks.
Each subtask should have a clear title and concise description. Do NOT assign to members.
Return STRICT JSON only:

{
  "tasks": [
    { "title": "string", "description": "string", "estimated_minutes": 45 }
  ]
}

Question Title: "$title"
Question Details: "$description"
''';
  }

  String _extractJson(String s) {
    s = s.trim();
    if (s.startsWith('{') && s.endsWith('}')) return s;
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) return s.substring(start, end + 1);
    throw Exception('LLM did not return JSON.');
  }

  List<Map<String, dynamic>> _forceToN(
      List<Map<String, dynamic>> inList, int n) {
    if (inList.isEmpty) {
      return List.generate(
          n,
              (i) => {
            'title': 'Task ${i + 1}',
            'description': 'Fill in details here.'
          });
    }
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (out.length < n) {
      out.add(Map<String, dynamic>.from(inList[i % inList.length]));
      i++;
    }
    return out.take(n).toList();
  }
}
