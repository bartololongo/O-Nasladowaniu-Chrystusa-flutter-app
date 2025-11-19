import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_user_models.dart';

class BookmarksService {
  static const String _keyBookmarks = 'reader_bookmarks_v1';

  Future<List<Bookmark>> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyBookmarks);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final List<dynamic> list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveBookmarks(List<Bookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final list = bookmarks.map((b) => b.toJson()).toList();
    await prefs.setString(_keyBookmarks, json.encode(list));
  }

  Future<List<Bookmark>> getBookmarks() => _loadBookmarks();

  Future<bool> isChapterBookmarked(String chapterRef) async {
    final list = await _loadBookmarks();
    return list.any((b) => b.chapterRef == chapterRef);
  }

  Future<void> addBookmarkForChapterRef(String chapterRef) async {
    final list = await _loadBookmarks();
    final already = list.any((b) => b.chapterRef == chapterRef);
    if (already) {
      return;
    }

    final bookmark = Bookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      chapterRef: chapterRef,
      createdAt: DateTime.now(),
    );

    list.add(bookmark);
    await _saveBookmarks(list);
  }

  Future<void> removeBookmarkForChapterRef(String chapterRef) async {
    final list = await _loadBookmarks();
    final updated =
        list.where((b) => b.chapterRef != chapterRef).toList();
    await _saveBookmarks(updated);
  }
}
