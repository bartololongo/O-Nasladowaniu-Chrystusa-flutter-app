class Bookmark {
  final String id;
  final String chapterRef;
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.chapterRef,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      chapterRef: json['chapterRef'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chapterRef': chapterRef,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Ulubiony cytat (na poziomie akapitu)
class FavoriteQuote {
  final String id;
  final String paragraphRef; // np. "I-1-3"
  final String text;
  final String? note;
  final DateTime createdAt;

  FavoriteQuote({
    required this.id,
    required this.paragraphRef,
    required this.text,
    required this.createdAt,
    this.note,
  });

  factory FavoriteQuote.fromJson(Map<String, dynamic> json) {
    return FavoriteQuote(
      id: json['id'] as String,
      paragraphRef: json['paragraphRef'] as String,
      text: json['text'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'paragraphRef': paragraphRef,
      'text': text,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
