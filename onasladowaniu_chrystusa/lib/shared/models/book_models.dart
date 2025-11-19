class BookCollection {
  final String id;
  final String title;
  final String language;
  final String translator;
  final String? source;
  final int version;
  final List<Book> books;

  BookCollection({
    required this.id,
    required this.title,
    required this.language,
    required this.translator,
    required this.version,
    required this.books,
    this.source,
  });

  factory BookCollection.fromJson(Map<String, dynamic> json) {
    return BookCollection(
      id: json['id'] as String,
      title: json['title'] as String,
      language: json['language'] as String,
      translator: json['translator'] as String,
      source: json['source'] as String?,
      version: (json['version'] as num).toInt(),
      books: (json['books'] as List<dynamic>)
          .map((b) => Book.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'language': language,
      'translator': translator,
      'source': source,
      'version': version,
      'books': books.map((b) => b.toJson()).toList(),
    };
  }
}

class Book {
  final String code; // "I", "II", ...
  final String title;
  final List<BookChapter> chapters;

  Book({
    required this.code,
    required this.title,
    required this.chapters,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      code: json['code'] as String,
      title: json['title'] as String,
      chapters: (json['chapters'] as List<dynamic>)
          .map((c) => BookChapter.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'title': title,
      'chapters': chapters.map((c) => c.toJson()).toList(),
    };
  }
}

class BookChapter {
  final int number;
  final String reference; // "I-1"
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
      number: (json['number'] as num).toInt(),
      reference: json['reference'] as String,
      title: json['title'] as String,
      paragraphs: (json['paragraphs'] as List<dynamic>)
          .map((p) => BookParagraph.fromJson(p as Map<String, dynamic>))
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

class BookParagraph {
  final int index;
  final String reference; // "I-1-1"
  final String text;

  BookParagraph({
    required this.index,
    required this.reference,
    required this.text,
  });

  factory BookParagraph.fromJson(Map<String, dynamic> json) {
    return BookParagraph(
      index: (json['index'] as num).toInt(),
      reference: json['reference'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'reference': reference,
      'text': text,
    };
  }
}
