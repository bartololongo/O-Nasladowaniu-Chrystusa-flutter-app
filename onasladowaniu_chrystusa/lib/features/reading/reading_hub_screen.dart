import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/navigation/app_page_route.dart';
import '../../shared/widgets/section_header.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../favorites/favorites_screen.dart';
import '../journal/journal_screen.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

class ReadingHubScreen extends StatelessWidget {
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

  void _openReader(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/reader/from-reading-hub'),
        builder: (_) => ReaderScreen(
          key: readerScreenKey,
          pendingReaderRequestSignal: pendingReaderRequestSignal,
          onOpenSearchResults: onOpenSearchResults,
        ),
      ),
    );
  }

  void _openBookmarks(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/bookmarks/from-reading-hub'),
        builder: (_) => BookmarksScreen(onNavigateToTab: onNavigateToTab),
      ),
    );
  }

  void _openFavorites(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/favorites/from-reading-hub'),
        builder: (_) => FavoritesScreen(onNavigateToTab: onNavigateToTab),
      ),
    );
  }

  void _openJournal(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/journal/from-reading-hub'),
        builder: (_) => JournalScreen(onNavigateToTab: onNavigateToTab),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/search'),
        builder: (_) => SearchScreen(onNavigateToTab: onNavigateToTab),
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
              title: 'Czytaj',
              subtitle:
                  'Czytaj, wracaj do ważnych fragmentów i zapisuj swoje refleksje.',
              icon: Icons.menu_book,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _openSearch(context),
                    icon: const Icon(Icons.search),
                    tooltip: 'Szukaj',
                  ),
                  IconButton(
                    onPressed: () => _openSettings(context),
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
                  _ReadingHubTile(
                    icon: Icons.play_circle_fill,
                    title: 'Kontynuuj czytanie',
                    subtitle: 'Wróć do ostatniego miejsca w książce.',
                    isPrimary: true,
                    onTap: () => _openReader(context),
                  ),
                  const SizedBox(height: 20),
                  const _ReadingHubSectionTitle('Twoje miejsca i refleksje'),
                  const SizedBox(height: 8),
                  _ReadingHubTile(
                    icon: Icons.edit_note,
                    title: 'Dziennik duchowy',
                    subtitle: 'Twoje notatki, refleksje i odpowiedzi.',
                    onTap: () => _openJournal(context),
                  ),
                  const SizedBox(height: 12),
                  _ReadingHubTile(
                    icon: Icons.format_quote,
                    title: 'Ulubione',
                    subtitle: 'Fragmenty, do których chcesz wracać.',
                    onTap: () => _openFavorites(context),
                  ),
                  const SizedBox(height: 12),
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
  final VoidCallback onTap;
  final bool isPrimary;

  const _ReadingHubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
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
          vertical: isPrimary ? 16 : 12,
          horizontal: 16,
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: colorScheme.primary),
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
