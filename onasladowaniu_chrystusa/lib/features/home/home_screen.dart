import 'package:flutter/material.dart';

import '../../shared/services/book_repository.dart';
import '../../shared/models/book_models.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/journal_service.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const HomeScreen({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PreferencesService _prefs = PreferencesService();
  final FavoritesService _favoritesService = FavoritesService();
  final JournalService _journalService = JournalService();

  String? _lastChapterRef;

  @override
  void initState() {
    super.initState();
    _loadLastChapterRef();
  }

  Future<void> _loadLastChapterRef() async {
    final ref = await _prefs.getLastChapterRef();
    if (!mounted) return;
    setState(() {
      _lastChapterRef = ref;
    });
  }

  String get _continueReadingSubtitle {
    if (_lastChapterRef == null || _lastChapterRef!.isEmpty) {
      return 'Wróć do ostatnio czytanego miejsca.';
    }

    final parts = _lastChapterRef!.split('-');
    if (parts.length == 2) {
      final bookCode = parts[0]; // np. "I"
      final chapterNumber = parts[1]; // np. "3"
      return 'Księga $bookCode, rozdział $chapterNumber';
    }

    // Fallback, gdyby format był inny
    return 'Rozdział $_lastChapterRef';
  }

  Future<void> _showRandomQuoteBottomSheet() async {
    final repo = BookRepository();

    try {
      final BookParagraph paragraph = await repo.getRandomParagraph();
      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: false,
        builder: (sheetContext) {
          final colorScheme = Theme.of(sheetContext).colorScheme;

          final refParts = paragraph.reference.split('-');
          String locationText;
          String? chapterRef;
          if (refParts.length >= 2) {
            chapterRef = '${refParts[0]}-${refParts[1]}';
          }

          if (refParts.length == 3) {
            locationText =
                'Księga ${refParts[0]}, rozdział ${refParts[1]}, akapit ${refParts[2]}';
          } else if (refParts.length == 2) {
            locationText =
                'Księga ${refParts[0]}, rozdział ${refParts[1]}';
          } else {
            locationText = paragraph.reference;
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_quote,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Wylosowany cytat',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    paragraph.text,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    locationText,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.favorite_border),
                          label: const Text('Ulubione'),
                          onPressed: () async {
                            await _favoritesService
                                .addOrUpdateFavoriteForParagraph(
                              paragraph,
                              note: null,
                            );
                            if (!mounted) return;
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Dodano cytat do ulubionych.'),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Do dziennika'),
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await _addRandomQuoteToJournal(paragraph);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Zobacz w książce'),
                    onPressed: () async {
                      if (chapterRef != null && chapterRef.isNotEmpty) {
                        // TYLKO jump, nie last!
                        await _prefs.setJumpChapterRef(chapterRef);
                      }

                      if (!mounted) return;
                      Navigator.of(sheetContext).pop();

                      // przełączamy na zakładkę "Czytanie"
                      widget.onNavigateToTab?.call(1);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się wylosować cytatu: $e'),
        ),
      );
    }
  }

  Future<void> _addRandomQuoteToJournal(BookParagraph paragraph) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Dodaj do dziennika'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paragraph.text,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Twoja notatka:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Co mówi do Ciebie ten fragment? '
                        'Jak chcesz na niego odpowiedzieć?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () async {
                final note = controller.text.trim();

                await _journalService.addEntry(
                  content: note.isEmpty ? paragraph.text : note,
                  quoteText: paragraph.text,
                  quoteRef: paragraph.reference,
                );

                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dodano wpis do dziennika.'),
                  ),
                );
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('O naśladowaniu Chrystusa'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildContinueReadingCard(context),
            const SizedBox(height: 12),
            _buildChallengeCard(context),
            const SizedBox(height: 12),
            _buildRandomQuoteCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const Text(
      'Witaj!',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildContinueReadingCard(BuildContext context) {
    return _HomeCard(
      icon: Icons.play_circle_fill,
      title: 'Kontynuuj czytanie',
      subtitle: _continueReadingSubtitle,
      onTap: () {
        // Przełącz dolny pasek na zakładkę „Czytanie”
        widget.onNavigateToTab?.call(1);
      },
    );
  }

  Widget _buildChallengeCard(BuildContext context) {
    return _HomeCard(
      icon: Icons.flag,
      title: 'Wyzwanie: Czytaj całość',
      subtitle: 'Rozpocznij lub kontynuuj wyzwanie czytelnicze.',
      onTap: () {
        // Na razie brak oddzielnego ekranu wyzwania,
        // w przyszłości przełączymy na osobny tab lub ekran.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Wyzwanie będzie dostępne w jednej z kolejnych wersji.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildRandomQuoteCard(BuildContext context) {
    return _HomeCard(
      icon: Icons.auto_awesome,
      title: 'Losuj cytat',
      subtitle: 'Wyświetl losowy fragment z książki.',
      onTap: () {
        _showRandomQuoteBottomSheet();
      },
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.3),
          ),
        ),
        child: SizedBox(
          height: 80, // stała wysokość kafelka
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 16),
              Icon(
                icon,
                size: 32,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // pionowe centrum
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
