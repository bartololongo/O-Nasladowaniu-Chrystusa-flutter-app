import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class JournalEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String? quoteText;
  final String? quoteRef;

  JournalEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    this.quoteText,
    this.quoteRef,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      content: json['content'] as String,
      quoteText: json['quoteText'] as String?,
      quoteRef: json['quoteRef'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'content': content,
      'quoteText': quoteText,
      'quoteRef': quoteRef,
    };
  }
}

class JournalService {
  static const String _keyJournalEntries = 'journal_entries_v1';

  Future<List<JournalEntry>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyJournalEntries);
    if (raw == null || raw.isEmpty) return [];

    final List<dynamic> list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveEntries(List<JournalEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final list = entries.map((e) => e.toJson()).toList();
    await prefs.setString(_keyJournalEntries, json.encode(list));
  }

  Future<void> addEntry({
    required String content,
    String? quoteText,
    String? quoteRef,
  }) async {
    final entries = await getEntries();

    final entry = JournalEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: content,
      quoteText: quoteText,
      quoteRef: quoteRef,
    );

    entries.add(entry);
    await _saveEntries(entries);
  }

  Future<void> deleteEntry(String id) async {
    final entries = await getEntries();
    final updated = entries.where((e) => e.id != id).toList();
    await _saveEntries(updated);
  }
}
