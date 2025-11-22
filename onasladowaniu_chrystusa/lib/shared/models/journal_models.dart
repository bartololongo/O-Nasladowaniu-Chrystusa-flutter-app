class JournalEntry {
  final String id;
  final DateTime createdAt;
  final String content;   // Twoja notatka / treść wpisu
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
