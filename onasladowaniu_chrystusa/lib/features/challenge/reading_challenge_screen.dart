import 'package:flutter/material.dart';

import '../../shared/services/reading_challenge_service.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/models/book_models.dart';

class ReadingChallengeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const ReadingChallengeScreen({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<ReadingChallengeScreen> createState() => _ReadingChallengeScreenState();
}

class _ReadingChallengeScreenState extends State<ReadingChallengeScreen> {
  final ReadingChallengeService _challengeService = ReadingChallengeService();
  final BookRepository _bookRepository = BookRepository();
  final PreferencesService _prefs = PreferencesService();

  ReadingChallengeState? _state;

  bool _isLoading = true;
  int? _totalChapters;
  int? _furthestChapterIndex;

  List<_ChapterItem> _chapters = [];

  // Zakładki u góry: Rozdziały / Statystyki
  _ChallengeTab _currentTab = _ChallengeTab.chapters;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final state = await _challengeService.getState();
      final collection = await _bookRepository.getCollection();

      final items = <_ChapterItem>[];
      int index = 0;
      int? furthestIndex;
      final furthestRef = state.furthestChapterRef;

      for (final book in collection.books) {
        for (final chapter in book.chapters) {
          index++;
          items.add(
            _ChapterItem(
              index: index,
              reference: chapter.reference,
              bookCode: book.code,
              chapterNumber: chapter.number,
              title: chapter.title,
            ),
          );
          if (furthestRef != null && chapter.reference == furthestRef) {
            furthestIndex = index;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _state = state;
        _chapters = items;
        _totalChapters = index;
        _furthestChapterIndex = furthestIndex;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  double get _progressValue {
    final state = _state;
    if (state == null || !state.isActive) return 0.0;
    if (_totalChapters == null ||
        _totalChapters == 0 ||
        _furthestChapterIndex == null) {
      return 0.0;
    }

    final value = _furthestChapterIndex! / _totalChapters!;
    if (value.isNaN || value.isInfinite) return 0.0;
    return value.clamp(0.0, 1.0);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final m = two(local.month);
    final d = two(local.day);
    return '$y-$m-$d';
  }

  Future<void> _openChapter(_ChapterItem item) async {
    // ustawiamy jump tylko na ten rozdział, NIE zmieniamy last_chapter
    await _prefs.setJumpChapterRef(item.reference);

    if (!mounted) return;

    // przełącz na tab "Czytanie"
    widget.onNavigateToTab?.call(1);

    // zamknij ekran wyzwania
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetChallenge() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Zresetować wyzwanie?'),
            content: const Text(
              'Spowoduje to wyczyszczenie postępu „Czytaj całość” '
              'i rozpoczęcie wyzwania od początku książki. '
              'Twoje zakładki, ulubione i dziennik pozostaną bez zmian.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Anuluj'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Resetuj'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    // 1) pierwszy rozdział książki – nowy punkt startu
    final firstChapter = await _bookRepository.getFirstChapter();
    final startRef = firstChapter.reference;

    // 2) wyczyść stary stan i rozpocznij wyzwanie od nowa
    await _challengeService.resetChallenge();
    await _challengeService.startChallenge();
    await _challengeService.updateFurthestChapter(startRef);

    // 3) ustaw oficjalny postęp czytania na początek książki
    await _prefs.saveLastChapterRef(startRef);
    await _prefs.setJumpChapterRef(startRef);

    // 4) przeładuj dane ekranu (stan + lista rozdziałów + postęp)
    await _loadData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Wyzwanie zresetowane. Zaczynasz od początku książki.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wyzwanie: Czytaj całość'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (state == null || !state.isActive)
              ? _buildInactiveBody(context)
              : _buildActiveBody(context, state),
    );
  }

  Widget _buildInactiveBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.flag_outlined, size: 48),
            SizedBox(height: 16),
            Text(
              'Wyzwanie nie jest jeszcze aktywne.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Wróć na ekran startowy i użyj kafelka '
              '„Wyzwanie: Czytaj całość”, aby rozpocząć od początku książki.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBody(BuildContext context, ReadingChallengeState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final startedStr =
        state.startedAt != null ? _formatDate(state.startedAt!) : '—';
    final progress = _progressValue;
    final percent = (progress * 100).round();
    final done = _furthestChapterIndex ?? 0;
    final total = _totalChapters ?? 0;

    return Column(
      children: [
        // Podsumowanie
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Podsumowanie wyzwania',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Rozpoczęte: $startedStr',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor:
                      colorScheme.onSurface.withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Przeczytano: $done / $total (${percent}%)',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _resetChallenge,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Zresetuj wyzwanie'),
                ),
              ),
            ],
          ),
        ),

        // Zakładki: Rozdziały / Statystyki
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Rozdziały'),
                selected: _currentTab == _ChallengeTab.chapters,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _currentTab = _ChallengeTab.chapters;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Statystyki'),
                selected: _currentTab == _ChallengeTab.stats,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _currentTab = _ChallengeTab.stats;
                  });
                },
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Treść zakładki
        Expanded(
          child: _currentTab == _ChallengeTab.chapters
              ? _buildChaptersList(context, state, colorScheme)
              : _buildStatsTab(context, state, colorScheme, done, total),
        ),
      ],
    );
  }

  /// Zakładka „Rozdziały”
  Widget _buildChaptersList(
    BuildContext context,
    ReadingChallengeState state,
    ColorScheme colorScheme,
  ) {
    if (_chapters.isEmpty) {
      return const Center(
        child: Text('Brak listy rozdziałów do wyświetlenia.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _chapters.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = _chapters[index];
        final furthestIndex = _furthestChapterIndex ?? 0;
        final isDone = state.isActive && item.index <= furthestIndex;
        final isCurrent = state.furthestChapterRef == item.reference;

        IconData icon;
        Color iconColor;

        if (isCurrent) {
          icon = Icons.radio_button_checked;
          iconColor = colorScheme.primary;
        } else if (isDone) {
          icon = Icons.check_circle;
          iconColor = colorScheme.primary;
        } else {
          icon = Icons.radio_button_unchecked;
          iconColor = colorScheme.onSurface.withOpacity(0.4);
        }

        final tile = ListTile(
          onTap: () => _openChapter(item),
          leading: Icon(icon, color: iconColor),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight:
                  isCurrent ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            'Księga ${item.bookCode}, rozdział ${item.chapterNumber}',
          ),
          trailing: const Icon(Icons.chevron_right),
        );

        // Delikatne wyróżnienie bieżącego rozdziału – jasne tło + zaokrąglenie
        if (isCurrent) {
          return Container(
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: tile,
          );
        }

        return tile;
      },
    );
  }

  /// Zakładka „Statystyki”
  Widget _buildStatsTab(
    BuildContext context,
    ReadingChallengeState state,
    ColorScheme colorScheme,
    int done,
    int total,
  ) {
    final started = state.startedAt;
    int days = 0;
    double avgPerDay = 0.0;

    if (started != null) {
      final now = DateTime.now();
      days = now.difference(started).inDays + 1; // min. 1 dzień
      if (days > 0 && done > 0) {
        avgPerDay = done / days;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              'Przeczytano $done z $total rozdziałów.',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (started != null) ...[
              Text(
                'Wyzwanie trwa od ${_formatDate(started)} (ok. $days dni).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              avgPerDay > 0
                  ? 'Średnio ${(avgPerDay).toStringAsFixed(1)} rozdziału na dzień.'
                  : 'Czytaj regularnie, aby zobaczyć średnią liczbę rozdziałów na dzień.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterItem {
  final int index;
  final String reference;
  final String bookCode;
  final int chapterNumber;
  final String title;

  _ChapterItem({
    required this.index,
    required this.reference,
    required this.bookCode,
    required this.chapterNumber,
    required this.title,
  });
}

enum _ChallengeTab {
  chapters,
  stats,
}
