import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/models/book_models.dart';
import '../../../shared/services/book_repository.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/audio_catalog.dart';
import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';
import 'audio_player_screen.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';

class ListenScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const ListenScreen({super.key, this.onNavigateToTab});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;
  final BookRepository _bookRepository = BookRepository();

  bool _isOpeningPlayer = false;

  Future<void> _openAudioPlayer() async {
    if (_isOpeningPlayer) return;

    setState(() {
      _isOpeningPlayer = true;
    });

    final track = await _lastAudioTrack() ?? await _firstAudioTrack();

    if (!mounted) return;
    setState(() {
      _isOpeningPlayer = false;
    });

    if (track == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się przygotować odtwarzacza.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/audio-player/from-listen'),
        builder: (_) => AudioPlayerScreen(track: track),
      ),
    );
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
      subtitle: _bookTitleForChapter(chapter),
    );
  }

  String _bookTitleForChapter(BookChapter chapter) {
    final bookCode = chapter.reference.split('-').first;

    return switch (bookCode) {
      'I' => 'Księga pierwsza',
      'II' => 'Księga druga',
      'III' => 'Księga trzecia',
      'IV' => 'Księga czwarta',
      _ => 'Księga $bookCode',
    };
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/search'),
        builder: (_) => SearchScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Słuchaj',
              subtitle:
                  'Wróć do ostatniego miejsca odsłuchu albo rozpocznij słuchanie od początku.',
              icon: Icons.headphones_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search),
                    tooltip: 'Szukaj',
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                    tooltip: 'Ustawienia',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _ListenTile(
                    title: 'Kontynuuj słuchanie',
                    subtitle:
                        'Otwórz odtwarzacz i wróć do ostatniego rozdziału audio.',
                    isLoading: _isOpeningPlayer,
                    onTap: _isOpeningPlayer
                        ? null
                        : () => unawaited(_openAudioPlayer()),
                  ),
                  const SizedBox(height: 12),
                  const _ListenInfo(
                    text:
                        'Odtwarzacz zapamiętuje postęp słuchania i pozwala przechodzić między rozdziałami.',
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

class _ListenTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ListenTile({
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.45),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.headphones_rounded,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),
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

class _ListenInfo extends StatelessWidget {
  final String text;

  const _ListenInfo({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: colorScheme.onSurface.withValues(alpha: 0.62),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ),
      ],
    );
  }
}
