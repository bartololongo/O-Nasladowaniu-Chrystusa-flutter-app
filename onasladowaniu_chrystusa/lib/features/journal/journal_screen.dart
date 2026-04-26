import 'package:flutter/material.dart';

import '../../shared/services/journal_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/models/reader_user_models.dart';
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

  Future<void> _deleteEntry(JournalEntry entry) async {
    await _journalService.deleteEntry(entry.id);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wpis dziennika usunięty.')),
    );
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
              hintText: hintText ??
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
        ? entry.content.substring(
            0,
            markerIndex + reflectionMarker.length,
          )
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

    final paragraph = BookParagraph(
      index: index,
      reference: ref,
      text: text,
    );

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

        final hasQuote = entry.quoteText != null &&
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
                      Icon(
                        Icons.menu_book_rounded,
                        color: colorScheme.primary,
                      ),
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
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.7),
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
                              color: colorScheme.onSurface.withOpacity(0.9),
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
    final reflectionText =
        content.substring(markerIndex + marker.length).trim();

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
                Expanded(
                  child: _buildEntriesContent(context, snapshot),
                ),
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

    final colorScheme = Theme.of(context).colorScheme;

    _scheduleInitialEntryReveal(entries);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final e = entries[index];
          final isHighlighted = e.id == _highlightedEntryId;

          return KeyedSubtree(
            key: _keyForEntry(e.id),
            child: Dismissible(
              key: ValueKey(e.id),
              direction: DismissDirection.horizontal,
              // Przeciągnięcie w prawo – EDYCJA
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: colorScheme.primary.withOpacity(0.8),
                child: const Row(
                  children: [
                    Icon(Icons.edit, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Edytuj',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Przeciągnięcie w lewo – USUWANIE
              secondaryBackground: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: Theme.of(context).colorScheme.error,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Usuń',
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.delete, color: Colors.white),
                  ],
                ),
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  // EDYCJA
                  await _editEntry(e);
                  // Nie usuwamy elementu z listy via Dismissible
                  return false;
                } else if (direction == DismissDirection.endToStart) {
                  // USUWANIE – jak dotychczas
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Usuń wpis dziennika'),
                          content: const Text(
                            'Na pewno chcesz usunąć ten wpis?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(ctx).pop(false),
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
                  _deleteEntry(e);
                }
              },
              child: ListTile(
                tileColor: isHighlighted
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () => _openEntryDetails(e),
                title: Text(
                  _formatDateTime(e.createdAt),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.quoteText != null &&
                        e.quoteText!.trim().isNotEmpty) ...[
                      Text(
                        e.quoteText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      e.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          );
        },
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
