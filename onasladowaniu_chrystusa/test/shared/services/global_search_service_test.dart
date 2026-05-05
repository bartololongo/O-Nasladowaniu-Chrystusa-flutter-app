import 'package:flutter_test/flutter_test.dart';
import 'package:onasladowaniu_chrystusa/shared/models/book_models.dart';
import 'package:onasladowaniu_chrystusa/shared/models/global_search_models.dart';
import 'package:onasladowaniu_chrystusa/shared/models/reader_user_models.dart';
import 'package:onasladowaniu_chrystusa/shared/services/book_repository.dart';
import 'package:onasladowaniu_chrystusa/shared/services/bookmarks_service.dart';
import 'package:onasladowaniu_chrystusa/shared/services/favorites_service.dart';
import 'package:onasladowaniu_chrystusa/shared/services/global_search_service.dart';
import 'package:onasladowaniu_chrystusa/shared/services/journal_service.dart';

void main() {
  group('GlobalSearchService', () {
    test(
      'search returns bookmark when query matches target chapter text',
      () async {
        final service = _createService(
          bookmarks: [
            Bookmark(id: 'bookmark-i-2', chapterRef: 'I-2', createdAt: _date),
          ],
        );

        final results = await service.search('lecz');

        final bookmarkResults = results.where(
          (result) => result.type == GlobalSearchResultType.bookmark,
        );
        expect(bookmarkResults, hasLength(1));
        expect(bookmarkResults.single.chapterRef, 'I-2');
        expect(bookmarkResults.single.snippet.toLowerCase(), contains('lecz'));
      },
    );

    test('search returns bookmark when query matches chapter title', () async {
      final service = _createService(
        bookmarks: [
          Bookmark(id: 'bookmark-i-1', chapterRef: 'I-1', createdAt: _date),
        ],
      );

      final results = await service.search('prawdy');

      final bookmarkResults = results.where(
        (result) => result.type == GlobalSearchResultType.bookmark,
      );
      expect(bookmarkResults, hasLength(1));
      expect(bookmarkResults.single.chapterRef, 'I-1');
      expect(bookmarkResults.single.title, contains('prawdy'));
    });

    test('search returns favorite with paragraphRef', () async {
      final service = _createService(
        favorites: [
          FavoriteQuote(
            id: 'favorite-i-1-2',
            paragraphRef: 'I-1-2',
            text: 'Pokorna iskra serca wraca do Boga.',
            createdAt: _date,
          ),
        ],
      );

      final results = await service.search('iskra');

      final favoriteResults = results.where(
        (result) => result.type == GlobalSearchResultType.favorite,
      );
      expect(favoriteResults, hasLength(1));
      expect(favoriteResults.single.paragraphRef, 'I-1-2');
    });

    test(
      'search returns journal entry with quoteRef as paragraphRef',
      () async {
        final service = _createService(
          journalEntries: [
            JournalEntry(
              id: 'journal-1',
              createdAt: _date,
              content: 'Dzisiejsza refleksja o cichości.',
              quoteText: 'Cichość pomaga odnaleźć pokój.',
              quoteRef: 'I-2-1',
            ),
          ],
        );

        final results = await service.search('cichość');

        final journalResults = results.where(
          (result) => result.type == GlobalSearchResultType.journalEntry,
        );
        expect(journalResults, hasLength(1));
        expect(journalResults.single.paragraphRef, 'I-2-1');
        expect(journalResults.single.journalEntryId, 'journal-1');
      },
    );
  });
}

final _date = DateTime(2026, 5, 5);

GlobalSearchService _createService({
  List<Bookmark> bookmarks = const [],
  List<FavoriteQuote> favorites = const [],
  List<JournalEntry> journalEntries = const [],
}) {
  return GlobalSearchService(
    bookRepository: _FakeBookRepository(_bookCollection),
    bookmarksService: _FakeBookmarksService(bookmarks),
    favoritesService: _FakeFavoritesService(favorites),
    journalService: _FakeJournalService(journalEntries),
  );
}

final _bookCollection = BookCollection(
  id: 'imitation-test',
  title: 'O naśladowaniu Chrystusa',
  language: 'pl',
  translator: 'Test',
  version: 1,
  books: [
    Book(
      code: 'I',
      title: 'Księga pierwsza',
      chapters: [
        BookChapter(
          number: 1,
          reference: 'I-1',
          title: 'O nauce prawdy',
          paragraphs: [
            BookParagraph(
              index: 1,
              reference: 'I-1-1',
              text: 'Kto idzie za Mną, nie chodzi w ciemności.',
            ),
            BookParagraph(
              index: 2,
              reference: 'I-1-2',
              text: 'Prawda prowadzi serce ku światłu.',
            ),
          ],
        ),
        BookChapter(
          number: 2,
          reference: 'I-2',
          title: 'O pokorze',
          paragraphs: [
            BookParagraph(
              index: 1,
              reference: 'I-2-1',
              text: 'Człowiek poznaje wiele, lecz bez miłości mało korzysta.',
            ),
            BookParagraph(
              index: 2,
              reference: 'I-2-2',
              text: 'Niech serce szuka dobra w ciszy.',
            ),
          ],
        ),
      ],
    ),
  ],
);

class _FakeBookRepository extends BookRepository {
  final BookCollection collection;

  _FakeBookRepository(this.collection);

  @override
  Future<BookCollection> getCollection() async => collection;
}

class _FakeBookmarksService extends BookmarksService {
  final List<Bookmark> bookmarks;

  _FakeBookmarksService(this.bookmarks);

  @override
  Future<List<Bookmark>> getBookmarks() async => bookmarks;
}

class _FakeFavoritesService extends FavoritesService {
  final List<FavoriteQuote> favorites;

  _FakeFavoritesService(this.favorites);

  @override
  Future<List<FavoriteQuote>> getFavorites() async => favorites;
}

class _FakeJournalService extends JournalService {
  final List<JournalEntry> entries;

  _FakeJournalService(this.entries);

  @override
  Future<List<JournalEntry>> getEntries() async => entries;
}
