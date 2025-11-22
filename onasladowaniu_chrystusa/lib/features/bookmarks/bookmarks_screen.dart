import 'package:flutter/material.dart';
import '../../shared/services/bookmarks_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/models/reader_user_models.dart';

class BookmarksScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const BookmarksScreen({super.key, this.onNavigateToTab});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final BookmarksService _service = BookmarksService();
  final PreferencesService _prefs = PreferencesService();

  late Future<List<Bookmark>> _bookmarksFuture;

  @override
  void initState() {
    super.initState();
    _bookmarksFuture = _service.getBookmarks();
  }

  Future<void> _refresh() async {
    setState(() {
      _bookmarksFuture = _service.getBookmarks();
    });
  }

  String _formatRef(String ref) {
    final parts = ref.split('-');
    if (parts.length == 2) {
      return 'Księga ${parts[0]}, rozdział ${parts[1]}';
    }
    return 'Rozdział $ref';
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

  Future<void> _openBookmark(Bookmark b) async {
    // Jednorazowy skok do rozdziału z zakładki (nie zmieniamy głównego lastChapterRef)
    await _prefs.setJumpChapterRef(b.chapterRef);

    // przełącz na tab "Czytanie"
    widget.onNavigateToTab?.call(1);
  }

  Future<void> _deleteBookmark(Bookmark b) async {
    await _service.removeBookmarkForChapterRef(b.chapterRef);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zakładka usunięta.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zakładki'),
      ),
      body: FutureBuilder<List<Bookmark>>(
        future: _bookmarksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Błąd wczytywania zakładek:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final bookmarks = snapshot.data ?? [];
          if (bookmarks.isEmpty) {
            return const Center(
              child: Text(
                'Brak zakładek.\nDodaj pierwszą zakładkę z ekranu czytania.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bookmarks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final b = bookmarks[index];
                return Dismissible(
                  key: ValueKey(b.id),
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
                            title: const Text('Usuń zakładkę'),
                            content: const Text(
                                'Na pewno chcesz usunąć tę zakładkę?'),
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
                  onDismissed: (_) => _deleteBookmark(b),
                  child: ListTile(
                    onTap: () => _openBookmark(b),
                    title: Text(_formatRef(b.chapterRef)),
                    subtitle:
                        Text('Dodano: ${_formatDateTime(b.createdAt)}'),
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
