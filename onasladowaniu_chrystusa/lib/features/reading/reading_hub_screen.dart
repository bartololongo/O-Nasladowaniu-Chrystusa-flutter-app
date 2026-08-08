import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/layout/responsive_layout.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/widgets/section_header.dart';
import '../audio/data/audio_track.dart';
import '../audio/services/app_audio_player_service.dart';
import '../audio/services/audio_resume_service.dart';
import '../audio/ui/audio_player_screen.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../favorites/favorites_screen.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';

class ReadingHubScreen extends StatefulWidget {
  final Key? readerScreenKey;
  final ValueListenable<int>? pendingReaderRequestSignal;
  final void Function(String query)? onOpenSearchResults;
  final void Function(int tabIndex)? onNavigateToTab;

  const ReadingHubScreen({
    super.key,
    this.readerScreenKey,
    this.pendingReaderRequestSignal,
    this.onOpenSearchResults,
    this.onNavigateToTab,
  });

  @override
  State<ReadingHubScreen> createState() => _ReadingHubScreenState();
}

class _ReadingHubScreenState extends State<ReadingHubScreen> {
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;
  final AudioResumeService _audioResumeService = AudioResumeService();

  bool _isOpeningAudioPlayer = false;
  AudioResumeTileData _audioTileData = const AudioResumeTileData(
    hasSavedProgress: false,
    chapterReference: AudioResumeService.defaultChapterReference,
  );
  StreamSubscription<AudioTrack?>? _audioTrackSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAudioTileData());
    _audioTrackSubscription = _audioService.currentTrackStream.listen((_) {
      unawaited(_loadAudioTileData());
    });
  }

  @override
  void dispose() {
    _audioTrackSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAudioTileData() async {
    final tileData = await _audioResumeService.loadTileData();

    if (!mounted) return;
    setState(() {
      _audioTileData = tileData;
    });
  }

  void _openReader(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/reader/from-reading-hub'),
        builder: (_) => ReaderScreen(
          key: widget.readerScreenKey,
          pendingReaderRequestSignal: widget.pendingReaderRequestSignal,
          onOpenSearchResults: widget.onOpenSearchResults,
        ),
      ),
    );
  }

  void _openBookmarks(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/bookmarks/from-reading-hub'),
        builder: (_) =>
            BookmarksScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  void _openFavorites(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/favorites/from-reading-hub'),
        builder: (_) =>
            FavoritesScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/search'),
        builder: (_) => SearchScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  Future<void> _openAudioPlayer() async {
    if (_isOpeningAudioPlayer) return;

    setState(() {
      _isOpeningAudioPlayer = true;
    });

    final track = await _audioResumeService.lastOrFirstTrack();

    if (!mounted) return;
    setState(() {
      _isOpeningAudioPlayer = false;
    });

    if (track == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się przygotować odtwarzacza.')),
      );
      return;
    }

    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/audio-player/from-book-hub'),
        builder: (_) => AudioPlayerScreen(track: track),
      ),
    );

    if (!mounted) return;
    await _loadAudioTileData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Książka',
              subtitle: 'Czytaj, słuchaj i wracaj do zapisanych miejsc.',
              icon: Icons.menu_book,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _openSearch(context),
                    icon: const Icon(Icons.search),
                    tooltip: 'Szukaj',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  context.layoutValue(16, compact: 12),
                  context.layoutValue(4, compact: 2),
                  context.layoutValue(16, compact: 12),
                  context.layoutValue(24, compact: 16),
                ),
                children: [
                  _ReadingHubTile(
                    icon: Icons.play_circle_fill,
                    title: 'Kontynuuj czytanie',
                    subtitle: 'Wróć do ostatniego miejsca w książce.',
                    isPrimary: true,
                    onTap: () => _openReader(context),
                  ),
                  SizedBox(height: context.layoutValue(12, compact: 8)),
                  _ReadingHubTile(
                    icon: Icons.headphones_rounded,
                    title: _audioTileData.title,
                    subtitle: _audioTileData.subtitle,
                    isLoading: _isOpeningAudioPlayer,
                    onTap: _isOpeningAudioPlayer
                        ? null
                        : () => unawaited(_openAudioPlayer()),
                  ),
                  SizedBox(height: context.layoutValue(20, compact: 14)),
                  const _ReadingHubSectionTitle('Zapisane miejsca'),
                  SizedBox(height: context.layoutValue(8, compact: 6)),
                  _ReadingHubTile(
                    icon: Icons.format_quote,
                    title: 'Ulubione',
                    subtitle: 'Fragmenty, do których chcesz wracać.',
                    onTap: () => _openFavorites(context),
                  ),
                  SizedBox(height: context.layoutValue(12, compact: 8)),
                  _ReadingHubTile(
                    icon: Icons.bookmark_border,
                    title: 'Zakładki',
                    subtitle: 'Szybki powrót do zapisanych rozdziałów.',
                    onTap: () => _openBookmarks(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingHubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isLoading;

  const _ReadingHubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: isPrimary ? 0.14 : 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withValues(
              alpha: isPrimary ? 0.45 : 0.3,
            ),
          ),
        ),
        padding: EdgeInsets.symmetric(
          vertical: isPrimary
              ? context.layoutValue(16, compact: 12)
              : context.layoutValue(12, compact: 10),
          horizontal: context.layoutValue(16, compact: 12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: context.layoutValue(32, compact: 28),
              color: colorScheme.primary,
            ),
            SizedBox(width: context.layoutValue(16, compact: 10)),
            Expanded(
              child: Column(
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
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _ReadingHubSectionTitle extends StatelessWidget {
  final String title;

  const _ReadingHubSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
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
}
