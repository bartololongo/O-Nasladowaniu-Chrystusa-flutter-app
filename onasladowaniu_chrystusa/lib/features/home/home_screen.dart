import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/services/reading_challenge_service.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/models/book_models.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/journal_service.dart';

import '../challenge/reading_challenge_screen.dart';
import '../journal/journal_screen.dart';
import '../favorites/favorites_screen.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  /// NOWE: callback do otwierania ekranów z sekcji "Więcej"
  /// (Dziennik, Ulubione, Ustawienia) tak, żeby RootScreen
  /// mógł podświetlić ikonę "Więcej" i zarządzać powrotem.
  final void Function(Widget screen)? onOpenMoreScreen;

  const HomeScreen({
    super.key,
    this.onNavigateToTab,
    this.onOpenMoreScreen,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final PreferencesService _prefs = PreferencesService();
  final FavoritesService _favoritesService = FavoritesService();
  final JournalService _journalService = JournalService();
  final ReadingChallengeService _challengeService = ReadingChallengeService();
  final BookRepository _bookRepository = BookRepository();

  String? _lastChapterRef;
  ReadingChallengeState? _challengeState;

  int? _totalChapters;
  int? _furthestChapterIndex;

  // --- Wsparcie / BuyMeACoffee ---
  static const String _supportUrl =
      'https://www.buymeacoffee.com/bartolo_longo'; 
      
  late final AnimationController _supportAnimController;
  late final Animation<double> _supportScaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadLastChapterRef();
    _loadChallengeState();

    _supportAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _supportScaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(
        parent: _supportAnimController,
        curve: Curves.easeInOut,
      ),
    );

    _supportAnimController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _supportAnimController.dispose();
    super.dispose();
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
        settings: const RouteSettings(name: '/challenge'),
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
      final BookParagraph paragraph =
          await _bookRepository.getRandomParagraph();
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
                        await _prefs.setJumpChapterRef(chapterRef);
                      }

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

  Future<void> _openSupportLink() async {
    final uri = Uri.parse(_supportUrl);
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nie udało się otworzyć strony wsparcia.'),
        ),
      );
    }
  }

  // --- QUICK ACTIONS ---

  void _openJournalQuick() {
    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(
        JournalScreen(
          onNavigateToTab: widget.onNavigateToTab,
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/journal'),
          builder: (_) => JournalScreen(
            onNavigateToTab: widget.onNavigateToTab,
          ),
        ),
      );
    }
  }

  void _openFavoritesQuick() {
    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(
        FavoritesScreen(
          onNavigateToTab: widget.onNavigateToTab,
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/favorites'),
          builder: (_) => FavoritesScreen(
            onNavigateToTab: widget.onNavigateToTab,
          ),
        ),
      );
    }
  }

  void _openBookmarksQuick() {
    widget.onNavigateToTab?.call(2);
  }

  void _openSettingsQuick() {
    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(
        const SettingsScreen(),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/settings'),
          builder: (_) => const SettingsScreen(),
        ),
      );
    }
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
            const SizedBox(height: 12),
            _buildQuickActionsRow(context),
            const SizedBox(height: 16),
            _buildContinueReadingCard(context),
            const SizedBox(height: 12),
            _buildChallengeCard(context),
            const SizedBox(height: 12),
            _buildRandomQuoteCard(context),
            const SizedBox(height: 12),
            _buildSupportCard(context),
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

  Widget _buildQuickActionsRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _QuickActionChip(
            icon: Icons.edit_note,
            label: 'Dziennik duchowy',
            colorScheme: colorScheme,
            onTap: _openJournalQuick,
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            icon: Icons.format_quote,
            label: 'Ulubione cytaty',
            colorScheme: colorScheme,
            onTap: _openFavoritesQuick,
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            icon: Icons.bookmark,
            label: 'Zakładki',
            colorScheme: colorScheme,
            onTap: _openBookmarksQuick,
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            icon: Icons.settings,
            label: 'Ustawienia',
            colorScheme: colorScheme,
            onTap: _openSettingsQuick,
          ),
        ],
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
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

  Widget _buildSupportCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ScaleTransition(
      scale: _supportScaleAnimation,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openSupportLink,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.25),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.coffee,
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
                      'Wesprzyj projekt',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jeśli aplikacja jest dla Ciebie pomocna, możesz postawić mi „wirtualną kawę”.',
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
      ),
    );
  }
}

// Mały pomocniczy widget na „chip” w pasku szybkich akcji.
class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: colorScheme.surface.withOpacity(0.16),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
