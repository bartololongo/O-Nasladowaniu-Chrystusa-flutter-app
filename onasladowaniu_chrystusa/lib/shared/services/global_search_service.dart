import '../models/book_models.dart';
import '../models/global_search_models.dart';
import 'book_repository.dart';
import 'bookmarks_service.dart';
import 'favorites_service.dart';
import 'journal_service.dart';

class GlobalSearchService {
  static const int _limitPerCategory = 20;

  final BookRepository _bookRepository;
  final BookmarksService _bookmarksService;
  final FavoritesService _favoritesService;
  final JournalService _journalService;

  GlobalSearchService({
    BookRepository? bookRepository,
    BookmarksService? bookmarksService,
    FavoritesService? favoritesService,
    JournalService? journalService,
  })  : _bookRepository = bookRepository ?? BookRepository(),
        _bookmarksService = bookmarksService ?? BookmarksService(),
        _favoritesService = favoritesService ?? FavoritesService(),
        _journalService = journalService ?? JournalService();

  Future<List<GlobalSearchResult>> search(String query) async {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.length < 2) return [];

    final results = <GlobalSearchResult>[];

    results.addAll(await _searchBook(normalizedQuery));
    results.addAll(await _searchBookmarks(normalizedQuery));
    results.addAll(await _searchFavorites(normalizedQuery));
    results.addAll(await _searchJournal(normalizedQuery));

    return results;
  }

  Future<List<GlobalSearchResult>> _searchBook(String query) async {
    final collection = await _bookRepository.getCollection();
    final results = <GlobalSearchResult>[];

    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        final chapterText = '${book.title} ${chapter.reference} '
            '${chapter.title}';

        if (_matches(chapterText, query)) {
          results.add(
            GlobalSearchResult(
              id: 'book-chapter-${chapter.reference}',
              type: GlobalSearchResultType.bookParagraph,
              title: chapter.title,
              subtitle: '${book.title} • ${chapter.reference}',
              snippet: _snippet(chapterText, query),
              chapterRef: chapter.reference,
            ),
          );
          if (results.length >= _limitPerCategory) return results;
        }

        for (final paragraph in chapter.paragraphs) {
          if (!_matches(paragraph.text, query)) continue;

          results.add(
            GlobalSearchResult(
              id: 'book-${paragraph.reference}',
              type: GlobalSearchResultType.bookParagraph,
              title: chapter.title,
              subtitle: '${book.title} • ${paragraph.reference}',
              snippet: _snippet(paragraph.text, query),
              chapterRef: chapter.reference,
              paragraphRef: paragraph.reference,
            ),
          );
          if (results.length >= _limitPerCategory) return results;
        }
      }
    }

    return results;
  }

  Future<List<GlobalSearchResult>> _searchBookmarks(String query) async {
    final bookmarks = await _bookmarksService.getBookmarks();
    final results = <GlobalSearchResult>[];

    for (final bookmark in bookmarks) {
      final chapter = await _bookRepository.getChapterByReference(
        bookmark.chapterRef,
      );
      final searchable = [
        bookmark.chapterRef,
        chapter?.title,
      ].whereType<String>().join(' ');

      if (!_matches(searchable, query)) continue;

      results.add(
        GlobalSearchResult(
          id: 'bookmark-${bookmark.id}',
          type: GlobalSearchResultType.bookmark,
          title: chapter?.title ?? 'Zakładka',
          subtitle: bookmark.chapterRef,
          snippet: chapter == null
              ? bookmark.chapterRef
              : _chapterPreview(chapter),
          chapterRef: bookmark.chapterRef,
        ),
      );
      if (results.length >= _limitPerCategory) return results;
    }

    return results;
  }

  Future<List<GlobalSearchResult>> _searchFavorites(String query) async {
    final favorites = await _favoritesService.getFavorites();
    final results = <GlobalSearchResult>[];

    for (final favorite in favorites) {
      final searchable = [
        favorite.paragraphRef,
        favorite.text,
        favorite.note,
      ].whereType<String>().join(' ');

      if (!_matches(searchable, query)) continue;

      results.add(
        GlobalSearchResult(
          id: 'favorite-${favorite.id}',
          type: GlobalSearchResultType.favorite,
          title: 'Ulubiony cytat',
          subtitle: favorite.paragraphRef,
          snippet: _snippet(searchable, query),
          paragraphRef: favorite.paragraphRef,
        ),
      );
      if (results.length >= _limitPerCategory) return results;
    }

    return results;
  }

  Future<List<GlobalSearchResult>> _searchJournal(String query) async {
    final entries = await _journalService.getEntries();
    final results = <GlobalSearchResult>[];

    for (final entry in entries.reversed) {
      final searchable = [
        entry.content,
        entry.quoteText,
        entry.quoteRef,
      ].whereType<String>().join(' ');

      if (!_matches(searchable, query)) continue;

      results.add(
        GlobalSearchResult(
          id: 'journal-${entry.id}',
          type: GlobalSearchResultType.journalEntry,
          title: 'Wpis z dziennika',
          subtitle: _formatDate(entry.createdAt),
          snippet: _snippet(searchable, query),
          paragraphRef: entry.quoteRef,
          journalEntryId: entry.id,
        ),
      );
      if (results.length >= _limitPerCategory) return results;
    }

    return results;
  }

  bool _matches(String value, String query) {
    return _normalize(value).contains(query);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _snippet(String text, String query) {
    final compactText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compactText.length <= 180) return compactText;

    final index = _normalize(compactText).indexOf(query);
    if (index < 0) {
      return '${compactText.substring(0, 180)}...';
    }

    final start = (index - 70).clamp(0, compactText.length);
    final end = (index + query.length + 110).clamp(start, compactText.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < compactText.length ? '...' : '';
    return '$prefix${compactText.substring(start, end)}$suffix';
  }

  String _chapterPreview(BookChapter chapter) {
    final text = chapter.paragraphs.map((p) => p.text).join(' ');
    return _snippet(text, _normalize(chapter.title));
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
