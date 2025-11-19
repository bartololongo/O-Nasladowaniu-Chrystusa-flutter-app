import 'package:flutter/material.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/models/book_models.dart';

class HomeScreen extends StatelessWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const HomeScreen({
    super.key,
    this.onNavigateToTab,
  });

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
      subtitle: 'Wróć do ostatnio czytanego miejsca.',
      onTap: () {
        // Przełącz dolny pasek na zakładkę „Czytanie”
        onNavigateToTab?.call(1);
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
            content: Text('Wyzwanie będzie dostępne w jednej z kolejnych wersji.'),
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
      onTap: () async {
        final repo = BookRepository();

        try {
          final BookParagraph paragraph = await repo.getRandomParagraph();

          // Dialog z wylosowanym cytatem
          // (na razie sam tekst; później możemy dodać referencję typu I-1-3).
          // ignore: use_build_context_synchronously
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Wylosowany cytat'),
                content: Text(paragraph.text),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Zamknij'),
                  ),
                ],
              );
            },
          );
        } catch (e) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nie udało się wylosować cytatu: $e'),
            ),
          );
        }
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
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 36,
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
}
