import 'package:flutter/material.dart';

import '../../shared/services/journal_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/models/book_models.dart';
import '../../shared/widgets/section_header.dart';

class JournalScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;
  final bool openInitialComposer;
  final bool closeAfterInitialComposer;
  final String? initialContent;
  final String? initialQuoteText;
  final String? initialQuoteRef;
  final String? initialComposerTitle;
  final String? initialComposerHint;
  final String? initialContentPrefix;
  final String? initialEntryId;

  const JournalScreen({
    super.key,
    this.onNavigateToTab,
    this.openInitialComposer = false,
    this.closeAfterInitialComposer = false,
    this.initialContent,
    this.initialQuoteText,
    this.initialQuoteRef,
    this.initialComposerTitle,
    this.initialComposerHint,
    this.initialContentPrefix,
    this.initialEntryId,
  });

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final JournalService _journalService = JournalService();
  final PreferencesService _prefs = PreferencesService();
  final FavoritesService _favoritesService = FavoritesService();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _entryKeys = {};

  late Future<List<JournalEntry>> _entriesFuture;
  bool _initialComposerOpened = false;
  bool _initialEntryRevealScheduled = false;
  String? _highlightedEntryId;
  _JournalSortOrder _sortOrder = _JournalSortOrder.newestFirst;
  _JournalSourceFilter _sourceFilter = _JournalSourceFilter.all;
  final Set<int> _expandedYears = {};
  final Set<String> _expandedMonths = {};
  bool _archiveExpansionInitialized = false;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _journalService.getEntries();
    _highlightedEntryId = widget.initialEntryId;

    if (widget.openInitialComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialComposer();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _entriesFuture = _journalService.getEntries();
    });
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

  String _formatEntryDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.day} ${_monthShortName(local.month)} · '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _monthName(int month) {
    const names = [
      'Styczeń',
      'Luty',
      'Marzec',
      'Kwiecień',
      'Maj',
      'Czerwiec',
      'Lipiec',
      'Sierpień',
      'Wrzesień',
      'Październik',
      'Listopad',
      'Grudzień',
    ];
    return names[month - 1];
  }

  String _monthShortName(int month) {
    const names = [
      'sty',
      'lut',
      'mar',
      'kwi',
      'maj',
      'cze',
      'lip',
      'sie',
      'wrz',
      'paź',
      'lis',
      'gru',
    ];
    return names[month - 1];
  }

  String _monthKey(int year, int month) => '$year-$month';

  String _entryCountLabel(int count) {
    final mod100 = count % 100;
    final mod10 = count % 10;
    final suffix = count == 1
        ? 'wpis'
        : mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)
        ? 'wpisy'
        : 'wpisów';
    return '$count $suffix';
  }

  int _compareDates(DateTime a, DateTime b) {
    return _sortOrder == _JournalSortOrder.newestFirst
        ? b.compareTo(a)
        : a.compareTo(b);
  }

  bool _matchesSourceFilter(JournalEntry entry) {
    return switch (_sourceFilter) {
      _JournalSourceFilter.all => true,
      _JournalSourceFilter.formation =>
        _detectEntrySource(entry) == _JournalEntrySource.formation,
      _JournalSourceFilter.own =>
        _detectEntrySource(entry) == _JournalEntrySource.own,
      _JournalSourceFilter.reading =>
        _detectEntrySource(entry) == _JournalEntrySource.reading,
    };
  }

  _JournalEntrySource _detectEntrySource(JournalEntry entry) {
    final content = entry.content.toLowerCase();
    if (content.contains('droga naśladowania') ||
        content.contains('droga nasladowania') ||
        content.contains('dzień ') && content.contains('moja refleksja')) {
      return _JournalEntrySource.formation;
    }

    final hasQuote =
        (entry.quoteText?.trim().isNotEmpty ?? false) ||
        (entry.quoteRef?.trim().isNotEmpty ?? false);
    if (hasQuote) {
      return _JournalEntrySource.reading;
    }

    return _JournalEntrySource.own;
  }

  String _sourceLabelFor(JournalEntry entry) {
    return switch (_detectEntrySource(entry)) {
      _JournalEntrySource.formation => 'Droga naśladowania',
      _JournalEntrySource.reading => 'Czytanie',
      _JournalEntrySource.own => 'Własna notatka',
    };
  }

  String? _formationDayLabel(JournalEntry entry) {
    final match = RegExp(
      r'Dzień\s+\d+\s+z\s+\d+',
      caseSensitive: false,
    ).firstMatch(entry.content);
    return match?.group(0);
  }

  List<_JournalArchiveYear> _buildArchiveYears(List<JournalEntry> entries) {
    final filtered = entries.where(_matchesSourceFilter).toList()
      ..sort((a, b) => _compareDates(a.createdAt, b.createdAt));

    final yearBuckets = <int, Map<int, List<JournalEntry>>>{};
    for (final entry in filtered) {
      final local = entry.createdAt.toLocal();
      yearBuckets
          .putIfAbsent(local.year, () => <int, List<JournalEntry>>{})
          .putIfAbsent(local.month, () => <JournalEntry>[])
          .add(entry);
    }

    final years = yearBuckets.keys.toList()
      ..sort(
        (a, b) => _sortOrder == _JournalSortOrder.newestFirst
            ? b.compareTo(a)
            : a.compareTo(b),
      );

    return [
      for (final year in years)
        _JournalArchiveYear(
          year: year,
          months: [
            for (final month
                in (yearBuckets[year]!.keys.toList()..sort(
                  (a, b) => _sortOrder == _JournalSortOrder.newestFirst
                      ? b.compareTo(a)
                      : a.compareTo(b),
                )))
              _JournalArchiveMonth(
                month: month,
                entries: yearBuckets[year]![month]!
                  ..sort((a, b) => _compareDates(a.createdAt, b.createdAt)),
              ),
          ],
        ),
    ];
  }

  int? _latestYear(List<_JournalArchiveYear> years) {
    if (years.isEmpty) return null;
    return years.map((year) => year.year).reduce((a, b) => a > b ? a : b);
  }

  int? _latestMonth(_JournalArchiveYear year) {
    if (year.months.isEmpty) return null;
    return year.months
        .map((month) => month.month)
        .reduce((a, b) => a > b ? a : b);
  }

  _JournalArchiveYear? _archiveYearByNumber(
    List<_JournalArchiveYear> years,
    int year,
  ) {
    for (final archiveYear in years) {
      if (archiveYear.year == year) return archiveYear;
    }
    return null;
  }

  bool _archiveMonthExists(_JournalArchiveYear year, int month) {
    return year.months.any((archiveMonth) => archiveMonth.month == month);
  }

  void _expandDefaultArchiveSection(List<_JournalArchiveYear> years) {
    if (years.isEmpty) return;

    final now = DateTime.now();
    final currentYear = _archiveYearByNumber(years, now.year);
    final targetYear =
        currentYear ?? _archiveYearByNumber(years, _latestYear(years)!);
    if (targetYear == null) return;

    final targetMonth =
        currentYear != null && _archiveMonthExists(currentYear, now.month)
        ? now.month
        : _latestMonth(targetYear);

    _expandedYears.add(targetYear.year);
    if (targetMonth != null) {
      _expandedMonths.add(_monthKey(targetYear.year, targetMonth));
    }
  }

  void _expandHighlightedEntrySection(List<_JournalArchiveYear> years) {
    final entryId = widget.initialEntryId;
    if (entryId == null || entryId.isEmpty) return;

    for (final year in years) {
      for (final month in year.months) {
        final hasEntry = month.entries.any((entry) => entry.id == entryId);
        if (!hasEntry) continue;

        _expandedYears.add(year.year);
        _expandedMonths.add(_monthKey(year.year, month.month));
        return;
      }
    }
  }

  void _ensureArchiveExpansion(List<_JournalArchiveYear> years) {
    if (years.isEmpty) {
      _expandedYears.clear();
      _expandedMonths.clear();
      _archiveExpansionInitialized = true;
      return;
    }

    if (!_archiveExpansionInitialized) {
      _archiveExpansionInitialized = true;
      _expandDefaultArchiveSection(years);
      _expandHighlightedEntrySection(years);
      return;
    }

    final hadExpandedYears = _expandedYears.isNotEmpty;
    final hadExpandedMonthsByYear = <int>{};
    for (final monthKey in _expandedMonths) {
      final parts = monthKey.split('-');
      if (parts.length != 2) continue;
      final year = int.tryParse(parts.first);
      if (year != null) {
        hadExpandedMonthsByYear.add(year);
      }
    }

    final yearNumbers = years.map((year) => year.year).toSet();
    final validMonthKeys = <String>{};
    final yearByNumber = <int, _JournalArchiveYear>{};

    for (final year in years) {
      yearByNumber[year.year] = year;
      for (final month in year.months) {
        validMonthKeys.add(_monthKey(year.year, month.month));
      }
    }

    _expandedYears.removeWhere((year) => !yearNumbers.contains(year));
    _expandedMonths.removeWhere(
      (monthKey) => !validMonthKeys.contains(monthKey),
    );

    if (hadExpandedYears && _expandedYears.isEmpty) {
      _expandDefaultArchiveSection(years);
      return;
    }

    for (final year in _expandedYears.toList()) {
      final archiveYear = yearByNumber[year];
      if (archiveYear == null) continue;

      final hasExpandedMonth = archiveYear.months.any(
        (month) => _expandedMonths.contains(_monthKey(year, month.month)),
      );
      if (!hasExpandedMonth && hadExpandedMonthsByYear.contains(year)) {
        final fallbackMonth = _latestMonth(archiveYear);
        if (fallbackMonth != null) {
          _expandedMonths.add(_monthKey(year, fallbackMonth));
        }
      }
    }
  }

  void _toggleYear(_JournalArchiveYear year) {
    setState(() {
      if (_expandedYears.contains(year.year)) {
        _expandedYears.remove(year.year);
      } else {
        _expandedYears.add(year.year);
        final hasExpandedMonth = year.months.any(
          (month) =>
              _expandedMonths.contains(_monthKey(year.year, month.month)),
        );
        if (!hasExpandedMonth) {
          final fallbackMonth = _latestMonth(year);
          if (fallbackMonth != null) {
            _expandedMonths.add(_monthKey(year.year, fallbackMonth));
          }
        }
      }
    });
  }

  void _toggleMonth(int year, int month) {
    final key = _monthKey(year, month);
    setState(() {
      if (_expandedMonths.contains(key)) {
        _expandedMonths.remove(key);
      } else {
        _expandedMonths.add(key);
      }
    });
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    await _journalService.deleteEntry(entry.id);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Wpis dziennika usunięty.')));
  }

  Future<void> _openInitialComposer() async {
    if (_initialComposerOpened) return;
    _initialComposerOpened = true;

    final saved = await _addManualEntry(
      initialContent: widget.initialContent,
      quoteText: widget.initialQuoteText,
      quoteRef: widget.initialQuoteRef,
      title: widget.initialComposerTitle,
      hintText: widget.initialComposerHint,
      contentPrefix: widget.initialContentPrefix,
    );

    if (!mounted || !widget.closeAfterInitialComposer) return;
    Navigator.of(context).pop(saved);
  }

  Future<bool> _addManualEntry({
    String? initialContent,
    String? quoteText,
    String? quoteRef,
    String? title,
    String? hintText,
    String? contentPrefix,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return _JournalEntryComposerDialog(
              initialContent: initialContent,
              title: title ?? 'Nowy wpis dziennika',
              hintText:
                  hintText ??
                  'Co się dziś wydarzyło? Co mówi do Ciebie Pan?\n\n'
                      'Napisz krótki zapis myśli, modlitwy, decyzji...',
              onSave: (text) async {
                if (text.isNotEmpty) {
                  final content = contentPrefix == null
                      ? text
                      : '$contentPrefix$text';
                  await _journalService.addEntry(
                    content: content,
                    quoteText: quoteText,
                    quoteRef: quoteRef,
                  );
                  await _refresh();
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(text.isNotEmpty);
              },
            );
          },
        ) ??
        false;
  }

  /// Edycja istniejącego wpisu – prosty dialog z prewypełnionym tekstem.
  Future<void> _editEntry(JournalEntry entry) async {
    const reflectionMarker = 'Moja refleksja:';
    final markerIndex = entry.content.indexOf(reflectionMarker);
    final hasReflectionMarker = markerIndex != -1;
    final contentPrefix = hasReflectionMarker
        ? entry.content.substring(0, markerIndex + reflectionMarker.length)
        : null;
    final editableContent = hasReflectionMarker
        ? entry.content.substring(markerIndex + reflectionMarker.length).trim()
        : entry.content;
    final controller = TextEditingController(text: editableContent);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edytuj wpis'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Zaktualizuj treść swojego wpisu...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                final updatedContent = contentPrefix == null
                    ? text
                    : '$contentPrefix\n$text';

                // Jeśli nic się nie zmieniło – po prostu zamknij
                if (text.isEmpty || updatedContent == entry.content) {
                  Navigator.of(dialogContext).pop();
                  return;
                }

                // Aktualizacja istniejącego wpisu (bez zmiany id/createdAt/cytatu)
                await _journalService.updateEntryContent(
                  id: entry.id,
                  content: updatedContent,
                );

                await _refresh();
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Wpis dziennika zaktualizowany.'),
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

  /// Dodaje cytat z wpisu do ulubionych (jeśli cytat i referencja są dostępne)
  /// i zamyka bottomsheet.
  Future<void> _addEntryQuoteToFavorites(
    JournalEntry entry,
    BuildContext sheetContext,
  ) async {
    final text = entry.quoteText?.trim();
    final ref = entry.quoteRef?.trim();

    if (text == null || text.isEmpty || ref == null || ref.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ten wpis nie ma cytatu do dodania do ulubionych.'),
        ),
      );
      return;
    }

    int index = 0;
    final parts = ref.split('-');
    if (parts.length >= 3) {
      final parsed = int.tryParse(parts[2]);
      if (parsed != null) {
        index = parsed;
      }
    }

    final paragraph = BookParagraph(index: index, reference: ref, text: text);

    await _favoritesService.addOrUpdateFavoriteForParagraph(
      paragraph,
      note: null,
    );

    if (!mounted) return;

    // zamknij bottomsheet
    Navigator.of(sheetContext).pop();

    // i pokaż komunikat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cytat dodany do ulubionych.')),
    );
  }

  /// "Zobacz w książce" – ustawiamy jumpChapterRef + (jeśli się da) jumpParagraphNumber,
  /// a potem przełączamy na zakładkę "Czytanie".
  Future<void> _goToBookFromEntry(
    JournalEntry entry,
    BuildContext sheetContext,
  ) async {
    final quoteRef = entry.quoteRef;
    if (quoteRef == null || quoteRef.isEmpty) {
      Navigator.of(sheetContext).pop();
      return;
    }

    final parts = quoteRef.split('-');

    // chapterRef np. "I-3-2" -> "I-3"
    String chapterRef;
    if (parts.length >= 2) {
      chapterRef = '${parts[0]}-${parts[1]}';
    } else {
      chapterRef = quoteRef;
    }

    // 1) ustawiamy skok do rozdziału
    await _prefs.setJumpChapterRef(chapterRef);

    // 2) jeśli quoteRef zawiera numer akapitu (I-3-7), spróbuj go sparsować
    if (parts.length >= 3) {
      final num = int.tryParse(parts[2]);
      if (num != null) {
        await _prefs.setJumpParagraphNumber(num);
      } else {
        await _prefs.clearJumpParagraphNumber();
      }
    } else {
      await _prefs.clearJumpParagraphNumber();
    }

    if (!mounted) return;

    // 3) zamykamy bottomsheet ze szczegółami wpisu
    Navigator.of(sheetContext).pop();

    // 4) przełączamy na tab "Czytanie"
    widget.onNavigateToTab?.call(1);

    // 5) zamykamy ekran dziennika (jeśli jest osobnym route’em)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openEntryDetails(JournalEntry entry) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final displayContent = _buildEntryDisplayContent(entry);

        final hasQuote =
            entry.quoteText != null &&
            entry.quoteText!.trim().isNotEmpty &&
            entry.quoteRef != null &&
            entry.quoteRef!.trim().isNotEmpty;

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_rounded, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDateTime(entry.createdAt),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (displayContent.reflectionText.isNotEmpty) ...[
                          const Text(
                            'Moja refleksja:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            displayContent.reflectionText,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (displayContent.contextText.isNotEmpty) ...[
                          Text(
                            displayContent.contextText,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (entry.quoteText != null &&
                            entry.quoteText!.trim().isNotEmpty) ...[
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'Fragment:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.quoteText!,
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (hasQuote)
                        TextButton.icon(
                          icon: const Icon(Icons.favorite_border),
                          label: const Text('Do ulubionych'),
                          onPressed: () =>
                              _addEntryQuoteToFavorites(entry, sheetContext),
                        ),
                      if (entry.quoteRef != null &&
                          entry.quoteRef!.trim().isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Zobacz w książce'),
                          onPressed: () =>
                              _goToBookFromEntry(entry, sheetContext),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Zamknij'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _JournalEntryDisplayContent _buildEntryDisplayContent(JournalEntry entry) {
    const marker = 'Moja refleksja:';
    final content = entry.content.trim();
    final markerIndex = content.indexOf(marker);

    if (markerIndex == -1) {
      return _JournalEntryDisplayContent(reflectionText: content);
    }

    final contextText = content.substring(0, markerIndex).trim();
    final reflectionText = content
        .substring(markerIndex + marker.length)
        .trim();

    return _JournalEntryDisplayContent(
      contextText: contextText,
      reflectionText: reflectionText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addManualEntry,
        tooltip: 'Nowy wpis',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<JournalEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'Dziennik duchowy',
                  subtitle: 'Twoje refleksje i notatki z lektury.',
                  icon: Icons.edit_note,
                  showBackButton: true,
                ),
                Expanded(child: _buildEntriesContent(context, snapshot)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntriesContent(
    BuildContext context,
    AsyncSnapshot<List<JournalEntry>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: Text(
          'Błąd wczytywania dziennika:\n${snapshot.error}',
          textAlign: TextAlign.center,
        ),
      );
    }

    final entries = snapshot.data ?? [];
    final archiveYears = _buildArchiveYears(entries);
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'Brak wpisów w dzienniku.\n\n'
            'Dodaj pierwszy wpis z losowego cytatu, z czytnika\n'
            'albo za pomocą przycisku „+” w prawym dolnym rogu.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (archiveYears.isNotEmpty) {
      _ensureArchiveExpansion(archiveYears);
    }
    _scheduleInitialEntryReveal(entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JournalArchiveControls(
          selectedFilter: _sourceFilter,
          sortOrder: _sortOrder,
          onFilterChanged: (filter) {
            setState(() {
              _sourceFilter = filter;
            });
          },
          onSortChanged: (order) {
            setState(() {
              _sortOrder = order;
            });
          },
        ),
        Expanded(
          child: archiveYears.isEmpty
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    children: const [
                      Text(
                        'Brak wpisów dla wybranego filtra.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                    children: [
                      for (final year in archiveYears) ...[
                        _JournalYearHeader(
                          year: year.year,
                          expanded: _expandedYears.contains(year.year),
                          countLabel: _entryCountLabel(year.entryCount),
                          onTap: () => _toggleYear(year),
                        ),
                        if (_expandedYears.contains(year.year))
                          for (final month in year.months) ...[
                            _JournalMonthHeader(
                              title: _monthName(month.month),
                              countLabel: _entryCountLabel(
                                month.entries.length,
                              ),
                              expanded: _expandedMonths.contains(
                                _monthKey(year.year, month.month),
                              ),
                              onTap: () => _toggleMonth(year.year, month.month),
                            ),
                            if (_expandedMonths.contains(
                              _monthKey(year.year, month.month),
                            ))
                              for (final entry in month.entries)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    top: 4,
                                    bottom: 8,
                                  ),
                                  child: _buildEntryTile(context, entry),
                                ),
                          ],
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(BuildContext context, JournalEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final isHighlighted = entry.id == _highlightedEntryId;
    final displayContent = _buildEntryDisplayContent(entry);
    final sourceLabel = _sourceLabelFor(entry);
    final formationDayLabel = _formationDayLabel(entry);

    return KeyedSubtree(
      key: _keyForEntry(entry.id),
      child: Dismissible(
        key: ValueKey(entry.id),
        direction: DismissDirection.horizontal,
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: colorScheme.primary.withValues(alpha: 0.8),
          child: const Row(
            children: [
              Icon(Icons.edit, color: Colors.white),
              SizedBox(width: 8),
              Text('Edytuj', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: colorScheme.error,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Usuń', style: TextStyle(color: Colors.white)),
              SizedBox(width: 8),
              Icon(Icons.delete, color: Colors.white),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _editEntry(entry);
            return false;
          } else if (direction == DismissDirection.endToStart) {
            return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Usuń wpis dziennika'),
                    content: const Text('Na pewno chcesz usunąć ten wpis?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Anuluj'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Usuń'),
                      ),
                    ],
                  ),
                ) ??
                false;
          }
          return false;
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            _deleteEntry(entry);
          }
        },
        child: ListTile(
          tileColor: isHighlighted
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surface.withValues(alpha: 0.32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          onTap: () => _openEntryDetails(entry),
          title: Text(
            _formatEntryDateTime(entry.createdAt),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formationDayLabel == null
                      ? sourceLabel
                      : '$sourceLabel · $formationDayLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.quoteText != null &&
                    entry.quoteText!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '„${entry.quoteText!.trim()}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurface.withValues(alpha: 0.78),
                    ),
                  ),
                ],
                if (displayContent.reflectionText.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    displayContent.reflectionText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  GlobalKey _keyForEntry(String id) {
    return _entryKeys.putIfAbsent(id, GlobalKey.new);
  }

  void _scheduleInitialEntryReveal(List<JournalEntry> entries) {
    final entryId = widget.initialEntryId;
    if (_initialEntryRevealScheduled ||
        entryId == null ||
        entryId.isEmpty ||
        !entries.any((entry) => entry.id == entryId)) {
      return;
    }

    _initialEntryRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _entryKeys[entryId]?.currentContext;
      if (context == null) return;

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
    });
  }
}

enum _JournalSortOrder { newestFirst, oldestFirst }

enum _JournalSourceFilter { all, formation, own, reading }

enum _JournalEntrySource { formation, own, reading }

class _JournalArchiveYear {
  final int year;
  final List<_JournalArchiveMonth> months;

  const _JournalArchiveYear({required this.year, required this.months});

  int get entryCount =>
      months.fold<int>(0, (total, month) => total + month.entries.length);
}

class _JournalArchiveMonth {
  final int month;
  final List<JournalEntry> entries;

  const _JournalArchiveMonth({required this.month, required this.entries});
}

class _JournalArchiveControls extends StatelessWidget {
  final _JournalSourceFilter selectedFilter;
  final _JournalSortOrder sortOrder;
  final ValueChanged<_JournalSourceFilter> onFilterChanged;
  final ValueChanged<_JournalSortOrder> onSortChanged;

  const _JournalArchiveControls({
    required this.selectedFilter,
    required this.sortOrder,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChipButton(
                  label: 'Wszystkie',
                  selected: selectedFilter == _JournalSourceFilter.all,
                  onSelected: () => onFilterChanged(_JournalSourceFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChipButton(
                  label: 'Droga',
                  selected: selectedFilter == _JournalSourceFilter.formation,
                  onSelected: () =>
                      onFilterChanged(_JournalSourceFilter.formation),
                ),
                const SizedBox(width: 8),
                _FilterChipButton(
                  label: 'Własne',
                  selected: selectedFilter == _JournalSourceFilter.own,
                  onSelected: () => onFilterChanged(_JournalSourceFilter.own),
                ),
                const SizedBox(width: 8),
                _FilterChipButton(
                  label: 'Czytanie',
                  selected: selectedFilter == _JournalSourceFilter.reading,
                  onSelected: () =>
                      onFilterChanged(_JournalSourceFilter.reading),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<_JournalSortOrder>(
              initialValue: sortOrder,
              tooltip: 'Sortowanie',
              onSelected: onSortChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _JournalSortOrder.newestFirst,
                  child: Text('Najnowsze najpierw'),
                ),
                PopupMenuItem(
                  value: _JournalSortOrder.oldestFirst,
                  child: Text('Najstarsze najpierw'),
                ),
              ],
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sortOrder == _JournalSortOrder.newestFirst
                            ? 'Najnowsze najpierw'
                            : 'Najstarsze najpierw',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: colorScheme.primary.withValues(alpha: 0.18),
      backgroundColor: colorScheme.surface.withValues(alpha: 0.34),
      side: BorderSide(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.7)
            : colorScheme.outline.withValues(alpha: 0.16),
      ),
      labelStyle: TextStyle(
        color: selected ? colorScheme.primary : colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _JournalYearHeader extends StatelessWidget {
  final int year;
  final String countLabel;
  final bool expanded;
  final VoidCallback onTap;

  const _JournalYearHeader({
    required this.year,
    required this.countLabel,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: year.toString()),
                      TextSpan(
                        text: ' · $countLabel',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.66),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.chevron_right_rounded,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalMonthHeader extends StatelessWidget {
  final String title;
  final String countLabel;
  final bool expanded;
  final VoidCallback onTap;

  const _JournalMonthHeader({
    required this.title,
    required this.countLabel,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 2, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$title · $countLabel',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.chevron_right_rounded,
                color: colorScheme.primary.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalEntryComposerDialog extends StatefulWidget {
  final String? initialContent;
  final String title;
  final String hintText;
  final Future<void> Function(String text) onSave;

  const _JournalEntryComposerDialog({
    required this.initialContent,
    required this.title,
    required this.hintText,
    required this.onSave,
  });

  @override
  State<_JournalEntryComposerDialog> createState() =>
      _JournalEntryComposerDialogState();
}

class _JournalEntryDisplayContent {
  final String contextText;
  final String reflectionText;

  const _JournalEntryDisplayContent({
    this.contextText = '',
    required this.reflectionText,
  });
}

class _JournalEntryComposerDialogState
    extends State<_JournalEntryComposerDialog> {
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSave(_controller.text.trim());
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: widget.hintText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
