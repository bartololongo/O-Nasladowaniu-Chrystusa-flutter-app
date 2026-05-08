import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/global_search_models.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/services/global_search_service.dart';
import '../../shared/services/preferences_service.dart';
import '../journal/journal_screen.dart';
import '../reader/reader_screen.dart';

class SearchScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;
  final void Function(Widget screen)? onOpenMoreScreen;
  final VoidCallback? onBookResultSelectedFromReader;
  final String? initialQuery;

  const SearchScreen({
    super.key,
    this.onNavigateToTab,
    this.onOpenMoreScreen,
    this.onBookResultSelectedFromReader,
    this.initialQuery,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final GlobalSearchService _searchService = GlobalSearchService();
  final PreferencesService _preferencesService = PreferencesService();
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  List<GlobalSearchResult> _results = [];
  bool _isLoading = false;
  String _query = '';
  int _searchToken = 0;
  GlobalSearchResultType? _activeFilter;

  static const List<GlobalSearchResultType> _filterOrder = [
    GlobalSearchResultType.journalEntry,
    GlobalSearchResultType.bookParagraph,
    GlobalSearchResultType.bookmark,
    GlobalSearchResultType.favorite,
  ];

  @override
  void initState() {
    super.initState();

    final initialQuery = widget.initialQuery?.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (initialQuery == null || initialQuery.length < 2) {
      return;
    }

    _controller.text = initialQuery;
    _controller.selection = TextSelection.collapsed(
      offset: initialQuery.length,
    );
    _query = initialQuery;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runSearch(initialQuery));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String value) async {
    final token = ++_searchToken;
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _query = query;
        _results = [];
        _isLoading = false;
        _activeFilter = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _isLoading = true;
    });

    final results = await _searchService.search(query);
    if (!mounted || token != _searchToken) return;

    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  void _hideKeyboard() {
    FocusScope.of(context).unfocus();
  }

  String get _currentSearchQuery {
    final stateQuery = _query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (stateQuery.isNotEmpty) {
      return stateQuery;
    }

    return _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Szukaj')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _hideKeyboard(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            _runSearch('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  hintText: 'Szukaj w książce, notatkach i zapisach',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideKeyboard,
                child: _buildBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Wpisz co najmniej 2 znaki, aby rozpocząć wyszukiwanie.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isLoading) {
      return Column(
        children: [
          _buildFilterBar(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_results.isEmpty) {
      return Column(
        children: [
          _buildFilterBar(),
          const Expanded(child: Center(child: Text('Brak wyników.'))),
        ],
      );
    }

    final filteredResults = _filteredResults;
    if (filteredResults.isEmpty) {
      return Column(
        children: [
          _buildFilterBar(),
          const Expanded(
            child: Center(child: Text('Brak wyników w tej kategorii.')),
          ),
        ],
      );
    }

    final groups = <GlobalSearchResultType, List<GlobalSearchResult>>{
      for (final type in GlobalSearchResultType.values)
        type: filteredResults.where((result) => result.type == type).toList(),
    };

    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final type in GlobalSearchResultType.values)
                if (groups[type]!.isNotEmpty) ...[
                  if (_activeFilter == null)
                    _SectionHeader(title: _sectionTitle(type)),
                  ...groups[type]!.map(
                    (result) => _SearchResultTile(
                      result: result,
                      icon: _iconForType(result.type),
                      onTap: () => _showResultDetails(context, result),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ],
    );
  }

  List<GlobalSearchResult> get _filteredResults {
    final activeFilter = _activeFilter;
    if (activeFilter == null) return _results;

    return _results.where((result) => result.type == activeFilter).toList();
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _FilterChipItem(
            label: 'Wszystko',
            selected: _activeFilter == null,
            onSelected: () {
              setState(() {
                _activeFilter = null;
              });
            },
          ),
          for (final type in _filterOrder) ...[
            const SizedBox(width: 8),
            _FilterChipItem(
              label: _sectionTitle(type),
              selected: _activeFilter == type,
              onSelected: () {
                setState(() {
                  _activeFilter = type;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showResultDetails(BuildContext context, GlobalSearchResult result) {
    _hideKeyboard();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(_iconForType(result.type)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          result.sourceLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    result.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(result.subtitle),
                  if ((result.chapterRef ?? result.paragraphRef) != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Referencja: ${result.paragraphRef ?? result.chapterRef}',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(result.snippet, style: const TextStyle(height: 1.45)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Zamknij'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _goToResult(result);
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(_goToButtonLabel(result.type)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _goToResult(GlobalSearchResult result) async {
    switch (result.type) {
      case GlobalSearchResultType.journalEntry:
        _openJournalResult(result);
        return;
      case GlobalSearchResultType.bookParagraph:
        await _openBookResult(result);
        return;
      case GlobalSearchResultType.bookmark:
        await _openBookmarkResult(result);
        return;
      case GlobalSearchResultType.favorite:
        await _openFavoriteResult(result);
        return;
    }
  }

  void _openJournalResult(GlobalSearchResult result) {
    final screen = JournalScreen(
      onNavigateToTab: widget.onNavigateToTab,
      initialEntryId: result.journalEntryId,
    );

    if (widget.onOpenMoreScreen != null) {
      widget.onOpenMoreScreen!(screen);
      return;
    }

    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/journal/from-search'),
        builder: (_) => screen,
      ),
    );
  }

  Future<void> _openBookResult(GlobalSearchResult result) async {
    final chapterRef =
        result.chapterRef ?? _chapterRefFromParagraphRef(result.paragraphRef);
    final searchQuery = _currentSearchQuery;

    if (chapterRef != null && chapterRef.isNotEmpty) {
      await _preferencesService.setJumpChapterRef(chapterRef);
      if (searchQuery.length >= 2) {
        await _preferencesService.setPendingReaderSearchQuery(searchQuery);
      }
    }

    await _preferencesService.clearJumpParagraphNumber();

    if (!mounted) return;
    final onBookResultSelectedFromReader =
        widget.onBookResultSelectedFromReader;
    if (onBookResultSelectedFromReader != null) {
      onBookResultSelectedFromReader();
      return;
    }

    await Navigator.of(context).pushReplacement(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/reader/from-search'),
        builder: (_) => const ReaderScreen(),
      ),
    );
  }

  Future<void> _openBookmarkResult(GlobalSearchResult result) async {
    final chapterRef = result.chapterRef;
    if (chapterRef != null && chapterRef.isNotEmpty) {
      await _preferencesService.setJumpChapterRef(chapterRef);
    }
    await _preferencesService.clearJumpParagraphNumber();

    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/reader/from-bookmark-search'),
        builder: (_) => const ReaderScreen(),
      ),
    );
  }

  Future<void> _openFavoriteResult(GlobalSearchResult result) async {
    final paragraphRef = result.paragraphRef;
    final chapterRef = _chapterRefFromParagraphRef(paragraphRef);

    if (chapterRef != null && chapterRef.isNotEmpty) {
      await _preferencesService.setJumpChapterRef(chapterRef);
    }

    final paragraphNumber = _paragraphNumberFromParagraphRef(paragraphRef);
    if (paragraphNumber != null) {
      await _preferencesService.setJumpParagraphNumber(paragraphNumber);
    } else {
      await _preferencesService.clearJumpParagraphNumber();
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/reader/from-favorite-search'),
        builder: (_) => const ReaderScreen(),
      ),
    );
  }

  String? _chapterRefFromParagraphRef(String? paragraphRef) {
    if (paragraphRef == null || paragraphRef.isEmpty) return null;

    final parts = paragraphRef.split('-');
    if (parts.length < 2) return paragraphRef;

    return '${parts[0]}-${parts[1]}';
  }

  int? _paragraphNumberFromParagraphRef(String? paragraphRef) {
    if (paragraphRef == null || paragraphRef.isEmpty) return null;

    final parts = paragraphRef.split('-');
    if (parts.length < 3) return null;

    return int.tryParse(parts[2]);
  }

  String _sectionTitle(GlobalSearchResultType type) {
    switch (type) {
      case GlobalSearchResultType.bookParagraph:
        return 'Książka';
      case GlobalSearchResultType.bookmark:
        return 'Zakładki';
      case GlobalSearchResultType.favorite:
        return 'Ulubione';
      case GlobalSearchResultType.journalEntry:
        return 'Dziennik';
    }
  }

  IconData _iconForType(GlobalSearchResultType type) {
    switch (type) {
      case GlobalSearchResultType.bookParagraph:
        return Icons.menu_book;
      case GlobalSearchResultType.bookmark:
        return Icons.bookmark;
      case GlobalSearchResultType.favorite:
        return Icons.format_quote;
      case GlobalSearchResultType.journalEntry:
        return Icons.edit_note;
    }
  }

  String _goToButtonLabel(GlobalSearchResultType type) {
    if (type == GlobalSearchResultType.journalEntry) {
      return 'Pokaż w dzienniku';
    }

    return 'Przejdź';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final GlobalSearchResult result;
  final IconData icon;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.result,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(result.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.subtitle),
            const SizedBox(height: 4),
            Text(result.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
