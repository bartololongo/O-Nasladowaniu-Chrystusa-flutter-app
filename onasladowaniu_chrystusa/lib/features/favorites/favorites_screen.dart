import 'package:flutter/material.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/models/reader_user_models.dart';

class FavoritesScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const FavoritesScreen({super.key, this.onNavigateToTab});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesService _service = FavoritesService();
  final PreferencesService _prefs = PreferencesService();

  late Future<List<FavoriteQuote>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = _service.getFavorites();
  }

  Future<void> _refresh() async {
    setState(() {
      _favoritesFuture = _service.getFavorites();
    });
  }

  String _formatRef(String paragraphRef) {
    final parts = paragraphRef.split('-');
    if (parts.length == 3) {
      return 'Księga ${parts[0]}, rozdział ${parts[1]}, akapit ${parts[2]}';
    } else if (parts.length == 2) {
      return 'Księga ${parts[0]}, rozdział ${parts[1]}';
    }
    return 'Odniesienie $paragraphRef';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final m = two(local.month);
    final d = two(local.day);
    final h = two(local.hour);
    final min = two(local.minute);
    return '$y-$m-$d $h:$min';
  }

  Future<void> _openFavorite(FavoriteQuote f) async {
    // wyciągamy referencję rozdziału z "I-1-3" lub "I-1-sel" -> "I-1"
    final parts = f.paragraphRef.split('-');
    String chapterRef;
    if (parts.length >= 2) {
      chapterRef = '${parts[0]}-${parts[1]}';
    } else {
      chapterRef = f.paragraphRef;
    }

    // 1) Jednorazowy skok do rozdziału z ulubionego cytatu
    await _prefs.setJumpChapterRef(chapterRef);

    // 2) Jeśli paragraphRef ma trzeci człon i jest liczbą – traktujemy go jako numer akapitu
    if (parts.length >= 3) {
      final num = int.tryParse(parts[2]);
      if (num != null) {
        await _prefs.setJumpParagraphNumber(num);
      } else {
        await _prefs.clearJumpParagraphNumber();
      }
    } else {
      await _prefs.clearJumpParagraphNumber();
    }

    if (!mounted) return;

    // Jeśli FavoritesScreen jest otwarty jako osobny route (np. z bottomsheet),
    // to najpierw go zamykamy, żeby wrócić do widoku z dolnym paskiem.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // przełącz na tab "Czytanie"
    widget.onNavigateToTab?.call(1);
  }

  Future<void> _deleteFavorite(FavoriteQuote f) async {
    await _service.removeFavoriteByParagraphRef(f.paragraphRef);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ulubiony cytat usunięty.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ulubione cytaty'),
      ),
      body: FutureBuilder<List<FavoriteQuote>>(
        future: _favoritesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Błąd wczytywania ulubionych:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final favorites = snapshot.data ?? [];
          if (favorites.isEmpty) {
            return const Center(
              child: Text(
                'Brak ulubionych cytatów.\nPrzytrzymaj dłużej akapit w czytniku, aby dodać pierwszy.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final f = favorites[index];
                return Dismissible(
                  key: ValueKey(f.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: Theme.of(context).colorScheme.error,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Usuń ulubiony cytat'),
                            content: const Text(
                                'Na pewno chcesz usunąć ten cytat z ulubionych?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Anuluj'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: const Text('Usuń'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) => _deleteFavorite(f),
                  child: ListTile(
                    onTap: () => _openFavorite(f),
                    title: Text(
                      _formatRef(f.paragraphRef),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (f.note != null && f.note!.isNotEmpty)
                          Text(
                            'Notatka: ${f.note}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          'Dodano: ${_formatDateTime(f.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
