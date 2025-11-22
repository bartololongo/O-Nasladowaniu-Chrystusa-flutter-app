import 'package:flutter/material.dart';

import '../../shared/services/journal_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/models/reader_user_models.dart';

class JournalScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const JournalScreen({super.key, this.onNavigateToTab});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final JournalService _journalService = JournalService();
  final PreferencesService _prefs = PreferencesService();

  late Future<List<JournalEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _journalService.getEntries();
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

  Future<void> _addManualEntry() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nowy wpis dziennika'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Co się dziś wydarzyło? Co mówi do Ciebie Pan?\n\n'
                  'Napisz krótki zapis myśli, modlitwy, decyzji...',
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
                if (text.isNotEmpty) {
                  await _journalService.addEntry(
                    content: text,
                    quoteText: null,
                    quoteRef: null,
                  );
                  await _refresh();
                }
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _goToBookFromEntry(
    JournalEntry entry,
    BuildContext sheetContext,
  ) async {
    final quoteRef = entry.quoteRef;
    if (quoteRef == null || quoteRef.isEmpty) {
      Navigator.of(sheetContext).pop();
      return;
    }

    // quoteRef np. "I-3-2" -> chapterRef "I-3"
    final parts = quoteRef.split('-');
    String chapterRef;
    if (parts.length >= 2) {
      chapterRef = '${parts[0]}-${parts[1]}';
    } else {
      chapterRef = quoteRef;
    }

    // 1) ustawiamy skok do rozdziału
    await _prefs.setJumpChapterRef(chapterRef);

    if (!mounted) return;

    // 2) zamykamy bottomsheet ze szczegółami wpisu
    Navigator.of(sheetContext).pop();

    // 3) przełączamy na tab "Czytanie" w rodzicu (jeśli callback został przekazany)
    widget.onNavigateToTab?.call(1);

    // 4) zamykamy ekran dziennika (jeśli jest osobnym route’em na stosie)
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

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                const SizedBox(height: 12),
                if (entry.quoteText != null &&
                    entry.quoteText!.trim().isNotEmpty) ...[
                  Text(
                    entry.quoteText!,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurface.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                ],
                Text(
                  entry.content,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dziennik duchowy'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManualEntry,
        tooltip: 'Nowy wpis',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<JournalEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
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

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final e = entries[index];
                final colorScheme = Theme.of(context).colorScheme;

                return Dismissible(
                  key: ValueKey(e.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: Theme.of(context).colorScheme.error,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
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
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: const Text('Usuń'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) => _deleteEntry(e),
                  child: ListTile(
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
                );
              },
            ),
          );
        },
      ),
    );
  }
}
