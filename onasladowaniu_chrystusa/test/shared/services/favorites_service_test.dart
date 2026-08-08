import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onasladowaniu_chrystusa/shared/models/book_models.dart';
import 'package:onasladowaniu_chrystusa/shared/models/reader_user_models.dart';
import 'package:onasladowaniu_chrystusa/shared/services/favorites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'adds a new selection favorite after opening an existing favorite and moving chapters',
      () async {
        final original = FavoriteQuote(
          id: 'favorite-x',
          paragraphRef: 'I-1-sel-favorite-x',
          text: 'Cytat X',
          note: 'pierwotna notatka',
          createdAt: DateTime(2026, 8, 1, 10),
        );
        await _storeFavorites([original]);

        final service = FavoritesService();

        await service.addFavoriteForSelection(
          chapterRef: 'I-4',
          text: 'Nowy fragment po ręcznej nawigacji.',
        );

        final favorites = await service.getFavorites();

        expect(favorites, hasLength(2));
        expect(favorites.first.id, original.id);
        expect(favorites.first.paragraphRef, original.paragraphRef);
        expect(favorites.first.text, original.text);
        expect(favorites.first.note, original.note);
        expect(favorites.first.createdAt, original.createdAt);

        final added = favorites.last;
        expect(added.id, isNot(original.id));
        expect(added.paragraphRef, startsWith('I-4-sel-'));
        expect(added.paragraphRef, isNot(original.paragraphRef));
        expect(added.text, 'Nowy fragment po ręcznej nawigacji.');
      },
    );

    test('updating the same paragraph favorite keeps the same record', () async {
      final original = FavoriteQuote(
        id: 'favorite-i-2-3',
        paragraphRef: 'I-2-3',
        text: 'Pierwotny tekst akapitu.',
        note: 'stara notatka',
        createdAt: DateTime(2026, 8, 1, 11),
      );
      await _storeFavorites([original]);

      final service = FavoritesService();

      await service.addOrUpdateFavoriteForParagraph(
        BookParagraph(
          index: 3,
          reference: 'I-2-3',
          text: 'Zaktualizowany tekst akapitu.',
        ),
        note: 'nowa notatka',
      );

      final favorites = await service.getFavorites();

      expect(favorites, hasLength(1));
      expect(favorites.single.id, original.id);
      expect(favorites.single.paragraphRef, original.paragraphRef);
      expect(favorites.single.createdAt, original.createdAt);
      expect(favorites.single.text, 'Zaktualizowany tekst akapitu.');
      expect(favorites.single.note, 'nowa notatka');
    });
  });
}

Future<void> _storeFavorites(List<FavoriteQuote> favorites) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'reader_favorites_v1',
    json.encode(favorites.map((favorite) => favorite.toJson()).toList()),
  );
}
