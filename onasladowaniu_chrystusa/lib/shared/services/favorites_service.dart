import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_user_models.dart';
import '../models/book_models.dart';

class FavoritesService {
  static const String _keyFavorites = 'reader_favorites_v1';

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

    // Usuń istniejące dla tego akapitu (jedna ulubiona pozycja na akapit)
    final updated =
        list.where((f) => f.paragraphRef != paragraph.reference).toList();

    final favorite = FavoriteQuote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      paragraphRef: paragraph.reference,
      text: paragraph.text,
      note: note,
      createdAt: DateTime.now(),
    );

    updated.add(favorite);
    await _saveFavorites(updated);
  }

  Future<void> removeFavoriteByParagraphRef(String paragraphRef) async {
    final list = await _loadFavorites();
    final updated =
        list.where((f) => f.paragraphRef != paragraphRef).toList();
    await _saveFavorites(updated);
  }
}
