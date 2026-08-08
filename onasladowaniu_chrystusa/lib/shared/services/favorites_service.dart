import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_user_models.dart';
import '../models/book_models.dart';

class FavoritesService {
  static const String _keyFavorites = 'reader_favorites_v1';
  static const String _selectionRefMarker = 'sel';

  Future<List<FavoriteQuote>> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFavorites);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final List<dynamic> list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => FavoriteQuote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveFavorites(List<FavoriteQuote> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    final list = favorites.map((f) => f.toJson()).toList();
    await prefs.setString(_keyFavorites, json.encode(list));
  }

  Future<List<FavoriteQuote>> getFavorites() => _loadFavorites();

  Future<bool> isParagraphFavorite(String paragraphRef) async {
    final list = await _loadFavorites();
    return list.any((f) => f.paragraphRef == paragraphRef);
  }

  /// Dodaj lub zaktualizuj ulubiony cytat dla danego akapitu.
  Future<void> addOrUpdateFavoriteForParagraph(
    BookParagraph paragraph, {
    String? note,
  }) async {
    final list = await _loadFavorites();
    final now = DateTime.now();
    final existingIndex = list.indexWhere(
      (f) => f.paragraphRef == paragraph.reference,
    );

    if (existingIndex != -1) {
      final existing = list[existingIndex];
      list[existingIndex] = FavoriteQuote(
        id: existing.id,
        paragraphRef: existing.paragraphRef,
        text: paragraph.text,
        note: note,
        createdAt: existing.createdAt,
      );
      await _saveFavorites(list);
      return;
    }

    final favorite = FavoriteQuote(
      id: _createUniqueFavoriteId(now, list),
      paragraphRef: paragraph.reference,
      text: paragraph.text,
      note: note,
      createdAt: now,
    );

    list.add(favorite);
    await _saveFavorites(list);
  }

  /// Dodaj nowe ręczne zaznaczenie z czytnika.
  ///
  /// Zaznaczenia nie mają stabilnej referencji akapitu, więc każde z nich
  /// dostaje własną techniczną referencję. Dzięki temu kolejne zaznaczenia w
  /// tym samym rozdziale nie nadpisują wcześniejszych ulubionych cytatów.
  Future<FavoriteQuote> addFavoriteForSelection({
    required String chapterRef,
    required String text,
    String? note,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Selection text cannot be empty.');
    }

    final list = await _loadFavorites();
    final now = DateTime.now();
    final id = _createUniqueFavoriteId(now, list);
    final favorite = FavoriteQuote(
      id: id,
      paragraphRef: selectionParagraphRef(chapterRef: chapterRef, id: id),
      text: trimmedText,
      note: note,
      createdAt: now,
    );

    list.add(favorite);
    await _saveFavorites(list);
    return favorite;
  }

  Future<void> removeFavoriteByParagraphRef(String paragraphRef) async {
    final list = await _loadFavorites();
    final updated = list.where((f) => f.paragraphRef != paragraphRef).toList();
    await _saveFavorites(updated);
  }

  static String selectionParagraphRef({
    required String chapterRef,
    required String id,
  }) {
    return '$chapterRef-$_selectionRefMarker-$id';
  }

  static bool isSelectionParagraphRef(String paragraphRef) {
    final parts = paragraphRef.split('-');
    return parts.length >= 3 && parts[2] == _selectionRefMarker;
  }

  static String _createFavoriteId(DateTime now) {
    return now.microsecondsSinceEpoch.toString();
  }

  static String _createUniqueFavoriteId(
    DateTime now,
    List<FavoriteQuote> existingFavorites,
  ) {
    final baseId = _createFavoriteId(now);
    var candidate = baseId;
    var suffix = 1;
    final existingIds = existingFavorites.map((f) => f.id).toSet();

    while (existingIds.contains(candidate)) {
      candidate = '$baseId-$suffix';
      suffix += 1;
    }

    return candidate;
  }
}
