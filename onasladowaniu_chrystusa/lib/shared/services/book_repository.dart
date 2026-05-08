import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/book_models.dart';

class BookRepository {
  static const String _assetPath = 'assets/book/imitation_pl.json';
  static const String _localContentDirectory = 'content/o_nasladowaniu';
  static const String _localContentFileName = 'book_content.json';

  BookCollection? _cachedCollection;

  static Future<File> localOverrideFile() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(
      p.join(
        supportDirectory.path,
        _localContentDirectory,
        _localContentFileName,
      ),
    );
  }

  static BookCollection parseAndValidateCollection(String raw) {
    final Map<String, dynamic> jsonMap =
        json.decode(raw) as Map<String, dynamic>;
    final collection = BookCollection.fromJson(jsonMap);
    validateCollection(collection);
    return collection;
  }

  static void validateCollection(BookCollection collection) {
    if (collection.books.isEmpty) {
      throw const FormatException('Book collection has no books.');
    }

    final chapterReferences = <String>{};
    final paragraphReferences = <String>{};

    for (final book in collection.books) {
      if (book.code.trim().isEmpty) {
        throw const FormatException('Book has empty code.');
      }
      if (book.title.trim().isEmpty) {
        throw const FormatException('Book has empty title.');
      }
      if (book.chapters.isEmpty) {
        throw FormatException('Book ${book.code} has no chapters.');
      }

      for (final chapter in book.chapters) {
        final chapterReference = chapter.reference.trim();
        if (chapterReference.isEmpty) {
          throw FormatException(
            'Book ${book.code} has empty chapter reference.',
          );
        }
        if (chapter.title.trim().isEmpty) {
          throw FormatException('Chapter $chapterReference has empty title.');
        }
        if (chapter.paragraphs.isEmpty) {
          throw FormatException('Chapter $chapterReference has no paragraphs.');
        }
        if (!chapterReferences.add(chapterReference)) {
          throw FormatException(
            'Duplicate chapter reference: $chapterReference.',
          );
        }

        for (final paragraph in chapter.paragraphs) {
          final paragraphReference = paragraph.reference.trim();
          if (paragraphReference.isEmpty) {
            throw FormatException(
              'Chapter $chapterReference has empty paragraph reference.',
            );
          }
          if (paragraph.text.trim().isEmpty) {
            throw FormatException(
              'Paragraph $paragraphReference has empty text.',
            );
          }
          if (!paragraphReferences.add(paragraphReference)) {
            throw FormatException(
              'Duplicate paragraph reference: $paragraphReference.',
            );
          }
        }
      }
    }
  }

  Future<BookCollection> _loadCollection() async {
    if (_cachedCollection != null) {
      return _cachedCollection!;
    }

    final localCollection = await _loadLocalOverrideJson();
    if (localCollection != null) {
      _cachedCollection = localCollection;
      return _cachedCollection!;
    }

    _cachedCollection = await _loadBundledJson();
    return _cachedCollection!;
  }

  Future<BookCollection?> _loadLocalOverrideJson() async {
    try {
      final file = await localOverrideFile();

      if (!await file.exists()) {
        return null;
      }

      final raw = await file.readAsString();
      return _parseAndValidateCollection(raw);
    } catch (error, stackTrace) {
      debugPrint(
        'BookRepository: local content override rejected. '
        'errorType=${error.runtimeType}, error=$error',
      );
      debugPrintStack(
        label: 'BookRepository: local content override stackTrace',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<BookCollection> _loadBundledJson() async {
    final raw = await rootBundle.loadString(_assetPath);
    return _parseAndValidateCollection(raw);
  }

  BookCollection _parseAndValidateCollection(String raw) {
    return parseAndValidateCollection(raw);
  }

  /// Publiczny dostęp do całej kolekcji
  Future<BookCollection> getCollection() async {
    return _loadCollection();
  }

  /// Na start: po prostu pierwszy rozdział pierwszej księgi.
  Future<BookChapter> getFirstChapter() async {
    final collection = await _loadCollection();
    final firstBook = collection.books.first;
    final firstChapter = firstBook.chapters.first;
    return firstChapter;
  }

  /// Pobierz rozdział po referencji, np. "I-1".
  Future<BookChapter?> getChapterByReference(String reference) async {
    final collection = await _loadCollection();
    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        if (chapter.reference == reference) {
          return chapter;
        }
      }
    }
    return null;
  }

  /// Wylosuj dowolny akapit z całej książki.
  Future<BookParagraph> getRandomParagraph() async {
    final collection = await _loadCollection();
    final random = Random();

    final book = collection.books[random.nextInt(collection.books.length)];
    final chapter = book.chapters[random.nextInt(book.chapters.length)];
    final paragraph =
        chapter.paragraphs[random.nextInt(chapter.paragraphs.length)];

    return paragraph;
  }

  /// Znajdź następny rozdział po podanym (w kolejności księga → rozdziały).
  Future<BookChapter?> getNextChapter(String reference) async {
    final collection = await _loadCollection();
    bool foundCurrent = false;

    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        if (foundCurrent) {
          return chapter; // pierwszy po aktualnym
        }
        if (chapter.reference == reference) {
          foundCurrent = true;
        }
      }
    }
    return null; // brak następnego (ostatni rozdział)
  }

  /// Znajdź poprzedni rozdział przed podanym.
  Future<BookChapter?> getPreviousChapter(String reference) async {
    final collection = await _loadCollection();
    BookChapter? previous;

    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        if (chapter.reference == reference) {
          return previous; // może być null, jeśli to pierwszy rozdział
        }
        previous = chapter;
      }
    }
    return null;
  }
}
