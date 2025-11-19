import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import '../models/book_models.dart';

class BookRepository {
  static const String _assetPath = 'assets/book/imitation_pl.json';

  BookCollection? _cachedCollection;

  Future<BookCollection> _loadCollection() async {
    if (_cachedCollection != null) {
      return _cachedCollection!;
    }

    final raw = await rootBundle.loadString(_assetPath);
    final Map<String, dynamic> jsonMap =
        json.decode(raw) as Map<String, dynamic>;
    _cachedCollection = BookCollection.fromJson(jsonMap);
    return _cachedCollection!;
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
