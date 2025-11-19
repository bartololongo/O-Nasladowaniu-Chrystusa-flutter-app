/// Kolekcja książki „O naśladowaniu Chrystusa”
/// (jedna książka, ale struktura pozwala na łatwe rozszerzenie w przyszłości).
class BookCollection {
  final String id;
  final String title;
  final String? originalTitle;
  final String? author;
  final String? translator;
  final List<BookVolume> books;

  BookCollection({
    required this.id,
    required this.title,
    this.originalTitle,
    this.author,
    this.translator,
    required this.books,
  });

  factory BookCollection.fromJson(Map<String, dynamic> json) {
    return BookCollection(
      id: json['id'] as String,
      title: json['title'] as String,
      originalTitle: json['originalTitle'] as String?,
      author: json['author'] as String?,
      translator: json['translator'] as String?,
      books: (json['books'] as List<dynamic>)
          .map((e) => BookVolume.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalTitle': originalTitle,
      'author': author,
      'translator': translator,
      'books': books.map((b) => b.toJson()).toList(),
    };
  }
}

/// „Księga” – np. I, II, III, IV.
class BookVolume {
  final int number; // kolejność: 1, 2, 3...
  final String code; // np. "I", "II"
  final String title;
  final List<BookChapter> chapters;

  BookVolume({
    required this.number,
    required this.code,
    required this.title,
    required this.chapters,
  });

  factory BookVolume.fromJson(Map<String, dynamic> json) {
    return BookVolume(
      number: json['number'] as int,
      code: json['code'] as String,
      title: json['title'] as String,
      chapters: (json['chapters'] as List<dynamic>)
          .map((e) => BookChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'code': code,
      'title': title,
      'chapters': chapters.map((c) => c.toJson()).toList(),
    };
  }
}

/// Rozdział w księdze – np. „I-1”.
class BookChapter {
  final int number;
  final String reference; // np. "I-1"
  final String title;
  final List<BookParagraph> paragraphs;

  BookChapter({
    required this.number,
    required this.reference,
    required this.title,
    required this.paragraphs,
  });

  factory BookChapter.fromJson(Map<String, dynamic> json) {
    return BookChapter(
      number: json['number'] as int,
      reference: json['reference'] as String,
      title: json['title'] as String,
      paragraphs: (json['paragraphs'] as List<dynamic>)
          .map((e) => BookParagraph.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'reference': reference,
      'title': title,
      'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
    };
  }
}

/// Akapit – najmniejsza jednostka, do której będziemy
/// przypinać zakładki, ulubione, notatki itp.
class BookParagraph {
  final int number;
  final String reference; // np. "I-1-1"
  final String text;

  BookParagraph({
    required this.number,
    required this.reference,
    required this.text,
  });

  factory BookParagraph.fromJson(Map<String, dynamic> json) {
    return BookParagraph(
      number: json['number'] as int,
      reference: json['reference'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'reference': reference,
      'text': text,
    };
  }
}
