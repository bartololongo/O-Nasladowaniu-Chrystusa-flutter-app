import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/services/book_repository.dart';
import '../../shared/models/book_models.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_challenge_service.dart';
import '../../shared/services/journal_service.dart';
import '../../shared/models/formation_challenge_models.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/navigation/main_tabs.dart';

import '../formation_challenge/formation_challenge_screen.dart';
import '../formation_challenge/formation_meditation_screen.dart';
import '../journal/journal_screen.dart';
import '../favorites/favorites_screen.dart';
import '../reader/reader_screen.dart';
import '../settings/settings_screen.dart';
import '../search/search_screen.dart';
import '../audio/data/audio_catalog.dart';
import '../audio/data/audio_track.dart';
import '../audio/services/app_audio_player_service.dart';
import '../audio/ui/audio_player_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  /// NOWE: callback do otwierania ekranów z sekcji "Więcej"
  /// (Dziennik, Ulubione, Ustawienia) tak, żeby RootScreen
  /// mógł podświetlić ikonę "Więcej" i zarządzać powrotem.
  final void Function(Widget screen)? onOpenMoreScreen;

  const HomeScreen({super.key, this.onNavigateToTab, this.onOpenMoreScreen});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final PreferencesService _prefs = PreferencesService();
  final FavoritesService _favoritesService = FavoritesService();
  final JournalService _journalService = JournalService();
  final BookRepository _bookRepository = BookRepository();
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;
  final FormationChallengeService _formationChallengeService =
      FormationChallengeService();
  final FormationChallengeProgressService _formationProgressService =
      FormationChallengeProgressService();

  String? _lastChapterRef;
  String? _lastAudioTrackId;
  String _audioChapterMeta = 'Księga I, rozdział 1';
  FormationChallengeDay? _dailyMeditationDay;
  int? _dailyMeditationTotalDays;
  StreamSubscription<AudioTrack?>? _audioTrackSubscription;

  // --- Wsparcie / BuyMeACoffee ---
  static const String _supportUrl = 'https://www.buymeacoffee.com/bartololongo';

  late final AnimationController _supportAnimController;
  late final Animation<double> _supportScaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadLastChapterRef();
    _loadLastAudioTrack();
    _loadDailyMeditationShortcut();
    _audioTrackSubscription = _audioService.currentTrackStream.listen((_) {
      unawaited(_loadLastAudioTrack());
    });

    _supportAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _supportScaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _supportAnimController, curve: Curves.easeInOut),
    );

    _supportAnimController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _audioTrackSubscription?.cancel();
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

  Future<void> _loadLastAudioTrack() async {
    final trackId = await _audioService.getLastTrackId();
    final lastChapterReference = trackId == null
        ? null
        : AudioCatalog.chapterReferenceForTrackId(trackId);
    final chapterReference = lastChapterReference ?? 'I-1';

    if (!mounted) return;
    setState(() {
      _lastAudioTrackId = lastChapterReference == null ? null : trackId;
      _audioChapterMeta = _chapterMetaForReference(chapterReference);
    });
  }

  Future<void> _loadDailyMeditationShortcut() async {
    final isStarted = await _formationProgressService.isStarted();
    final startDate = isStarted
        ? await _formationProgressService.getStartDate()
        : null;
    final totalDays = await _formationChallengeService.getTotalDays();
    final day = startDate == null
        ? null
        : await _formationChallengeService.getDayForDate(
            startDate,
            DateTime.now(),
          );

    if (!mounted) return;
    setState(() {
      _dailyMeditationDay = day;
      _dailyMeditationTotalDays = totalDays;
    });
  }

  Future<void> _openFormationChallengeScreen() async {
    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/formation-challenge'),
        builder: (_) =>
            FormationChallengeScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
    if (!mounted) return;
    await _loadDailyMeditationShortcut();
  }

  String get _continueReadingTitle {
    if (_lastChapterRef == null || _lastChapterRef!.isEmpty) {
      return 'Rozpocznij czytanie';
    }

    return 'Kontynuuj czytanie';
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

  String get _continueListeningTitle {
    if (_lastAudioTrackId == null || _lastAudioTrackId!.isEmpty) {
      return 'Rozpocznij słuchanie';
    }

    return 'Kontynuuj słuchanie';
  }

  Future<void> _openAudioQuick() async {
    final track = await _lastAudioTrack() ?? await _firstAudioTrack();
    if (track == null || !mounted) return;

    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/audio-player'),
        builder: (_) => AudioPlayerScreen(track: track),
      ),
    );

    if (!mounted) return;
    await _loadLastAudioTrack();
  }

  String get _dailyMeditationSubtitle {
    final day = _dailyMeditationDay;
    final totalDays = _dailyMeditationTotalDays;

    if (day == null || totalDays == null) {
      return 'Najpierw rozpocznij Drogę naśladowania.';
    }

    return 'Dzień ${day.dayNumber} z $totalDays';
  }

  Future<void> _openDailyMeditationQuick() async {
    final day = _dailyMeditationDay;
    final totalDays = _dailyMeditationTotalDays;

    if (day == null || totalDays == null) {
      await _openFormationChallengeScreen();
      return;
    }

    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/formation-meditation'),
        builder: (_) =>
            FormationMeditationScreen(day: day, totalDays: totalDays),
      ),
    );

    if (!mounted) return;
    await _loadDailyMeditationShortcut();
  }

  Future<AudioTrack?> _lastAudioTrack() async {
    final trackId = await _audioService.getLastTrackId();
    if (trackId == null) return null;

    final chapterReference = AudioCatalog.chapterReferenceForTrackId(trackId);
    if (chapterReference == null) return null;

    return _audioTrackForChapterReference(chapterReference);
  }

  Future<AudioTrack?> _firstAudioTrack() {
    return _audioTrackForChapterReference('I-1');
  }

  Future<AudioTrack?> _audioTrackForChapterReference(
    String chapterReference,
  ) async {
    final chapter = await _bookRepository.getChapterByReference(
      chapterReference,
    );
    if (chapter == null) return null;

    return AudioCatalog.trackForChapter(
      chapterReference: chapter.reference,
      title: chapter.title,
      subtitle: _bookTitleForReference(chapter.reference),
    );
  }

  String _bookTitleForReference(String chapterReference) {
    final bookCode = chapterReference.split('-').first;

    return switch (bookCode) {
      'I' => 'Księga pierwsza',
      'II' => 'Księga druga',
      'III' => 'Księga trzecia',
      'IV' => 'Księga czwarta',
      _ => 'Księga $bookCode',
    };
  }

  String _chapterMetaForReference(String chapterReference) {
    final parts = chapterReference.split('-');
    if (parts.length == 2) {
      return 'Księga ${parts[0]}, rozdział ${parts[1]}';
    }

    return 'Rozdział $chapterReference';
  }

  Future<void> _showRandomQuoteBottomSheet() async {
    try {
      final BookParagraph paragraph = await _bookRepository
          .getRandomParagraph();
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
            locationText = 'Księga ${refParts[0]}, rozdział ${refParts[1]}';
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
                      Icon(Icons.format_quote, color: colorScheme.primary),
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
                    style: const TextStyle(fontSize: 16, height: 1.5),
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
                                content: Text('Dodano cytat do ulubionych.'),
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

                      widget.onNavigateToTab?.call(MainTabs.read);
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
        SnackBar(content: Text('Nie udało się wylosować cytatu: $e')),
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
                Text(paragraph.text, style: const TextStyle(fontSize: 14)),
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
                  const SnackBar(content: Text('Dodano wpis do dziennika.')),
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
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        JournalScreen(onNavigateToTab: widget.onNavigateToTab),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/journal'),
          builder: (_) =>
              JournalScreen(onNavigateToTab: widget.onNavigateToTab),
        ),
      );
    }
  }

  void _openFavoritesQuick() {
    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(
        FavoritesScreen(onNavigateToTab: widget.onNavigateToTab),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/favorites'),
          builder: (_) =>
              FavoritesScreen(onNavigateToTab: widget.onNavigateToTab),
        ),
      );
    }
  }

  void _openBookmarksQuick() {
    widget.onNavigateToTab?.call(MainTabs.read);
  }

  void _openSettingsQuick() {
    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(const SettingsScreen());
    } else {
      Navigator.of(context).push(
        AppPageRoute.fade(
          settings: const RouteSettings(name: '/settings'),
          builder: (_) => const SettingsScreen(),
        ),
      );
    }
  }

  void _openSearchScreen() {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/search'),
        builder: (_) => SearchScreen(
          onNavigateToTab: widget.onNavigateToTab,
          onOpenMoreScreen: widget.onOpenMoreScreen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(
              Icons.auto_stories_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'O naśladowaniu Chrystusa',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Droga codziennej lektury i refleksji',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openSearchScreen,
            icon: const Icon(Icons.search),
            tooltip: 'Szukaj',
          ),
          IconButton(
            onPressed: _openSettingsQuick,
            icon: const Icon(Icons.settings),
            tooltip: 'Ustawienia',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildStartIntro(context),
            const SizedBox(height: 20),
            _buildSectionTitle(context, 'Na teraz'),
            const SizedBox(height: 8),
            _buildContinueReadingCard(context),
            const SizedBox(height: 12),
            _buildContinueListeningCard(context),
            const SizedBox(height: 12),
            _buildDailyMeditationCard(context),
            const SizedBox(height: 20),
            _buildSectionTitle(context, 'Dodatkowe skróty'),
            const SizedBox(height: 8),
            _buildRandomQuoteCard(context),
            const SizedBox(height: 12),
            _buildSupportCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStartIntro(BuildContext context) {
    return Text(
      'Wróć do czytania, słuchania albo dzisiejszej medytacji.',
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const Text(
      'Witaj!',
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    );
  }

  // ignore: unused_element
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
            icon: Icons.auto_stories_outlined,
            label: 'Droga',
            colorScheme: colorScheme,
            onTap: _openFormationChallengeScreen,
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
        Navigator.of(context).push(
          AppPageRoute.fade(
            settings: const RouteSettings(name: '/reader/from-home'),
            builder: (_) => const ReaderScreen(),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill, size: 32, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _continueReadingTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _continueReadingSubtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildContinueListeningCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => unawaited(_openAudioQuick()),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.headphones_rounded,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _continueListeningTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _audioChapterMeta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildDailyMeditationCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => unawaited(_openDailyMeditationQuick()),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.self_improvement_rounded,
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
                    'Medytacja z dnia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dailyMeditationSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
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

  // ignore: unused_element
  Widget _buildFormationChallengeCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openFormationChallengeScreen,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
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
                    'Droga naśladowania',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Codzienna medytacja z książką',
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
          border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 32, color: colorScheme.primary),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Losuj cytat',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Wyświetl losowy fragment z książki.',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
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
            border: Border.all(color: colorScheme.primary.withOpacity(0.25)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.coffee, size: 32, color: colorScheme.primary),
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
          border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
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
