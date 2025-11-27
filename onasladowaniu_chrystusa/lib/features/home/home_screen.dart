import 'package:flutter/material.dart';
import '../../shared/services/reading_challenge_service.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/models/book_models.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/journal_service.dart';
import '../challenge/reading_challenge_screen.dart';

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
  final ReadingChallengeService _challengeService = ReadingChallengeService();
  final BookRepository _bookRepository = BookRepository();

  String? _lastChapterRef;
  ReadingChallengeState? _challengeState;

  int? _totalChapters;
  int? _furthestChapterIndex;

  @override
  void initState() {
    super.initState();
    _loadLastChapterRef();
    _loadChallengeState();
  }

  Future<void> _loadLastChapterRef() async {
    final ref = await _prefs.getLastChapterRef();
    if (!mounted) return;
    setState(() {
      _lastChapterRef = ref;
    });
  }

  Future<void> _loadChallengeState() async {
    final state = await _challengeService.getState();
    if (!mounted) return;
    setState(() {
      _challengeState = state;
    });
    await _loadChallengeProgress(state);
  }

  Future<void> _loadChallengeProgress(ReadingChallengeState state) async {
    if (!state.isActive || state.furthestChapterRef == null) {
      if (!mounted) return;
      setState(() {
        _totalChapters = null;
        _furthestChapterIndex = null;
      });
      return;
    }

    try {
      final collection = await _bookRepository.getCollection();
      int total = 0;
      int index = 0;
      int? furthestIndex;

      for (final book in collection.books) {
        for (final chapter in book.chapters) {
          index++;
          total++;
          if (chapter.reference == state.furthestChapterRef) {
            furthestIndex = index;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _totalChapters = total;
        _furthestChapterIndex = furthestIndex;
      });
    } catch (_) {}
  }

  Future<void> _openChallengeScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadingChallengeScreen(
          onNavigateToTab: widget.onNavigateToTab,
        ),
      ),
    );

    if (!mounted) return;

    final state = await _challengeService.getState();
    if (!mounted) return;
    setState(() {
      _challengeState = state;
    });
    await _loadChallengeProgress(state);
    await _loadLastChapterRef();
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final m = two(local.month);
    final d = two(local.day);
    return '$y-$m-$d';
  }

  String get _challengeSubtitle {
    final state = _challengeState;

    if (state == null) {
      return 'Sprawdzanie statusu wyzwania...';
    }

    if (!state.isActive) {
      return 'Rozpocznij wyzwanie i stopniowo przeczytaj całą książkę.';
    }

    final startedStr = _formatDate(state.startedAt!);

    if (_lastChapterRef == null || _lastChapterRef!.isEmpty) {
      return 'Wyzwanie aktywne od $startedStr. Zacznij od Księgi I, rozdziału 1.';
    }

    final parts = _lastChapterRef!.split('-');
    if (parts.length == 2) {
      final bookCode = parts[0];
      final chapterNumber = parts[1];
      return 'Wyzwanie od $startedStr. Obecnie: Księga $bookCode, rozdział $chapterNumber.';
    }

    return 'Wyzwanie od $startedStr. Obecnie: rozdział $_lastChapterRef.';
  }

  String get _continueReadingSubtitle {
    if (_lastChapterRef == null || _lastChapterRef!.isEmpty) {
      return 'Wróć do ostatnio czytanego miejsca.';
    }

    final parts = _lastChapterRef!.split('-');
    if (parts.length == 2) {
      final bookCode = parts[0];
      final chapterNumber = parts[1];
      return 'Księga $bookCode, rozdział $chapterNumber';
    }

    return 'Rozdział $_lastChapterRef';
  }

  double get _challengeProgressValue {
    if (_totalChapters == null ||
        _totalChapters == 0 ||
        _furthestChapterIndex == null) {
      return 0.0;
    }
    final value = _furthestChapterIndex! / _totalChapters!;
    if (value.isNaN || value.isInfinite) return 0.0;
    return value.clamp(0.0, 1.0);
  }

  Future<void> _showRandomQuoteBottomSheet() async {
    try {
      final BookParagraph paragraph = await _bookRepository.getRandomParagraph();
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
                        // Skok do rozdziału (bez zmiany lastChapterRef)
                        await _prefs.setJumpChapterRef(chapterRef);
                      }

                      // Jeśli referencja ma trzeci człon (np. I-3-7), potraktuj go jako numer akapitu
                      final refParts = paragraph.reference.split('-');
                      if (refParts.length >= 3) {
                        final num = int.tryParse(refParts[2]);
                        if (num != null) {
                          await _prefs.setJumpParagraphNumber(num);
                        } else {
                          await _prefs.clearJumpParagraphNumber();
                        }
                      } else {
                        await _prefs.clearJumpParagraphNumber();
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

  // --- KAFELKI ---

  Widget _buildContinueReadingCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        widget.onNavigateToTab?.call(1);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_fill,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kontynuuj czytanie',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _continueReadingSubtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildChallengeCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = _challengeState;
    final isActive = state?.isActive ?? false;

    double progress = 0.0;
    String progressLabel = '';

    if (isActive) {
      if (_totalChapters != null &&
          _totalChapters! > 0 &&
          _furthestChapterIndex != null) {
        progress = _challengeProgressValue;
        final percent = (progress * 100).round();
        progressLabel =
            'Postęp: $_furthestChapterIndex / $_totalChapters ($percent%)';
      } else {
        progressLabel = 'Obliczanie postępu...';
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final currentState = _challengeState;

        if (currentState == null || !currentState.isActive) {
          const startRef = 'I-1';

          await _challengeService.startChallenge();
          await _prefs.saveLastChapterRef(startRef);
          await _prefs.setJumpChapterRef(startRef);
          await _challengeService.updateFurthestChapter(startRef);

          final newState = await _challengeService.getState();
          if (!mounted) return;
          setState(() {
            _challengeState = newState;
            _lastChapterRef = startRef;
          });
          await _loadChallengeProgress(newState);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rozpoczęto wyzwanie: Czytaj całość od początku.'),
            ),
          );
        }

        widget.onNavigateToTab?.call(1);
      },
      onLongPress: _openChallengeScreen,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.flag,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Wyzwanie: Czytaj całość',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _challengeSubtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor:
                      colorScheme.onSurface.withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                progressLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRandomQuoteCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _showRandomQuoteBottomSheet();
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Losuj cytat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Wyświetl losowy fragment z książki.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
